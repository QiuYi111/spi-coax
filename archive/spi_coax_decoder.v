// ============================================================================
// SPI-Coax Decoder Top Level
// Single-Wire Manchester to RHS2116 Data Decoder
// ============================================================================
// 功能：将单线曼彻斯特编码信号解码为RHS2116数据
// 时钟：
//   - clk_240m: 240MHz (3x过采样时钟)
//   - clk_link: 80MHz (链路时钟)
// ============================================================================
module spi_coax_decoder #(
    parameter SYNC_BYTE   = 8'hA5,
    parameter CRC_POLY    = 8'h07,
    parameter CRC_INIT    = 8'h00,
    parameter FRAME_BITS  = 48
)(
    // 时钟和复位
    input  wire clk_240m,       // 240MHz 3x过采样时钟
    input  wire clk_link,       // 80MHz 链路时钟
    input  wire rst_n,          // 全局复位 (低有效)

    // 单线输入 (曼彻斯特编码)
    input  wire coax_in,

    // 解码数据输出
    output wire [31:0] data_out,
    output wire        data_valid,
    input  wire        data_ready,

    // 状态输出
    output wire        frame_error,
    output wire [7:0]  frame_count,
    output wire        sync_lost,
    output wire        cdr_locked,
    output wire [1:0]  phase_error_cnt
);

    // 内部信号
    wire manch_in;
    wire manch_in_buf;

    wire cdr_data_out;
    wire cdr_data_valid;
    wire cdr_data_ready;

    wire frame_bit_in;
    wire frame_bit_valid;
    wire frame_bit_ready;

    wire [31:0] frame_data_out;
    wire        frame_data_valid;

    // 输入缓冲 (可选，用于改善时序)
    reg coax_in_reg1, coax_in_reg2;
    always @(posedge clk_240m or negedge rst_n) begin
        if (!rst_n) begin
            coax_in_reg1 <= 1'b0;
            coax_in_reg2 <= 1'b0;
        end else begin
            coax_in_reg1 <= coax_in;
            coax_in_reg2 <= coax_in_reg1;
        end
    end
    assign manch_in = coax_in_reg2;

    // Soft CDR 实例
    soft_cdr #(
        .OVERSAMPLE_RATE(3),
        .PHASE_ADJUST_THRESHOLD(4)
    ) u_soft_cdr (
        .clk_240m(clk_240m),
        .rst_n(rst_n),
        .manch_in(manch_in),
        .data_out(cdr_data_out),
        .data_valid(cdr_data_valid),
        .data_ready(cdr_data_ready),
        .phase_error_cnt(phase_error_cnt),
        .phase_locked(cdr_locked)
    );

    // Manchester Decoder 实例 (简化版，CDR已经做了大部分工作)
    // 这里使用一个简单的同步器，因为CDR已经恢复了时钟
    reg cdr_data_reg;
    always @(posedge clk_link or negedge rst_n) begin
        if (!rst_n) begin
            cdr_data_reg <= 1'b0;
        end else begin
            cdr_data_reg <= cdr_data_out;
        end
    end

    // 数据有效信号同步
    reg cdr_valid_reg;
    always @(posedge clk_link or negedge rst_n) begin
        if (!rst_n) begin
            cdr_valid_reg <= 1'b0;
        end else begin
            cdr_valid_reg <= cdr_data_valid;
        end
    end

    assign frame_bit_in = cdr_data_reg;
    assign frame_bit_valid = cdr_valid_reg;
    assign cdr_data_ready = frame_bit_ready;

    // Frame Sync 实例
    frame_sync #(
        .SYNC_BYTE(SYNC_BYTE),
        .CRC_POLY(CRC_POLY),
        .CRC_INIT(CRC_INIT),
        .FRAME_BITS(FRAME_BITS)
    ) u_frame_sync (
        .clk(clk_link),
        .rst_n(rst_n),
        .bit_in(frame_bit_in),
        .bit_valid(frame_bit_valid),
        .bit_ready(frame_bit_ready),
        .data_out(frame_data_out),
        .data_valid(frame_data_valid),
        .data_ready(data_ready),
        .frame_error(frame_error),
        .frame_count(frame_count),
        .sync_lost(sync_lost)
    );

    // 输出连接
    assign data_out = frame_data_out;
    assign data_valid = frame_data_valid;

endmodule