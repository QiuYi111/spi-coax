// ============================================================================
// SPI-Coax Link System Top Level
// ============================================================================
// Wraps both Encoder and Decoder for system-level simulation or loopback test.
//
// Clock Domains:
// - clk_spi:  64MHz (SPI Master)
// - clk_sys:  100MHz (System/Link Logic)
// - clk_link: 200MHz (CDR Oversampling)
// ============================================================================

module top (
    // Clocks and Reset
    input  wire clk_spi,
    input  wire clk_sys,
    input  wire clk_link,
    input  wire rst_n,

    // Control
    input  wire enable,

    // SPI Interface (to Sensor)
    output wire cs_n,
    output wire sclk,
    output wire mosi,
    input  wire miso,

    // Decoded Output (from Decoder)
    output wire [31:0] rx_data,
    output wire        rx_valid,

    // Status
    output wire        link_active,
    output wire        cdr_locked,
    output wire        frame_error,
    output wire        sync_lost,
    output wire [7:0]  tx_frame_cnt
);

    // ========================================================================
    // Internal Signals
    // ========================================================================
    wire ddr_p;
    wire ddr_n;
    wire manch_link;

    // ========================================================================
    // Encoder Instance (TX)
    // ========================================================================
    rhs2116_link_encoder u_encoder (
        .clk_spi    (clk_spi),
        .clk_sys    (clk_sys),
        .rst_n      (rst_n),
        .enable     (enable),
        .cs_n       (cs_n),
        .sclk       (sclk),
        .mosi       (mosi),
        .miso       (miso),
        .ddr_p      (ddr_p),
        .ddr_n      (ddr_n),
        .link_active(link_active),
        .frame_count(tx_frame_cnt)
    );

    // ========================================================================
    // Channel Connection (Loopback)
    // ========================================================================
    // In a real system, this is the coax cable.
    // We connect the positive differential output to the single-ended input.
    assign manch_link = ddr_p;

    // ========================================================================
    // Decoder Instance (RX)
    // ========================================================================
    rhs2116_link_decoder u_decoder (
        .clk_link   (clk_link),
        .clk_sys    (clk_sys),
        .rst_n      (rst_n),
        .manch_in   (manch_link),
        .data_out   (rx_data),
        .data_valid (rx_valid),
        .cdr_locked (cdr_locked),
        .frame_error(frame_error),
        .sync_lost  (sync_lost)
    );

endmodule
