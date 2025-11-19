// ============================================================================
// Asynchronous FIFO for RHS2116 single-wire link
// 写时钟域：clk_wr (例如 clk_spi 24MHz)
// 读时钟域：clk_rd (例如 clk_link 80MHz)
// 默认参数：32bit 数据宽度，64 深度，可通过 ADDR_WIDTH 调整到 128 等
// ============================================================================
module async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 6     // FIFO 深度 = 2^ADDR_WIDTH，默认 64
)(
    // 写端口（clk_wr 域：RHS2116 SPI Master → FIFO）
    input  wire                   clk_wr,
    input  wire                   rst_wr_n,     // 写域复位，低有效

    input  wire                   wr_en,        // 写使能（高电平写入一拍）
    input  wire [DATA_WIDTH-1:0]  wr_data,      // 写入数据

    output wire                   wr_full,      // FIFO 满
    output wire                   wr_almost_full, // FIFO 接近满（可用于节流 SPI）

    // 读端口（clk_rd 域：FIFO → Frame Packer / Link）
    input  wire                   clk_rd,
    input  wire                   rst_rd_n,     // 读域复位，低有效

    input  wire                   rd_en,        // 读使能（高电平读出一拍）
    output reg  [DATA_WIDTH-1:0]  rd_data,      // 读出数据
    output wire                   rd_empty,     // FIFO 空
    output reg                    rd_valid      // 本拍 rd_data 有效
);

    // =========================================================================
    // 内部参数和寄存器定义
    // =========================================================================
    localparam PTR_WIDTH = ADDR_WIDTH + 1;      // 多一位用于 full/empty 判定
    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);

    // RAM
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // 写指针（bin / gray）
    reg [PTR_WIDTH-1:0] wr_ptr_bin;
    reg [PTR_WIDTH-1:0] wr_ptr_gray;

    // 读指针（bin / gray）
    reg [PTR_WIDTH-1:0] rd_ptr_bin;
    reg [PTR_WIDTH-1:0] rd_ptr_gray;

    // 对端指针同步（Gray 码）
    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;  // 到写域
    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;  // 到读域

    wire [PTR_WIDTH-1:0] rd_ptr_gray_sync; // 写域看到的读指针
    wire [PTR_WIDTH-1:0] wr_ptr_gray_sync; // 读域看到的写指针

    assign rd_ptr_gray_sync = rd_ptr_gray_sync2;
    assign wr_ptr_gray_sync = wr_ptr_gray_sync2;

    // =========================================================================
    // 二进制 ↔ Gray 码函数
    // =========================================================================
    // bin2gray: Gray = bin ^ (bin >> 1)
    function [PTR_WIDTH-1:0] bin2gray;
        input [PTR_WIDTH-1:0] bin;
        begin
            bin2gray = (bin >> 1) ^ bin;
        end
    endfunction

    // gray2bin 可选（这里不需要用到，不展开）

    // =========================================================================
    // 写时钟域逻辑
    // =========================================================================
    // 写指针更新 & 写入 RAM
    wire wr_push = wr_en && !wr_full;
    wire [PTR_WIDTH-1:0] wr_ptr_bin_next  = wr_ptr_bin + (wr_push ? 1'b1 : 1'b0);
    wire [PTR_WIDTH-1:0] wr_ptr_gray_next = bin2gray(wr_ptr_bin_next);

    integer i;
    always @(posedge clk_wr or negedge rst_wr_n) begin
        if (!rst_wr_n) begin
            wr_ptr_bin  <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;

            // 写 RAM
            if (wr_push) begin
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
            end
        end
    end

    // 同步读指针 Gray 到写域
    always @(posedge clk_wr or negedge rst_wr_n) begin
        if (!rst_wr_n) begin
            rd_ptr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // =========================================================================
    // 读时钟域逻辑
    // =========================================================================
    // 读指针更新 & RAM 读
    wire rd_pop = rd_en && !rd_empty;
    wire [PTR_WIDTH-1:0] rd_ptr_bin_next  = rd_ptr_bin + (rd_pop ? 1'b1 : 1'b0);
    wire [PTR_WIDTH-1:0] rd_ptr_gray_next = bin2gray(rd_ptr_bin_next);

    always @(posedge clk_rd or negedge rst_rd_n) begin
        if (!rst_rd_n) begin
            rd_ptr_bin  <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray <= {PTR_WIDTH{1'b0}};
            rd_data     <= {DATA_WIDTH{1'b0}};
            rd_valid    <= 1'b0;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;

            // rd_valid：当本拍真正 pop 时有效
            rd_valid <= rd_pop;

            if (rd_pop) begin
                rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
            end
        end
    end

    // 同步写指针 Gray 到读域
    always @(posedge clk_rd or negedge rst_rd_n) begin
        if (!rst_rd_n) begin
            wr_ptr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // =========================================================================
    // Empty / Full 判定（Gray 码标准写法）
    // =========================================================================
    // 空：读指针 == 同步过来的写指针
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync);

    // 满：写指针下一值 == 读指针 Gray 同步后，最高两位取反，其余相同
    assign wr_full  =
        (wr_ptr_gray_next == {~rd_ptr_gray_sync[PTR_WIDTH-1:PTR_WIDTH-2],
                              rd_ptr_gray_sync[PTR_WIDTH-3:0]});

    // =========================================================================
    // 可选：Almost Full（简单实现：剩余空间 <= 2）
    // 对于 RHS2116 应用，你可以用它来减慢 SPI 侧写入或者暂停读取 RHS2116。
    // =========================================================================
    // 将 Gray 转回 bin 估算使用量（注意：这里简单用组合逻辑做 gray2bin）
    reg [PTR_WIDTH-1:0] rd_bin_in_wr;
    integer k;
    always @* begin
        // Gray → Bin
        rd_bin_in_wr[PTR_WIDTH-1] = rd_ptr_gray_sync[PTR_WIDTH-1];
        for (k = PTR_WIDTH-2; k >= 0; k = k - 1) begin
            rd_bin_in_wr[k] = rd_bin_in_wr[k+1] ^ rd_ptr_gray_sync[k];
        end
    end

    wire [PTR_WIDTH-1:0] used_words_wr =
        wr_ptr_bin - rd_bin_in_wr;

    // 阈值可以根据你想要的 margin 调整，这里设为：只剩 <=2 个空位就 almost_full
    assign wr_almost_full = (used_words_wr >= (FIFO_DEPTH - 2));

endmodule