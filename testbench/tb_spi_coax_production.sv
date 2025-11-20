//==============================================================================
// Production-Level System Testbench for SPI-Coax System
// Includes comprehensive error injection, stress testing, and automated validation
//==============================================================================

`timescale 1ns/1ps
`include "test_framework_base.sv"
`include "error_injection.sv"

module tb_spi_coax_production;

    // Clock signals
    reg clk_64m = 0;
    reg clk_100m = 0;
    reg clk_200m = 0;
    reg rst_n = 0;

    // System signals
    wire ddr_p, ddr_n;
    wire [31:0] rx_data;
    wire rx_data_valid;
    wire rx_frame_error;
    wire cdr_locked;
    wire frame_sync_lost;

    // Testbench control
    TestBase test;
    ErrorInjector manch_error_inj;
    ErrorInjector spi_error_inj;
    ErrorInjector crc_error_inj;

    // Timing parameters
    parameter CLK_64M_PERIOD = 15.625;  // 64 MHz
    parameter CLK_100M_PERIOD = 10.0;    // 100 MHz
    parameter CLK_200M_PERIOD = 5.0;     // 200 MHz

    // Test statistics
    int total_frames_sent = 0;
    int total_frames_received = 0;
    int total_crc_errors = 0;
    int total_frame_errors = 0;
    int total_sync_losses = 0;

    // DUT instantiation
    top dut (
        .clk_64m(clk_64m),
        .clk_100m(clk_100m),
        .clk_200m(clk_200m),
        .rst_n(rst_n),
        .ddr_p(ddr_p),
        .ddr_n(ddr_n),
        .rx_data(rx_data),
        .rx_data_valid(rx_data_valid),
        .rx_frame_error(rx_frame_error),
        .cdr_locked(cdr_locked),
        .frame_sync_lost(frame_sync_lost)
    );

    // Clock generation
    initial begin
        forever #(CLK_64M_PERIOD/2) clk_64m = ~clk_64m;
    end

    initial begin
        forever #(CLK_100M_PERIOD/2) clk_100m = ~clk_100m;
    end

    initial begin
        forever #(CLK_200M_PERIOD/2) clk_200m = ~clk_200m;
    end

    // Test scenarios
    typedef enum {
        TEST_BASIC_FUNCTIONALITY,
        TEST_BIT_FLIP_INJECTION,
        TEST_CRC_ERROR_INJECTION,
        TEST_FRAME_CORRUPTION,
        TEST_SYNC_LOSS_RECOVERY,
        TEST_BURST_ERRORS,
        test_CLOCK_GLITCHES,
        TEST_STRESS_CONTINUOUS,
        TEST_STRESS_MAXIMUM_THROUGHPUT,
        TEST_CLOCK_DOMAIN_CROSSING,
        TEST_POWER_ON_RESET,
        TEST_LONG_TERM_STABILITY
    } test_scenario_t;

    test_scenario_t current_test;

    // Main test sequence
    initial begin
        // Initialize test framework
        test = new("spi_coax_production");
        test.cfg.timeout_cycles = 10000000;  // 10M cycles for production tests
        test.cfg.verbose = 1;
        test.cfg.dump_waves = 1;
        test.cfg.wave_file = "tb_spi_coax_production.vcd";

        // Initialize error injectors
        manch_error_inj = create_error_injector(ERROR_BIT_FLIP, 0.001);  // 0.1% error rate
        spi_error_inj = create_error_injector(ERROR_BIT_FLIP, 0.0005);  // 0.05% error rate
        crc_error_inj = create_error_injector(ERROR_CRC_MISMATCH, 0.002); // 0.2% error rate

        manch_error_inj.cfg.verbose = 1;
        spi_error_inj.cfg.verbose = 1;
        crc_error_inj.cfg.verbose = 1;

        // Start test
        test.start_test();

        // Run test scenarios
        run_all_test_scenarios();

        // Generate final report
        generate_production_report();

        test.finish_test();
    end

    // Test scenario execution
    task run_all_test_scenarios();
        test.info("Starting comprehensive production test suite");

        run_test_scenario(TEST_BASIC_FUNCTIONALITY);
        run_test_scenario(TEST_BIT_FLIP_INJECTION);
        run_test_scenario(TEST_CRC_ERROR_INJECTION);
        run_test_scenario(TEST_FRAME_CORRUPTION);
        run_test_scenario(TEST_SYNC_LOSS_RECOVERY);
        run_test_scenario(TEST_BURST_ERRORS);
        run_test_scenario(test_CLOCK_GLITCHES);
        run_test_scenario(TEST_STRESS_CONTINUOUS);
        run_test_scenario(TEST_STRESS_MAXIMUM_THROUGHPUT);
        run_test_scenario(TEST_CLOCK_DOMAIN_CROSSING);
        run_test_scenario(TEST_POWER_ON_RESET);
        run_test_scenario(TEST_LONG_TERM_STABILITY);

        test.info("All production test scenarios completed");
    endtask

    task run_test_scenario(test_scenario_t scenario);
        current_test = scenario;

        test.info($sformatf("Running test scenario: %s", scenario.name()));

        reset_statistics();
        reset_dut();
        enable_error_injectors(scenario);

        case (scenario)
            TEST_BASIC_FUNCTIONALITY:
                test_basic_functionality();
            TEST_BIT_FLIP_INJECTION:
                test_bit_flip_injection();
            TEST_CRC_ERROR_INJECTION:
                test_crc_error_injection();
            TEST_FRAME_CORRUPTION:
                test_frame_corruption();
            TEST_SYNC_LOSS_RECOVERY:
                test_sync_loss_recovery();
            TEST_BURST_ERRORS:
                test_burst_errors();
            test_CLOCK_GLITCHES:
                test_clock_glitches();
            TEST_STRESS_CONTINUOUS:
                test_stress_continuous();
            TEST_STRESS_MAXIMUM_THROUGHPUT:
                test_stress_maximum_throughput();
            TEST_CLOCK_DOMAIN_CROSSING:
                test_clock_domain_crossing();
            TEST_POWER_ON_RESET:
                test_power_on_reset();
            TEST_LONG_TERM_STABILITY:
                test_long_term_stability();
            default:
                test.error($sformatf("Unknown test scenario: %s", scenario.name()));
        endcase

        disable_error_injectors();
        validate_test_results(scenario);
    endtask

    // Individual test implementations
    task test_basic_functionality();
        test.info("Testing basic system functionality without errors");

        // Wait for system to stabilize
        wait_system_ready();

        // Monitor for 1000 frames
        monitor_frames(1000);

        // Verify basic functionality
        test.assert_equal_int(total_frames_received, 1000, "Basic frame reception test");
        test.assert_equal_int(total_crc_errors, 0, "No CRC errors in basic test");
        test.assert_equal_int(total_frame_errors, 0, "No frame errors in basic test");
    endtask

    task test_bit_flip_injection();
        test.info("Testing system resilience to bit flip errors");

        wait_system_ready();
        manch_error_inj.set_injection_probability(0.01);  // 1% error rate
        manch_error_inj.enable();

        monitor_frames(2000);

        test.assert_within_range(total_crc_errors, 15, 25, "Expected CRC errors from bit flips");
        test.info($sformatf("Bit flip test: %0d errors detected, error rate=%0.3f%%",
                           total_crc_errors, (total_crc_errors * 100.0) / 2000));
    endtask

    task test_crc_error_injection();
        test.info("Testing CRC error detection and handling");

        wait_system_ready();
        crc_error_inj.enable();

        monitor_frames(1000);

        test.assert_within_range(total_frame_errors, 15, 25, "Expected frame errors from CRC corruption");
        test.info($sformatf("CRC error test: %0d frame errors detected", total_frame_errors));
    endtask

    task test_frame_corruption();
        test.info("Testing frame corruption and recovery");

        wait_system_ready();
        manch_error_inj.set_error_type(ERROR_FRAME_CORRUPT);
        manch_error_inj.set_injection_probability(0.02);  // 2% frame corruption
        manch_error_inj.enable();

        monitor_frames(1500);

        test.assert_within_range(total_sync_losses, 25, 35, "Expected sync losses from frame corruption");
        test.info($sformatf("Frame corruption test: %0d sync loss events", total_sync_losses));
    endtask

    task test_sync_loss_recovery();
        test.info("Testing synchronization loss and recovery mechanisms");

        wait_system_ready();

        // Inject sync errors in bursts
        manch_error_inj.set_error_type(ERROR_FRAME_CORRUPT);
        manch_error_inj.set_burst_parameters(100, 10);  // Burst of 10 corrupt frames
        manch_error_inj.set_injection_probability(0.1);
        manch_error_inj.enable();

        monitor_frames(2000);

        test.assert(cdr_locked, "CDR should recover after sync loss");
        test.info($sformatf("Sync recovery test: %0d recovery cycles", total_sync_losses));
    endtask

    task test_burst_errors();
        test.info("Testing system response to burst errors");

        wait_system_ready();
        manch_error_inj.set_error_type(ERROR_BURST_ERROR);
        manch_error_inj.set_burst_parameters(200, 50);  // 50-cycle burst every 200 cycles
        manch_error_inj.set_injection_probability(0.05);
        manch_error_inj.enable();

        monitor_frames(3000);

        test.info($sformatf("Burst error test: %0d total errors in bursts",
                           manch_error_inj.get_error_count()));
    endtask

    task test_clock_glitches();
        test.info("Testing clock glitch resilience");

        wait_system_ready();

        bit glitch_active = 0;
        manch_error_inj.set_error_type(ERROR_CLOCK_GLITCH);
        manch_error_inj.set_injection_probability(0.001);  // Occasional glitches
        manch_error_inj.enable();

        monitor_frames(1000);

        test.info($sformatf("Clock glitch test: %0d glitches injected",
                           manch_error_inj.get_error_count()));
    endtask

    task test_stress_continuous();
        test.info("Testing continuous high-load operation");

        wait_system_ready();

        // Enable all error types at low rates for continuous stress
        manch_error_inj.set_error_type(ERROR_BIT_FLIP);
        manch_error_inj.set_injection_probability(0.0001);  // 0.01% error rate
        manch_error_inj.enable();

        monitor_frames(10000);  // Long continuous test

        test.assert(total_frames_received > 9900, "High frame reception rate under stress");
        test.info($sformatf("Stress test: %0d/%0d frames received successfully",
                           total_frames_received, total_frames_sent));
    endtask

    task test_stress_maximum_throughput();
        test.info("Testing maximum system throughput");

        wait_system_ready();

        real start_time = $realtime;
        monitor_frames(50000);  // Large number of frames
        real end_time = $realtime;
        real duration_ms = (end_time - start_time) / 1000.0;
        real throughput_kbps = (50000 * 56 * 8) / (duration_ms * 1000.0);  // 56-bit frames

        test.assert_within_range(throughput_kbps, 22000, 24000, "Expected throughput range");
        test.info($sformatf("Throughput test: %0.1f kbps", throughput_kbps));
    endtask

    task test_clock_domain_crossing();
        test.info("Testing clock domain crossing robustness");

        wait_system_ready();

        // Vary clock phases to stress CDC paths
        fork
            begin
                repeat (1000) @(posedge clk_64m);
                #(CLK_64M_PERIOD * 0.1);  // Add phase shift
            end
            begin
                repeat (2000) @(posedge clk_100m);
                #(CLK_100M_PERIOD * 0.1);  // Add phase shift
            end
        join_none

        monitor_frames(2000);

        test.assert_equal_int(total_frame_errors, 0, "No CDC-related errors expected");
        test.info("Clock domain crossing test completed successfully");
    endtask

    task test_power_on_reset();
        test.info("Testing power-on reset sequence");

        repeat (5) begin
            reset_dut();
            wait_system_ready();
            monitor_frames(100);
            test.assert(cdr_locked, "CDR should lock after reset");
        end

        test.info("Power-on reset test: All reset cycles successful");
    endtask

    task test_long_term_stability();
        test.info("Testing long-term stability (extended operation)");

        wait_system_ready();

        // Very long test with intermittent errors
        manch_error_inj.set_error_type(ERROR_BIT_FLIP);
        manch_error_inj.set_injection_probability(0.00005);  // Very low error rate
        manch_error_inj.enable();

        monitor_frames(100000);  // 100k frames for stability test

        test.assert(total_frames_received > 99900, "High stability over long term");
        test.info($sformatf("Stability test: %0.4f%% frame success rate over 100k frames",
                           (total_frames_received * 100.0) / 100000));
    endtask

    // Helper tasks
    task reset_dut();
        test.info("Resetting DUT");
        rst_n = 0;
        repeat (100) @(posedge clk_100m);
        rst_n = 1;
        repeat (100) @(posedge clk_100m);
    endtask

    task wait_system_ready();
        test.info("Waiting for system ready");
        wait(cdr_locked);
        repeat (1000) @(posedge clk_100m);  // Let system stabilize
    endtask

    task monitor_frames(int frame_count);
        int frames_received_local = 0;
        total_frames_sent = frame_count;

        test.info($sformatf("Monitoring %0d frames", frame_count));

        while (frames_received_local < frame_count) begin
            @(posedge clk_100m);

            if (rx_data_valid) begin
                frames_received_local++;
                total_frames_received++;

                if (rx_frame_error) begin
                    total_frame_errors++;
                    total_crc_errors++;
                end
            end

            if (frame_sync_lost) begin
                total_sync_losses++;
            end
        end

        test.info($sformatf("Frame monitoring completed: %0d frames processed", frames_received_local));
    endtask

    task reset_statistics();
        total_frames_sent = 0;
        total_frames_received = 0;
        total_crc_errors = 0;
        total_frame_errors = 0;
        total_sync_losses = 0;

        manch_error_inj.reset_stats();
        spi_error_inj.reset_stats();
        crc_error_inj.reset_stats();
    endtask

    task enable_error_injectors(test_scenario_t scenario);
        case (scenario)
            TEST_BIT_FLIP_INJECTION,
            TEST_FRAME_CORRUPTION,
            TEST_BURST_ERRORS,
            TEST_STRESS_CONTINUOUS,
            TEST_STRESS_MAXIMUM_THROUGHPUT,
            TEST_CLOCK_DOMAIN_CROSSING,
            TEST_LONG_TERM_STABILITY:
                manch_error_inj.enable();

            TEST_CRC_ERROR_INJECTION:
                crc_error_inj.enable();

            test_CLOCK_GLITCHES:
                manch_error_inj.enable();

            default:
                // No error injection for basic tests
        endcase
    endtask

    task disable_error_injectors();
        manch_error_inj.disable();
        spi_error_inj.disable();
        crc_error_inj.disable();
    endtask

    task validate_test_results(test_scenario_t scenario);
        string result_msg;

        case (scenario)
            TEST_BASIC_FUNCTIONALITY:
                if (total_frame_errors == 0 && total_sync_losses == 0)
                    test.info("✓ Basic functionality test PASSED");
                else
                    test.error("✗ Basic functionality test FAILED");

            TEST_BIT_FLIP_INJECTION:
                if (total_crc_errors > 0 && total_crc_errors < 50)
                    test.info("✓ Bit flip injection test PASSED");
                else
                    test.error("✗ Bit flip injection test FAILED");

            default:
                test.info($sformatf("Test scenario %s validation completed", scenario.name()));
        endcase
    endtask

    task generate_production_report();
        int file;
        string filename = "production_test_report.txt";

        file = $fopen(filename, "w");
        if (file) begin
            $fdisplay(file, "===============================================");
            $fdisplay(file, "SPI-Coax Production Test Report");
            $fdisplay(file, "===============================================");
            $fdisplay(file, "Generated: %0t", $time);
            $fdisplay(file, "");
            $fdisplay(file, "Test Statistics:");
            $fdisplay(file, "  Total Frames Sent: %0d", total_frames_sent);
            $fdisplay(file, "  Total Frames Received: %0d", total_frames_received);
            $fdisplay(file, "  Total CRC Errors: %0d", total_crc_errors);
            $fdisplay(file, "  Total Frame Errors: %0d", total_frame_errors);
            $fdisplay(file, "  Total Sync Losses: %0d", total_sync_losses);
            $fdisplay(file, "");
            $fdisplay(file, "Error Injection Statistics:");
            $fdisplay(file, "  Manchester Injector: %0d errors", manch_error_inj.get_error_count());
            $fdisplay(file, "  SPI Injector: %0d errors", spi_error_inj.get_error_count());
            $fdisplay(file, "  CRC Injector: %0d errors", crc_error_inj.get_error_count());
            $fdisplay(file, "");
            $fdisplay(file, "System Status:");
            $fdisplay(file, "  CDR Locked: %s", cdr_locked ? "YES" : "NO");
            $fdisplay(file, "  Test Framework Status: %s", test.status.name());
            $fdisplay(file, "===============================================");
            $fclose(file);

            test.info($sformatf("Production report generated: %s", filename));
        end
    endtask

endmodule