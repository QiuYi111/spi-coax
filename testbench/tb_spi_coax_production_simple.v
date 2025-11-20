//==============================================================================
// Simplified Production-Level System Testbench for SPI-Coax System
// Basic system test without SystemVerilog features, compatible with iverilog
//==============================================================================

`timescale 1ns/1ps

module tb_spi_coax_production_simple;

    // Clock signals
    reg clk_64m = 0;
    reg clk_100m = 0;
    reg clk_200m = 0;
    reg rst_n = 0;

    // System signals
    wire cs_n, sclk, mosi, miso;
    wire [31:0] rx_data;
    wire rx_valid;
    wire link_active;
    wire cdr_locked;
    wire frame_error;
    wire sync_lost;
    wire [7:0] tx_frame_cnt;

    // Timing parameters
    parameter CLK_64M_PERIOD = 15.625;  // 64 MHz
    parameter CLK_100M_PERIOD = 10.0;    // 100 MHz
    parameter CLK_200M_PERIOD = 5.0;     // 200 MHz

    // Test statistics
    reg [31:0] total_frames_sent = 0;
    reg [31:0] total_frames_received = 0;
    reg [31:0] total_crc_errors = 0;
    reg [31:0] total_frame_errors = 0;
    reg [31:0] total_sync_losses = 0;
    reg [31:0] test_start_time = 0;
    reg [31:0] test_end_time = 0;

    // Test configuration
    reg [15:0] test_duration_cycles = 100000;  // Test duration in cycles
    reg test_enabled = 1'b0;
    reg [1:0] test_status = 2'b00;  // 00=running, 01=passed, 10=failed

    // Include simplified error injection
    wire error_inject_active;
    wire [31:0] corrupted_data;

    // Clock generation
    always #(CLK_64M_PERIOD/2) clk_64m = ~clk_64m;
    always #(CLK_100M_PERIOD/2) clk_100m = ~clk_100m;
    always #(CLK_200M_PERIOD/2) clk_200m = ~clk_200m;

    // DUT instantiation - using top module
    top dut (
        .clk_spi(clk_64m),
        .clk_sys(clk_100m),
        .clk_link(clk_200m),
        .rst_n(rst_n),
        .enable(1'b1),
        .cs_n(cs_n),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .link_active(link_active),
        .cdr_locked(cdr_locked),
        .frame_error(frame_error),
        .sync_lost(sync_lost),
        .tx_frame_cnt(tx_frame_cnt)
    );

    // Test timeout counter
    reg [31:0] timeout_counter = 0;
    parameter TEST_TIMEOUT_CYCLES = 32'd1000000;  // 1M cycles timeout

    // Monitor and collect statistics
    always @(posedge clk_100m) begin
        if (test_enabled) begin
            timeout_counter = timeout_counter + 1;

            // Monitor received data
            if (rx_valid) begin
                total_frames_received = total_frames_received + 1;
                if (frame_error) begin
                    total_frame_errors = total_frame_errors + 1;
                end
            end

            // Monitor CDR status
            if (cdr_locked === 1'b0) begin
                total_sync_losses = total_sync_losses + 1;
            end

            // Check timeout
            if (timeout_counter > TEST_TIMEOUT_CYCLES) begin
                $display("[TEST] Test timeout reached");
                test_status = 2'b10;  // failed
                test_enabled = 1'b0;
            end

            // Check test duration
            if (timeout_counter > test_duration_cycles) begin
                $display("[TEST] Test duration completed");
                test_enabled = 1'b0;
                evaluate_test_results();
            end
        end
    end

    // Function to evaluate test results
    task evaluate_test_results;
        reg [31:0] success_rate;
        reg test_passed;
        begin
            test_end_time = $time;
            $display("=== PRODUCTION TEST RESULTS ===");
            $display("Test Duration: %0t ns", test_end_time - test_start_time);
            $display("Frames Sent: %d", total_frames_sent);
            $display("Frames Received: %d", total_frames_received);
            $display("CRC Errors: %d", total_crc_errors);
            $display("Frame Errors: %d", total_frame_errors);
            $display("Sync Losses: %d", total_sync_losses);

            // Calculate success rate
            if (total_frames_sent > 0) begin
                success_rate = (total_frames_received * 100) / total_frames_sent;
            end else begin
                success_rate = 0;
            end

            $display("Success Rate: %d%%", success_rate);

            // Determine if test passed (basic criteria)
            test_passed = (success_rate >= 95) &&  // At least 95% success rate
                         (total_frame_errors < total_frames_sent / 20);  // Less than 5% frame errors

            if (test_passed) begin
                test_status = 2'b01;  // passed
                $display("✅ PRODUCTION TEST PASSED");
            end else begin
                test_status = 2'b10;  // failed
                $display("❌ PRODUCTION TEST FAILED");
            end
            $display("=================================");
            $finish;
        end
    endtask

    // Basic test sequence
    task run_basic_test;
        begin
            $display("[TEST] Starting basic functionality test");
            test_duration_cycles = 50000;  // 50k cycles basic test
            start_test();
        end
    endtask

    // Stress test sequence
    task run_stress_test;
        begin
            $display("[TEST] Starting stress test");
            test_duration_cycles = 200000;  // 200k cycles stress test
            start_test();
        end
    endtask

    // Start test procedure
    task start_test;
        begin
            // Reset counters
            total_frames_sent = 0;
            total_frames_received = 0;
            total_crc_errors = 0;
            total_frame_errors = 0;
            total_sync_losses = 0;
            timeout_counter = 0;
            test_status = 2'b00;  // running
            test_enabled = 1'b1;
            test_start_time = $time;

            // Reset and enable system
            rst_n = 1'b0;
            #(CLK_100M_PERIOD * 10);
            rst_n = 1'b1;
            #(CLK_100M_PERIOD * 50);

            $display("[TEST] Test sequence started");
        end
    endtask

    // Main test stimulus - minimal for basic functionality
    initial begin
        $display("=== SPI-COAX PRODUCTION TEST (Simple Version) ===");
        $display("Starting simplified production-level testing...");

        // Run basic test first
        run_basic_test();

        // Wait for test to complete
        wait (test_enabled == 1'b0);

        // Only run stress test if basic test passed
        if (test_status == 2'b01) begin
            $display("[TEST] Basic test passed, running stress test...");
            #1000;  // Small delay between tests
            run_stress_test();
            wait (test_enabled == 1'b0);
        end else begin
            $display("[TEST] Basic test failed, skipping stress test");
        end

        $display("=== All tests completed ===");
        $finish;
    end

    // Simulation watchdog
    initial begin
        #20000000;  // 20ms max simulation time
        $display("[TEST] SIMULATION WATCHDOG: Terminating simulation");
        $finish;
    end

    // VCD file generation
    initial begin
        $dumpfile("production_test.vcd");
        $dumpvars(0, tb_spi_coax_production_simple);
    end

endmodule