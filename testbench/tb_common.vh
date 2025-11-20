// Common Testbench Utilities and Macros
// Provides reusable verification components for all testbenches

`ifndef TB_COMMON_VH
`define TB_COMMON_VH

// ============================================================================
// ASSERTION MACROS
// ============================================================================

// Assert with custom message
`define ASSERT(condition, message) \
    if (!(condition)) begin \
        $error("[ASSERTION FAILED] %s at time %0t: %s", `__FILE__, $time, message); \
        test_failed = 1; \
    end

// Check equality
`define CHECK_EQ(actual, expected, name) \
    if ((actual) !== (expected)) begin \
        $error("[CHECK FAILED] %s: expected %h, got %h at time %0t", name, expected, actual, $time); \
        test_failed = 1; \
    end else begin \
        $display("[CHECK PASS] %s: %h at time %0t", name, actual, $time); \
    end

// Check inequality
`define CHECK_NE(actual, not_expected, name) \
    if ((actual) === (not_expected)) begin \
        $error("[CHECK FAILED] %s: should not be %h at time %0t", name, not_expected, $time); \
        test_failed = 1; \
    end

// Check within range
`define CHECK_RANGE(actual, min_val, max_val, name) \
    if ((actual) < (min_val) || (actual) > (max_val)) begin \
        $error("[CHECK FAILED] %s: %0d not in range [%0d, %0d] at time %0t", name, actual, min_val, max_val, $time); \
        test_failed = 1; \
    end

// ============================================================================
// TEST MANAGEMENT
// ============================================================================

// Start a test section
`define TEST_SECTION(name) \
    begin \
        $display(""); \
        $display("========================================"); \
        $display("TEST SECTION: %s", name); \
        $display("========================================"); \
        section_name = name; \
    end

// Report test statistics
`define TEST_REPORT \
    begin \
        $display(""); \
        $display("========================================"); \
        $display("TEST REPORT"); \
        $display("========================================"); \
        $display("Total Checks: %0d", check_count); \
        $display("Passed: %0d", pass_count); \
        $display("Failed: %0d", fail_count); \
        if (test_failed) begin \
            $display("RESULT: FAILED"); \
            $error("TEST FAILED - See errors above"); \
        end else begin \
            $display("RESULT: PASSED"); \
            $display("ALL TESTS PASSED!"); \
        end \
        $display("========================================"); \
    end

// ============================================================================
// CRC-8 CALCULATION (Polynomial 0x07)
// ============================================================================

function [7:0] calc_crc8;
    input [47:0] data;  // SYNC(8) + CNT(8) + DATA(32)
    integer i;
    reg [7:0] crc;
    begin
        crc = 8'h00;
        for (i = 47; i >= 0; i = i - 1) begin
            if ((crc[7] ^ data[i]) == 1'b1)
                crc = {crc[6:0], 1'b0} ^ 8'h07;
            else
                crc = {crc[6:0], 1'b0};
        end
        calc_crc8 = crc;
    end
endfunction

// ============================================================================
// PERFORMANCE MEASUREMENT
// ============================================================================

// Measure time between two events
task measure_latency;
    input integer start_time;
    input integer end_time;
    input string name;
    integer latency_ns;
    begin
        latency_ns = end_time - start_time;
        $display("[PERFORMANCE] %s latency: %0d ns (%.2f us)", 
                 name, latency_ns, latency_ns / 1000.0);
    end
endtask

// Calculate throughput
task report_throughput;
    input integer num_bits;
    input integer duration_ns;
    real mbps;
    begin
        mbps = (num_bits * 1000.0) / duration_ns;
        $display("[PERFORMANCE] Throughput: %.2f Mbps (%0d bits in %0d ns)", 
                 mbps, num_bits, duration_ns);
    end
endtask

// ============================================================================
// MANCHESTER ENCODING/DECODING UTILITIES
// ============================================================================

// Encode a bit to Manchester (0 -> 01, 1 -> 10)
function [1:0] manchester_encode;
    input bit_val;
    begin
        manchester_encode = bit_val ? 2'b10 : 2'b01;
    end
endfunction

// Decode Manchester transition to bit
function manchester_decode;
    input [1:0] manch_val;
    begin
        case (manch_val)
            2'b01: manchester_decode = 1'b0;
            2'b10: manchester_decode = 1'b1;
            default: manchester_decode = 1'bx;
        endcase
    end
endfunction

// ============================================================================
// RANDOM DATA GENERATION
// ============================================================================

// Generate random 32-bit data
function [31:0] random_data;
    begin
        random_data = {$random, $random};
    end
endfunction

// Generate random bit pattern with specified density
function random_bit;
    input integer one_percent;  // Percentage of 1s (0-100)
    integer rand_val;
    begin
        rand_val = $random % 100;
        random_bit = (rand_val < one_percent) ? 1'b1 : 1'b0;
    end
endfunction

// ============================================================================
// BIT ERROR INJECTION
// ============================================================================

// Inject bit error with given probability
function inject_bit_error;
    input bit_val;
    input integer error_rate_ppm;  // Errors per million bits
    integer rand_val;
    begin
        rand_val = $random % 1000000;
        if (rand_val < error_rate_ppm)
            inject_bit_error = ~bit_val;  // Flip bit
        else
            inject_bit_error = bit_val;
    end
endfunction

// ============================================================================
// CLOCK JITTER INJECTION
// ============================================================================

// Add jitter to clock period (returns adjusted period)
function real add_jitter;
    input real nominal_period;
    input real jitter_percent;  // Peak-to-peak jitter as percentage
    real jitter_amount;
    real rand_val;
    begin
        rand_val = ($random % 1000) / 1000.0;  // -1.0 to 1.0
        jitter_amount = nominal_period * (jitter_percent / 100.0) * rand_val;
        add_jitter = nominal_period + jitter_amount;
    end
endfunction

// ============================================================================
// DISPLAY UTILITIES
// ============================================================================

// Display frame in human-readable format
task display_frame;
    input [55:0] frame;
    reg [7:0] sync_byte;
    reg [7:0] counter;
    reg [31:0] data;
    reg [7:0] crc;
    begin
        sync_byte = frame[55:48];
        counter = frame[47:40];
        data = frame[39:8];
        crc = frame[7:0];
        $display("[FRAME] SYNC=%02h CNT=%02h DATA=%08h CRC=%02h", 
                 sync_byte, counter, data, crc);
    end
endtask

// Display binary value with separator
task display_binary;
    input [31:0] value;
    input integer width;
    input string name;
    integer i;
    begin
        $write("[BINARY] %s: ", name);
        for (i = width-1; i >= 0; i = i - 1) begin
            $write("%b", value[i]);
            if (i % 8 == 0 && i != 0) $write("_");
        end
        $write("\n");
    end
endtask

// ============================================================================
// TIMING VERIFICATION
// ============================================================================

// Note: Timing checks are informational and don't set test_failed automatically
// Use with ASSERT macro in testbench if strict checking needed

// Check signal timing (setup/hold) - informational
task check_setup_time;
    input string signal_name;
    input integer actual_time;
    input integer required_time;
    begin
        if (actual_time < required_time) begin
            $error("[TIMING] Setup time violation for %s: %0d ns < %0d ns required", 
                   signal_name, actual_time, required_time);
        end
    end
endtask

task check_hold_time;
    input string signal_name;
    input integer actual_time;
    input integer required_time;
    begin
        if (actual_time < required_time) begin
            $error("[TIMING] Hold time violation for %s: %0d ns < %0d ns required", 
                   signal_name, actual_time, required_time);
        end
    end
endtask

`endif // TB_COMMON_VH
