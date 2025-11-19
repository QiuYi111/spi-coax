// ============================================================================
// RHS2116 Link Encoder - Top Level (Transmit Side)
// ============================================================================
// Clocks:
//   - clk_spi: 64MHz (dedicated PLL for SPI)
//   - clk_sys: 100MHz (system and link processing)
//
// Data flow:
//   RHS2116 SPI → SPI Master (64M) → Frame Packer (100M) → Manchester DDR (100M) → coax_out
//
// Interface:
//   - SPI: cs_n, sclk, mosi, miso
//   - Coax: ddr_p, ddr_n (differential output)
//   - Status: link_active, fifo_status
// ============================================================================

module rhs2116_link_encoder (
    // Clocks and reset
    input  wire clk_spi,    // 64MHz SPI clock
    input  wire clk_sys,    // 100MHz system clock
    input  wire rst_n,      // Global reset (sync to clk_sys)

    // Enable control (clk_sys domain)
    input  wire enable,

    // SPI interface to RHS2116
    output wire cs_n,
    output wire sclk,       // 16MHz
    output wire mosi,
    input  wire miso,

    // Manchester differential output
    output wire ddr_p,      // Positive phase
    output wire ddr_n,      // Negative phase

    // Status outputs
    output wire link_active,
    output wire [7:0] frame_count
);

    // ========================================================================
    // SPI Master (64MHz domain)
    // ========================================================================
    wire [31:0] spi_data;
    wire        spi_valid;

    spi_master_rhs2116 u_spi_master (
        .clk_spi    (clk_spi),
        .rst_n      (rst_n),
        .enable     (enable),
        .cs_n       (cs_n),
        .sclk       (sclk),
        .mosi       (mosi),
        .miso       (miso),
        .data_out   (spi_data),
        .data_valid (spi_valid)
    );

    // ========================================================================
    // Frame Packer (100MHz domain)
    // Instantiates FIFO internally to handle clk_spi -> clk_sys crossing
    // ========================================================================
    wire        packer_ready;
    wire        packer_valid;
    wire        packer_bit;
    wire [7:0]  packer_frame_cnt;

    frame_packer_100m u_frame_packer (
        .clk_sys        (clk_sys),
        .rst_n          (rst_n),
        .din            (spi_data),
        .din_valid      (spi_valid),
        .tx_bit         (packer_bit),
        .tx_bit_valid   (packer_valid),
        .tx_bit_ready   (packer_ready),
        .frame_count    (packer_frame_cnt)
    );

    // ========================================================================
    // Manchester Encoder DDR (100MHz domain)
    // ========================================================================
    manchester_encoder_ddr u_manchester (
        .clk_sys    (clk_sys),
        .rst_n      (rst_n),
        .tx_en      (enable),
        .bit_in     (packer_bit),
        .bit_valid  (packer_valid),
        .bit_ready  (packer_ready),
        .ddr_p      (ddr_p),
        .ddr_n      (ddr_n)
    );

    // ========================================================================
    // Status aggregation
    // ========================================================================
    assign link_active  = enable;
    assign frame_count  = packer_frame_cnt;

endmodule
