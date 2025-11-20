// ============================================================================
// Frame Synchronizer - 56-bit Frame Format
// ============================================================================
// Frame format: {SYNC(8), CNT(8), DATA(32), CRC(8)} = 56 bits
// SYNC pattern: 8'hAA
// CRC-8: Polynomial 0x07, initial 0x00
//
// State machine:
//   SEARCH: Look for SYNC pattern in 48-bit sliding window
//   SYNC:   Frame synced, validate CRC and output data
//   VERIFY: CRC validation state (1 cycle)
//
// Features:
//   - Sliding window sync (allows up to 7-bit slip)
//   - Frame counter continuity check
//   - CRC error detection
//   - Auto-resync after 8 consecutive CRC errors
// ============================================================================

module frame_sync_100m (
    input  wire clk_sys,      // 100MHz
    input  wire rst_n,
    input  wire bit_in,       // From CDR
    input  wire bit_valid,
    output reg  [31:0] data_out,
    output reg        data_valid,
    output reg        frame_error,
    output reg        sync_lost
);

    localparam SYNC_PATTERN = 8'hAA;

    // ========================================================================
    // State machine
    // ========================================================================
    localparam SEARCH = 2'b00;
    localparam SYNC   = 2'b01;
    localparam VERIFY = 2'b10;

    reg [1:0] state;
    reg [5:0] bit_cnt;      // 0-55 (56 bits per frame)
    reg [7:0] frame_cnt;    // Expected frame counter
    reg [3:0] error_cnt;    // Consecutive CRC errors

    // ========================================================================
    // 56-bit shift register
    // ========================================================================
    reg [55:0] shift_reg;

    always @(posedge clk_sys) begin
        if (bit_valid) begin
            shift_reg <= {shift_reg[54:0], bit_in};
            $display("Frame Sync: Shift Reg: %h", {shift_reg[54:0], bit_in});
        end
    end

    // ========================================================================
    // CRC-8 calculation (combination logic, x^8 + x^2 + x + 1)
    // ========================================================================
    wire [7:0] calc_crc;
    assign calc_crc = crc8_48bit({shift_reg[55:8]});

    function [7:0] crc8_48bit;
        input [47:0] data;
        integer i;
        reg [7:0] crc;
        begin
            crc = 8'h00;
            for (i = 47; i >= 0; i = i - 1) begin
                if ((crc[7] ^ data[i]) == 1'b1)
                    crc = {crc[6:0], 1'b0} ^ 8'h07;  // Polynomial: x^8 + x^2 + x + 1
                else
                    crc = {crc[6:0], 1'b0};
            end
            crc8_48bit = crc;
        end
    endfunction

    // ========================================================================
    // Main state machine
    // ========================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state      <= SEARCH;
            bit_cnt    <= 6'b0;
            frame_cnt  <= 8'b0;
            error_cnt  <= 4'b0;
            data_valid <= 1'b0;
            frame_error <= 1'b0;
            sync_lost  <= 1'b0;
        end else begin
            data_valid  <= 1'b0;  // Default
            frame_error <= 1'b0;
            sync_lost   <= 1'b0;

            case (state)
                // SEARCH: Look for SYNC pattern
                // SEARCH: Look for SYNC pattern
                SEARCH: begin
                    if (shift_reg[55:48] == SYNC_PATTERN) begin
                        // Found potential frame start - Check CRC immediately
                        $display("Frame Sync: Potential Sync at %t, CRC calc: %h, CRC in: %h", $time, calc_crc, shift_reg[7:0]);
                        if (calc_crc == shift_reg[7:0]) begin
                            // Good frame
                            error_cnt <= 4'b0;

                            // Check frame counter continuity (if we were tracking)
                            if (shift_reg[47:40] != frame_cnt) begin
                                // If we were searching, we might have skipped frames, 
                                // so this is expected, but we report it if we thought we were close?
                                // Actually, if we are in SEARCH, we might be starting up.
                                // Let's just report sync_lost if it mismatches, 
                                // but since we are in SEARCH, maybe we just accept it?
                                // The original VERIFY logic sets sync_lost. We'll do the same.
                                sync_lost <= 1'b1;
                            end

                            frame_cnt <= shift_reg[47:40] + 8'b1;

                            // Output data
                            data_out   <= shift_reg[39:8];
                            data_valid <= 1'b1;

                            // Transition to SYNC to wait for NEXT frame
                            state   <= SYNC;
                            bit_cnt <= 6'b0;
                        end
                    end
                end

                // SYNC: Accumulate frame bits
                SYNC: begin
                    if (bit_valid) begin
                        if (bit_cnt == 6'b110111) begin  // 55 (all 56 bits)
                            // Complete frame received
                            bit_cnt <= 6'b0;
                            state   <= VERIFY;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end
                end

                // VERIFY: Check CRC and output data
                VERIFY: begin
                    // Check CRC
                    if (calc_crc == shift_reg[7:0]) begin
                        // Good frame
                        error_cnt <= 4'b0;

                        // Check frame counter continuity
                        if (shift_reg[47:40] != frame_cnt) begin
                            sync_lost <= 1'b1;
                        end

                        frame_cnt <= shift_reg[47:40] + 8'b1;

                        // Output data
                        data_out   <= shift_reg[39:8];
                        data_valid <= 1'b1;
                    end else begin
                        // CRC error
                        frame_error <= 1'b1;
                        error_cnt   <= error_cnt + 1'b1;

                        // Lost sync after 8 consecutive errors
                        if (error_cnt >= 4'b0111) begin
                            sync_lost <= 1'b1;
                            state     <= SEARCH;
                            frame_cnt <= 8'b0;
                        end
                    end

                    state <= SEARCH;  // Always return to search
                end

                default: begin
                    state <= SEARCH;
                end
            endcase
        end
    end

endmodule
