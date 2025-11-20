//==============================================================================
// Test Framework Base Class for SPI-Coax System
// Provides common utilities for all testbenches
//==============================================================================

`timescale 1ns/1ps

// Test result status enumeration
typedef enum {
    TEST_PASS = 0,
    TEST_FAIL = 1,
    TEST_ERROR = 2,
    TEST_TIMEOUT = 3
} test_status_t;

// Test configuration structure
typedef struct {
    string test_name;
    real timeout_cycles;
    bit verbose;
    bit dump_waves;
    string wave_file;
} test_config_t;

// Base test class with common utilities
class TestBase;

    // Configuration
    test_config_t cfg;

    // Status tracking
    test_status_t status;
    int error_count;
    int warning_count;
    string test_log[$];

    // Timing
    realtime start_time;
    realtime end_time;

    // Constructor
    function new(string name = "unnamed_test");
        cfg.test_name = name;
        cfg.timeout_cycles = 1000000;  // Default: 1M cycles
        cfg.verbose = 1;
        cfg.dump_waves = 1;
        cfg.wave_file = $sformatf("%s.vcd", name);

        status = TEST_PASS;
        error_count = 0;
        warning_count = 0;
        start_time = 0;
        end_time = 0;
    endfunction

    // Utility methods
    function void info(string msg);
        $display("[%0t] INFO: %s", $time, msg);
        test_log.push_back($sformatf("INFO: %s", msg));
    endfunction

    function void warning(string msg);
        warning_count++;
        $display("[%0t] WARNING: %s", $time, msg);
        test_log.push_back($sformatf("WARNING: %s", msg));
    endfunction

    function void error(string msg);
        error_count++;
        status = TEST_FAIL;
        $display("[%0t] ERROR: %s", $time, msg);
        test_log.push_back($sformatf("ERROR: %s", msg));
    endfunction

    function void fatal(string msg);
        error_count++;
        status = TEST_ERROR;
        $display("[%0t] FATAL: %s", $time, msg);
        test_log.push_back($sformatf("FATAL: %s", msg));
        $finish;
    endfunction

    // Test control
    function void start_test();
        start_time = $realtime;
        info($sformatf("Starting test: %s", cfg.test_name));

        if (cfg.dump_waves) begin
            $dumpfile(cfg.wave_file);
            $dumpvars(0, top);
        end
    endfunction

    function void finish_test();
        end_time = $realtime;
        realtime duration = end_time - start_time;

        $display("===============================================");
        $display("Test: %s", cfg.test_name);
        $display("Status: %s", status.name());
        $display("Duration: %0.3f ms", duration/1000.0);
        $display("Errors: %0d", error_count);
        $display("Warnings: %0d", warning_count);
        $display("===============================================");

        if (status != TEST_PASS) begin
            $display("TEST FAILED - Check log for details");
        end

        $finish;
    endfunction

    // Assertion helpers
    function void assert_equal(bit expected, bit actual, string msg = "");
        if (expected !== actual) begin
            error($sformatf("Assertion failed: %s (expected=%b, actual=%b)",
                           msg, expected, actual));
        end else if (cfg.verbose) begin
            info($sformatf("Assertion passed: %s", msg));
        end
    endfunction

    function void assert_equal_int(int expected, int actual, string msg = "");
        if (expected !== actual) begin
            error($sformatf("Assertion failed: %s (expected=%0d, actual=%0d)",
                           msg, expected, actual));
        end else if (cfg.verbose) begin
            info($sformatf("Assertion passed: %s", msg));
        end
    endfunction

    function void assert_within_range(real value, real min_val, real max_val, string msg = "");
        if (value < min_val || value > max_val) begin
            error($sformatf("Range assertion failed: %s (value=%0.3f, range=[%0.3f,%0.3f]",
                           msg, value, min_val, max_val));
        end else if (cfg.verbose) begin
            info($sformatf("Range assertion passed: %s", msg));
        end
    endfunction

    // Timeout monitoring
    task automatic monitor_timeout(real timeout_cycles);
        real timeout_count = 0;
        @(posedge top.clk_sys);
        forever begin
            @(posedge top.clk_sys);
            timeout_count++;
            if (timeout_count >= timeout_cycles) begin
                error($sformatf("Test timeout after %0f cycles", timeout_cycles));
                status = TEST_TIMEOUT;
                finish_test();
            end
        end
    endtask

    // Log reporting
    function void generate_report();
        int file;
        string filename = $sformatf("%s_report.txt", cfg.test_name);

        file = $fopen(filename, "w");
        if (file) begin
            $fdisplay(file, "Test Report: %s", cfg.test_name);
            $fdisplay(file, "Generated: %0s", $time);
            $fdisplay(file, "Status: %s", status.name());
            $fdisplay(file, "Duration: %0.3f ms", (end_time - start_time)/1000.0);
            $fdisplay(file, "Errors: %0d", error_count);
            $fdisplay(file, "Warnings: %0d", warning_count);
            $fdisplay(file, "");
            $fdisplay(file, "Test Log:");
            foreach (test_log[i]) begin
                $fdisplay(file, "%s", test_log[i]);
            end
            $fclose(file);
            info($sformatf("Report generated: %s", filename));
        end
    endfunction

endclass