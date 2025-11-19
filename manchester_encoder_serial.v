// Manchester encoder with serial bit input from Frame Packer
// - clk_160m: 160 MHz clock
// - Effective bit rate: 80 Mbps (1 bit = 2 clk cycles)
// - Streaming interface: bit_in / bit_valid / bit_ready

module manchester_encoder_serial #(
    parameter IDLE_LEVEL = 1'b0   // 空闲电平，可根据需要修改
)(
    input  wire clk_160m,
    input  wire rst_n,

    // Serial bit input from Frame Packer (same clock domain)
    input  wire bit_in,      // 待编码的串行数据 bit
    input  wire bit_valid,   // 有效标志，配合 bit_ready 使用
    output wire bit_ready,   // 编码器可以接收新 bit

    // Manchester coded output
    output reg  manch_out
);

    // 当前正在编码的 bit
    reg cur_bit;

    // phase = 0: 等待/发送 bit 的前半周期
    // phase = 1: 发送该 bit 的后半周期（反码）
    reg phase;

    // 握手：只有在 phase == 0 时才会吞一个新 bit
    wire bit_accepted = bit_valid & bit_ready;

    // ready: 只有在前半周期并且没有复位时才为 1
    assign bit_ready = (phase == 1'b0);

    always @(posedge clk_160m or negedge rst_n) begin
        if (!rst_n) begin
            cur_bit   <= 1'b0;
            phase     <= 1'b0;
            manch_out <= IDLE_LEVEL;
        end else begin
            if (bit_accepted) begin
                // 接收一个新 bit，并开始它的第一个半周期
                cur_bit   <= bit_in;
                manch_out <= bit_in;    // 前半周期输出原始 bit
                phase     <= 1'b1;      // 下一拍进入后半周期
            end else if (phase == 1'b1) begin
                // 后半周期：输出反码，然后回到 phase 0，
                // 等待下一个 bit_accepted
                manch_out <= ~cur_bit;
                phase     <= 1'b0;
            end else begin
                // phase == 0 且没有新 bit 进来：保持空闲电平
                manch_out <= IDLE_LEVEL;
                // phase 继续保持 0，直到有 bit_accepted
            end
        end
    end

endmodule