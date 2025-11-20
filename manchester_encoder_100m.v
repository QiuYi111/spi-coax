// ============================================================================
// Manchester Encoder - 100MHz Single-Clock with DDR Output
// ============================================================================
// Encoding scheme: 4 clock cycles per bit
//   - Bit rate: 25 Mbps (data) → 50 Mbps Manchester line rate
//   - Clock period: 10ns @ 100MHz
//   - Bit period: 40ns (4 clock cycles)
//   - Encoding: bit=0 -> 0→1 transition, bit=1 -> 1→0 transition
//
// Interface:
//   - Input:  bit_in, bit_valid (ready-valid handshake)
//   - Output: bit_ready, ddr_p, ddr_n (differential DDR)
// ============================================================================

module manchester_encoder_100m (
    input  wire clk_sys,      // 100MHz system clock
    input  wire rst_n,
    input  wire tx_en,        // Transmit enable (active high)

    // Serial bit input (ready-valid handshake)
    input  wire bit_in,       // Data bit to encode
    input  wire bit_valid,    // Input valid
    output wire bit_ready,    // Ready to accept new bit

    // Differential DDR output
    output wire ddr_p,        // Positive phase
    output wire ddr_n         // Negative phase (complement)
);

    // ========================================================================
    // Half-cycle counter (4 cycles per bit)
    // ========================================================================
    reg [1:0] half_cnt;
    reg       bit_reg;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            half_cnt <= 2'b00;
        end else if (tx_en && bit_valid && bit_ready) begin
            // New bit accepted, start counting from 0
            half_cnt <= 2'b01;
            bit_reg  <= bit_in;
        end else if (tx_en && (half_cnt != 2'b11)) begin
            // Continue counting
            half_cnt <= half_cnt + 1'b1;
        end else if (tx_en && (half_cnt == 2'b11)) begin
            // End of bit, reset to 0
            half_cnt <= 2'b00;
        end else begin
            // Disabled
            half_cnt <= 2'b00;
        end
    end

    // ========================================================================
    // Output generation - 2:1 MUX per half cycle
    // ========================================================================
    // First half (cycles 0-1): output original bit
    // Second half (cycles 2-3): output inverted bit
    wire first_half = (half_cnt < 2'b10);

    assign ddr_p = tx_en ? (first_half ? bit_reg : ~bit_reg) : 1'b0;
    assign ddr_n = ~ddr_p;  // Complementary output

    // ========================================================================
    // Ready signal - asserted at end of bit (cycle 3)
    // ========================================================================
    assign bit_ready = (half_cnt == 2'b00) || (half_cnt == 2'b11);

endmodule
