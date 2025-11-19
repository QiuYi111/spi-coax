// ============================================================================
// RHS2116 Link Decoder - Top Level (Receive Side)
// ============================================================================
// Clocks:
//   - clk_link: 200MHz (CDR oversampling)
//   - clk_sys:  100MHz (system processing)
//
// Data flow:
//   coax_in → CDR (200M) → Frame Sync (100M) → Async FIFO (200M→100M) → Output
//
// Interface:
//   - Coax: manch_in (single-ended)
//   - Output: data_out[31:0], data_valid
//   - Status: cdr_locked, frame_error, sync_lost
// ============================================================================

module rhs2116_link_decoder (
    // Clocks and reset
    input  wire clk_link,   // 200MHz CDR clock
    input  wire clk_sys,    // 100MHz system clock
    input  wire rst_n,

    // Manchester input from coax
    input  wire manch_in,

    // Decoded output (clk_sys domain)
    output wire [31:0] data_out,
    output wire        data_valid,

    // Status outputs
    output wire        cdr_locked,
    output wire        frame_error,
    output wire        sync_lost
);

    // ========================================================================
    // CDR Module (200MHz domain)
    // ========================================================================
    wire        cdr_bit;
    wire        cdr_bit_valid;
    wire        cdr_locked_int;

    cdr_4x_oversampling u_cdr (
        .clk_link   (clk_link),
        .rst_n      (rst_n),
        .manch_in   (manch_in),
        .bit_out    (cdr_bit),
        .bit_valid  (cdr_bit_valid),
        .locked     (cdr_locked_int)
    );

    // ========================================================================
    // Frame Sync (100MHz domain)
    // ========================================================================
    wire [31:0] frame_data;
    wire        frame_data_valid;
    wire        frame_error_int;
    wire        sync_lost_int;

    frame_sync_100m u_frame_sync (
        .clk_sys    (clk_sys),
        .rst_n      (rst_n),
        .bit_in     (cdr_bit),
        .bit_valid  (cdr_bit_valid),
        .data_out   (frame_data),
        .data_valid (frame_data_valid),
        .frame_error(frame_error_int),
        .sync_lost  (sync_lost_int)
    );

    // ========================================================================
    // Async FIFO (clk_link 200M -> clk_sys 100M)
    // ========================================================================
    wire        fifo_full;
    wire        fifo_empty;
    wire [31:0] fifo_din;
    wire        fifo_wr_en;
    wire [31:0] fifo_dout;
    wire        fifo_rd_en;

    // FIFO write side (200MHz - same as Frame Sync output)
    assign fifo_din  = frame_data;
    assign fifo_wr_en = frame_data_valid;

    async_fifo_200to100 #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(4)  // 16 entries
    ) u_async_fifo (
        .clk_wr     (clk_sys),      // Frame Sync runs at clk_sys
        .rst_wr_n   (rst_n),
        .din        (fifo_din),
        .wr_en      (fifo_wr_en),
        .full       (fifo_full),
        .almost_full(),

        .clk_rd     (clk_sys),
        .rst_rd_n   (rst_n),
        .dout       (data_out),
        .rd_en      (fifo_rd_en),
        .empty      (fifo_empty),
        .valid      (data_valid)
    );

    // ========================================================================
    // FIFO read enable (always ready to output data)
    // ========================================================================
    assign fifo_rd_en = !fifo_empty;  // Or connect to downstream ready signal

    // ========================================================================
    // Status outputs
    // ========================================================================
    assign cdr_locked  = cdr_locked_int;
    assign frame_error = frame_error_int;
    assign sync_lost   = sync_lost_int;

endmodule
