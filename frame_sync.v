// Frame synchronization and CRC check module
// - Searches for SYNC pattern (0xA5) in incoming bit stream
// - Validates frame with CRC check
// - Outputs complete 32-bit data words

module frame_sync #(
    parameter SYNC_BYTE = 8'hA5,
    parameter CRC_POLY  = 8'h07,
    parameter CRC_INIT  = 8'h00,
    parameter FRAME_BITS = 48  // Total frame size in bits
)(
    input  wire        clk,           // 80 MHz clock
    input  wire        rst_n,

    // Serial bit input from CDR
    input  wire        bit_in,
    input  wire        bit_valid,
    output wire        bit_ready,

    // Frame output
    output reg [31:0]  data_out,
    output reg         data_valid,
    input  wire        data_ready,

    // Status outputs
    output reg         frame_error,   // CRC error detected
    output reg [7:0]   frame_count,   // Current frame counter value
    output reg         sync_lost      // Lost frame synchronization
);

    // Shift register for bit alignment
    reg [47:0] shift_reg;
    reg [5:0]  bit_counter;
    reg        in_frame;

    // Frame fields
    wire [7:0] sync_byte = shift_reg[47:40];
    wire [7:0] rx_cnt    = shift_reg[39:32];
    wire [31:0] rx_data  = shift_reg[31:0];
    wire [7:0] rx_crc    = shift_reg[7:0];

    // CRC calculation
    wire [7:0] calc_crc;
    assign calc_crc = crc8_40bit({rx_cnt, rx_data});

    // State tracking
    reg [7:0]  expected_cnt;
    reg        sync_acquired;
    reg [3:0]  error_count;

    // CRC-8 calculation function
    function [7:0] crc8_40bit;
        input [39:0] data_bits;
        integer i;
        reg [7:0] crc;
    begin
        crc = CRC_INIT;
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

    // Always ready for bits when not outputting data
    assign bit_ready = !data_valid || data_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg     <= 48'd0;
            bit_counter   <= 6'd0;
            in_frame      <= 1'b0;
            data_out      <= 32'd0;
            data_valid    <= 1'b0;
            frame_error   <= 1'b0;
            frame_count   <= 8'd0;
            sync_lost     <= 1'b0;
            expected_cnt  <= 8'd0;
            sync_acquired <= 1'b0;
            error_count   <= 4'd0;
        end else begin
            // Default outputs
            data_valid  <= 1'b0;
            frame_error <= 1'b0;
            sync_lost   <= 1'b0;

            if (bit_valid && bit_ready) begin
                // Shift in new bit
                shift_reg <= {shift_reg[46:0], bit_in};

                if (!in_frame) begin
                    // Searching for sync pattern
                    if (sync_byte == SYNC_BYTE) begin
                        // Found potential frame start
                        in_frame    <= 1'b1;
                        bit_counter <= 6'd1;
                    end
                end else begin
                    // Receiving frame
                    bit_counter <= bit_counter + 6'd1;

                    if (bit_counter == (FRAME_BITS - 1)) begin
                        // Complete frame received
                        in_frame <= 1'b0;

                        // Check CRC
                        if (calc_crc == rx_crc) begin
                            // Good frame
                            if (!sync_acquired) begin
                                sync_acquired <= 1'b1;
                                expected_cnt  <= rx_cnt + 8'd1;
                            end else begin
                                // Check for missing frames
                                if (rx_cnt != expected_cnt) begin
                                    // Frame(s) lost
                                    sync_lost <= 1'b1;
                                end
                                expected_cnt <= rx_cnt + 8'd1;
                            end

                            // Output data
                            if (!data_valid || data_ready) begin
                                data_out    <= rx_data;
                                data_valid  <= 1'b1;
                                frame_count <= rx_cnt;
                                error_count <= 4'd0;
                            end
                        end else begin
                            // CRC error
                            frame_error <= 1'b1;
                            error_count <= error_count + 4'd1;

                            if (error_count >= 4'd8) begin
                                // Too many errors - lose sync
                                sync_acquired <= 1'b0;
                                sync_lost     <= 1'b1;
                            end
                        end
                    end
                end
            end

            // Handle backpressure
            if (data_valid && data_ready) begin
                data_valid <= 1'b0;
            end
        end
    end

endmodule