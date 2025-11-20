//==============================================================================
// Simplified Test Framework for Icarus Verilog Compatibility
// Basic utilities for all testbenches without SystemVerilog features
//==============================================================================

`timescale 1ns/1ps

// Test status constants
`define TEST_PASS    2'b00
`define TEST_FAIL    2'b01
`define TEST_ERROR   2'b10
`define TEST_TIMEOUT 2'b11

// Global test configuration
module test_config;
    // Test name storage (as integer for simplicity)
    reg [31:0] test_name_hash;

    // Timing configuration
    reg [31:0] timeout_cycles;
    reg verbose;
    reg dump_waves;

    // Status tracking
    reg [1:0] status;
    reg [15:0] error_count;
    reg [15:0] warning_count;

    // Initialize with defaults
    initial begin
        test_name_hash = 0;
        timeout_cycles = 32'd1000000;  // Default: 1M cycles
        verbose = 1'b1;
        dump_waves = 1'b1;
        status = `TEST_PASS;
        error_count = 0;
        warning_count = 0;
    end
endmodule

// Common test utilities module
module test_utils;

    // Function to calculate simple hash of test name
    function [31:0] hash_name;
        input [8*32-1:0] name_str;  // Max 32 characters
        reg [31:0] hash;
        integer i;
        begin
            hash = 0;
            for (i = 0; i < 32; i = i + 1) begin
                if (name_str[i*8 +: 8] != 0) begin
                    hash = hash + name_str[i*8 +: 8];
                    hash = (hash << 1) | (hash >> 31);  // Rotate left
                end
            end
            hash_name = hash;
        end
    endfunction

    // Task to report test status
    task report_status;
        input [8*32-1:0] test_name_str;
        input [1:0] test_status;
        input [15:0] errors;
        input [15:0] warnings;
        begin
            $display("=== TEST REPORT: %s ===", test_name_str);
            case (test_status)
                `TEST_PASS:    $display("✅ PASSED");
                `TEST_FAIL:    $display("❌ FAILED");
                `TEST_ERROR:   $display("💥 ERROR");
                `TEST_TIMEOUT: $display("⏰ TIMEOUT");
            endcase
            $display("Errors: %d, Warnings: %d", errors, warnings);
            $display("============================");
        end
    endtask

    // Task to log messages
    task log_message;
        input [8*32-1:0] test_name_str;
        input [8*128-1:0] message_str;
        begin
            $display("[%0t] %s: %s", $time, test_name_str, message_str);
        end
    endtask

    // Task to log errors
    task log_error;
        input [8*32-1:0] test_name_str;
        input [8*128-1:0] error_str;
        begin
            $display("[%0t] %s ERROR: %s", $time, test_name_str, error_str);
        end
    endtask

    // Task to log warnings
    task log_warning;
        input [8*32-1:0] test_name_str;
        input [8*128-1:0] warning_str;
        begin
            $display("[%0t] %s WARNING: %s", $time, test_name_str, warning_str);
        end
    endtask

    // Function to compare expected vs actual values
    function check_equal;
        input [31:0] expected;
        input [31:0] actual;
        begin
            check_equal = (expected == actual);
        end
    endfunction

    // Function to check if value is within range
    function check_range;
        input signed [31:0] value;
        input signed [31:0] min_val;
        input signed [31:0] max_val;
        begin
            check_range = (value >= min_val) && (value <= max_val);
        end
    endfunction

endmodule

// Common test stimulus patterns
module stimulus_patterns;

    // Generate random 32-bit data using simple LFSR
    reg [31:0] lfsr_state;

    function [31:0] random_data;
        begin
            // Simple 32-bit LFSR
            lfsr_state = (lfsr_state << 1) |
                       ((lfsr_state[31] ^ lfsr_state[21] ^ lfsr_state[1] ^ lfsr_state[0]) & 1'b1);
            random_data = lfsr_state;
        end
    endfunction

    // Initialize LFSR
    initial begin
        lfsr_state = 32'hACE1;
    end

endmodule