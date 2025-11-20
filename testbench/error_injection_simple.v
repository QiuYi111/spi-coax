//==============================================================================
// Simplified Error Injection for Icarus Verilog Compatibility
// Basic error injection without SystemVerilog features
//==============================================================================

`timescale 1ns/1ps

// Error type constants
`define ERROR_NONE         3'd0
`define ERROR_BIT_FLIP     3'd1
`define ERROR_FRAME_CORRUPT 3'd2
`define ERROR_CRC_MISMATCH 3'd3
`define ERROR_SYNC_LOST    3'd4
`define ERROR_CLOCK_GLITCH 3'd5
`define ERROR_BURST_ERROR  3'd6

// Error injection configuration
module error_injector;
    // Clock input
    input clk;

    // Configuration registers
    reg [2:0] error_type;
    reg [15:0] error_rate;      // Error rate in ppm (parts per million)
    reg [7:0]  burst_length;    // Burst error length
    reg [15:0] error_counter;
    reg [15:0] cycle_counter;
    reg enabled;

    // Status registers
    reg error_active;
    reg [7:0] burst_counter;
    reg glitch_active;
    reg [31:0] corrupted_data;
    reg [7:0] corrupted_crc;
    reg [7:0] corrupted_sync;

    // Random number generator (simple LFSR)
    reg [31:0] rng_state;

    // Initialize with defaults
    initial begin
        error_type = `ERROR_NONE;
        error_rate = 0;
        burst_length = 8'd5;
        error_counter = 0;
        cycle_counter = 0;
        enabled = 1'b0;
        error_active = 1'b0;
        burst_counter = 0;
        glitch_active = 1'b0;
        corrupted_data = 0;
        corrupted_crc = 0;
        corrupted_sync = 0;
        rng_state = 32'hDEADBEEF;
    end

    // Random number generation
    function [31:0] random_num;
        begin
            rng_state = (rng_state << 1) | ((rng_state[31] ^ rng_state[21] ^ rng_state[1] ^ rng_state[0]) & 1'b1);
            random_num = rng_state;
        end
    endfunction

    // Enable/disable error injection
    task set_error_injection;
        input [2:0] err_type;
        input [15:0] err_rate;
        input [7:0]  burst_len;
        begin
            error_type = err_type;
            error_rate = err_rate;
            burst_length = burst_len;
            enabled = (err_type != `ERROR_NONE) && (err_rate > 0);
            error_counter = 0;
            cycle_counter = 0;
            burst_counter = 0;
            error_active = 1'b0;
            glitch_active = 1'b0;

            $display("[ERROR_INJ] Enabled: type=%d, rate=%d ppm, burst=%d",
                     error_type, error_rate, burst_length);
        end
    endtask

    // Check if error should be injected this cycle
    function should_inject_error;
        reg [15:0] threshold;
        begin
            if (!enabled) begin
                should_inject_error = 1'b0;
            end else begin
                // Convert error_rate from ppm to threshold
                threshold = error_rate;
                // Use rng_state directly for randomness
                should_inject_error = (rng_state[15:0] < threshold);
            end
        end
    endfunction

    // Inject bit flip error
    function [31:0] inject_bit_flip;
        input [31:0] data;
        reg [4:0] bit_pos;
        begin
            if (should_inject_error()) begin
                bit_pos = rng_state[4:0];  // Random bit position 0-31
                corrupted_data = data ^ (32'h1 << bit_pos);
                inject_bit_flip = corrupted_data;
                error_counter = error_counter + 1;
                $display("[ERROR_INJ] Bit flip: pos=%d, data=0x%h->0x%h",
                         bit_pos, data, corrupted_data);
            end else begin
                inject_bit_flip = data;
            end
        end
    endfunction

    // Inject CRC error
    function [7:0] inject_crc_error;
        input [7:0] crc;
        reg [7:0] corrupt_val;
        begin
            if (should_inject_error()) begin
                corrupt_val = rng_state[7:0];
                corrupted_crc = crc ^ corrupt_val;
                inject_crc_error = corrupted_crc;
                error_counter = error_counter + 1;
                $display("[ERROR_INJ] CRC error: crc=0x%h->0x%h",
                         crc, corrupted_crc);
            end else begin
                inject_crc_error = crc;
            end
        end
    endfunction

    // Inject SYNC pattern error
    function [7:0] inject_sync_error;
        input [7:0] sync;
        reg [7:0] corrupt_val;
        begin
            if (should_inject_error()) begin
                corrupt_val = rng_state[7:0];
                corrupted_sync = sync ^ corrupt_val;
                inject_sync_error = corrupted_sync;
                error_counter = error_counter + 1;
                $display("[ERROR_INJ] SYNC error: sync=0x%h->0x%h",
                         sync, corrupted_sync);
            end else begin
                inject_sync_error = sync;
            end
        end
    endfunction

    // Clock glitch control
    function clock_glitch_active;
        begin
            if (enabled && (error_type == `ERROR_CLOCK_GLITCH)) begin
                glitch_active = should_inject_error();
                clock_glitch_active = glitch_active;
                if (glitch_active) begin
                    error_counter = error_counter + 1;
                    $display("[ERROR_INJ] Clock glitch injection");
                end
            end else begin
                clock_glitch_active = 1'b0;
            end
        end
    endfunction

    // Burst error control
    function burst_error_active;
        begin
            if (enabled && (error_type == `ERROR_BURST_ERROR)) begin
                if (burst_counter == 0) begin
                    error_active = should_inject_error();
                    if (error_active) begin
                        burst_counter = burst_length;
                        $display("[ERROR_INJ] Starting burst error: length=%d", burst_length);
                    end
                end else begin
                    burst_counter = burst_counter - 1;
                    if (burst_counter == 0) begin
                        error_active = 1'b0;
                        $display("[ERROR_INJ] Burst error ended");
                    end
                end
                burst_error_active = error_active;
            end else begin
                burst_error_active = 1'b0;
            end
        end
    endfunction

    // Update cycle counter
    always @(posedge clk) begin
        cycle_counter = cycle_counter + 1;
    end

    // Get error statistics
    task get_error_stats;
        output [15:0] total_errors;
        output [15:0] total_cycles;
        begin
            total_errors = error_counter;
            total_cycles = cycle_counter;
        end
    endtask

    // Reset error injection
    task reset_error_injection;
        begin
            enabled = 1'b0;
            error_type = `ERROR_NONE;
            error_rate = 0;
            error_counter = 0;
            cycle_counter = 0;
            burst_counter = 0;
            error_active = 1'b0;
            glitch_active = 1'b0;
            $display("[ERROR_INJ] Reset error injection");
        end
    endtask

endmodule