// -----------------------------------------------------------------------------
// Frame Packer @ "80 MHz"（时钟.freq 任你定，但与 Manchester 保持同域更省事）
// 将 32-bit 采样打包为 56-bit 帧并串行输出：
//   [55:48] SYNC  = 8'hA5
//   [47:40] CNT   = 8-bit 帧计数
//   [39:08] DATA  = 输入 32-bit 采样
//   [07:00] CRC8  = 基于 {CNT, DATA} 计算 (poly 0x07, init 0x00, MSB-first)
//
// 并行口： frame_data / frame_valid 方便调试
// 串行口： tx_bit / tx_bit_valid / tx_bit_ready 直连 Manchester 编码器
// -----------------------------------------------------------------------------
module frame_packer_80m #(
    parameter SYNC_BYTE  = 8'hA5, // 帧头
    parameter CRC_POLY   = 8'h07, // x^8 + x^2 + x + 1
    parameter CRC_INIT   = 8'h00
)(
    input  wire         clk,        // 链路时钟（建议与 Manchester 同域）
    input  wire         rst_n,      // 低电平复位

    // 上游 FIFO 读口（SPI->FIFO->FramePacker）
    input  wire [31:0]  fifo_dout,   // FIFO 读数据
    input  wire         fifo_empty,  // FIFO 为空
    output reg          fifo_rd_en,  // 读使能：拉高一拍请求读，下一拍数据有效

    // 并行帧输出（可选，用于调试或后端不用可删）
    output reg  [55:0]  frame_data,  // 打包好的 56-bit 帧
    output reg          frame_valid, // 1 个 clk 周期的有效脉冲

    // 串行 bit 输出接口（给 Manchester）
    output reg          tx_bit,       // 串行 bit，MSB-first
    output reg          tx_bit_valid, // bit 有效标志
    input  wire         tx_bit_ready  // 下游可以接收 bit
);

    // 状态机
    localparam S_IDLE = 2'd0;
    localparam S_READ = 2'd1;
    localparam S_SEND = 2'd2;

    reg [1:0]  state;
    reg [7:0]  frame_cnt;       // 8-bit 帧计数器
    reg [31:0] sample_reg;      // 暂存从 FIFO 读出的采样

    // 串行发送相关寄存器
    reg [55:0] shift_reg;       // 待发送帧的移位寄存器
    reg [5:0]  bit_cnt;         // 剩余 bit 个数（0..55）
    reg        sending;         // 正在发送一帧

    // -------------------------------------------------------------------------
    // CRC-8 组合逻辑函数
    // 输入：40-bit {CNT[7:0], DATA[31:0]}，MSB-first
    // 输出：8-bit CRC
    // -------------------------------------------------------------------------
    function automatic [7:0] crc8_40bit;
        input [39:0] data_bits;
        integer i;
        reg [7:0] crc;
    begin
        crc = CRC_INIT;
        // MSB-first：从 data_bits[39] 到 data_bits[0]
        for (i = 39; i >= 0; i = i - 1) begin
            if ((crc[7] ^ data_bits[i]) == 1'b1) begin
                crc = {crc[6:0], 1'b0} ^ CRC_POLY;
            end else begin
                crc = {crc[6:0], 1'b0};
            end
        end
        crc8_40bit = crc;
    end
    endfunction

    // -------------------------------------------------------------------------
    // 主时序逻辑
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            fifo_rd_en   <= 1'b0;
            frame_valid  <= 1'b0;
            frame_data   <= 56'd0;
            frame_cnt    <= 8'd0;
            sample_reg   <= 32'd0;

            shift_reg    <= 56'd0;
            bit_cnt      <= 6'd0;
            sending      <= 1'b0;
            tx_bit       <= 1'b0;
            tx_bit_valid <= 1'b0;
        end else begin
            // 默认值，避免锁存
            fifo_rd_en   <= 1'b0;
            frame_valid  <= 1'b0;
            tx_bit_valid <= 1'b0;

            case (state)
                //------------------------------------------------------------------
                // IDLE：等待 FIFO 非空 且 当前没有在发送上一帧
                //------------------------------------------------------------------
                S_IDLE: begin
                    if (!fifo_empty && !sending) begin
                        fifo_rd_en <= 1'b1;   // 请求读
                        state      <= S_READ; // 下一拍去接数据
                    end
                end

                //------------------------------------------------------------------
                // READ：上一拍已经拉高 rd_en，这一拍拿到 fifo_dout
                //       计算 CRC，生成一帧，并准备进入串行发送
                //------------------------------------------------------------------
                S_READ: begin
                    sample_reg <= fifo_dout;

                    begin : pack_and_crc
                        reg [39:0] crc_input;
                        reg [7:0]  crc_val;
                        reg [55:0] frame_word;

                        crc_input = {frame_cnt, fifo_dout};
                        crc_val   = crc8_40bit(crc_input);

                        // 帧格式：
                        // [55:48] SYNC
                        // [47:40] CNT
                        // [39:08] DATA
                        // [07:00] CRC
                        frame_word = {SYNC_BYTE, frame_cnt, fifo_dout, crc_val};

                        frame_data <= frame_word;  // 并行输出（调试用）
                        // 串行发送准备
                        shift_reg  <= frame_word;  // MSB-first
                    end

                    frame_valid <= 1'b1;          // 并行帧有效 1 个周期
                    frame_cnt   <= frame_cnt + 8'd1;

                    // 初始化发送计数器：需要发送 56 个 bit，从 [55] 到 [0]
                    bit_cnt <= 6'd55;
                    sending <= 1'b1;
                    state   <= S_SEND;
                end

                //------------------------------------------------------------------
                // SEND：通过 tx_bit/tx_bit_valid/tx_bit_ready 串行吐出 56 个 bit
                //------------------------------------------------------------------
                S_SEND: begin
                    if (sending && tx_bit_ready) begin
                        // 当前输出最高位 bit
                        tx_bit       <= shift_reg[55];
                        tx_bit_valid <= 1'b1;

                        // 左移一位（也可以右移+改变索引，风格问题）
                        shift_reg <= {shift_reg[54:0], 1'b0};

                        if (bit_cnt == 6'd0) begin
                            // 最后一个 bit 已发送
                            sending <= 1'b0;
                            state   <= S_IDLE;
                        end else begin
                            bit_cnt <= bit_cnt - 6'd1;
                        end
                    end
                    // 如果 tx_bit_ready == 0，则保持当前 shift_reg、bit_cnt，不发送，形成背压
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule