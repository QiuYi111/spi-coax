`timescale 1ns / 1ps

`include "tb_common.vh"
`include "scoreboard.vh"

module tb_spi_coax_system_enhanced;

    // ========================================================================
    // Test Control
    // ========================================================================
    reg test_failed;
    integer check_count, pass_count, fail_count;
    string section_name;

    // ========================================================================
    // Clock Generation
    // ========================================================================
    reg clk_spi;    // 64MHz  
    reg clk_sys;    // 100MHz
    reg clk_link;   // 200MHz
    reg rst_n;

    parameter real CLK_SPI_PERIOD = 15.625;
    parameter real CLK_SYS_PERIOD = 10.0;
    parameter real CLK_LINK_PERIOD = 5.0;

    initial begin
        clk_spi = 0;
        forever #(CLK_SPI_PERIOD/2) clk_spi = ~clk_spi;
    end

    initial begin
        clk_sys = 0;
        forever #(CLK_SYS_PERIOD/2) clk_sys = ~clk_sys;
    end

    initial begin
        clk_link = 0;
        forever #(CLK_LINK_PERIOD/2) clk_link = ~clk_link;
    end

    // ========================================================================
    // Signals
    // ========================================================================
    reg enable;
    
    // SPI Interface
    wire cs_n;
    wire sclk;
    wire mosi;
    reg  miso;

    // Decoder Output
    wire [31:0] rx_data;
    wire        rx_valid;
    wire        cdr_locked;
    wire        frame_error;
    wire        sync_lost;

    // Status
    wire link_active;
    wire [7:0] tx_frame_cnt;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    top u_top (
        .clk_spi    (clk_spi),
        .clk_sys    (clk_sys),
        .clk_link   (clk_link),
        .rst_n      (rst_n),
        .enable     (enable),
        .cs_n       (cs_n),
        .sclk       (sclk),
        .mosi       (mosi),
        .miso       (miso),
        .rx_data    (rx_data),
        .rx_valid   (rx_valid),
        .link_active(link_active),
        .cdr_locked (cdr_locked),
        .frame_error(frame_error),
        .sync_lost  (sync_lost),
        .tx_frame_cnt(tx_frame_cnt)
    );

    // ========================================================================
    // Simulated RHS2116 Sensor
    // ========================================================================
    reg [31:0] sensor_data;
    reg [5:0]  bit_cnt;
    reg [31:0] sensor_shift_reg;
    
    // Data patterns for testing
    typedef enum {
        PATTERN_INCREMENT,
        PATTERN_RANDOM,
        PATTERN_FIXED,
        PATTERN_ALTERNATING
    } pattern_mode_t;
    
    pattern_mode_t pattern_mode;
    reg [31:0] fixed_pattern;
    
    always @(negedge cs_n or negedge rst_n) begin
        if (!rst_n) begin
            sensor_data <= 32'h00000000;
            bit_cnt <= 6'd0;
        end else begin
            // Generate next data based on mode
            case (pattern_mode)
                PATTERN_INCREMENT: sensor_data <= sensor_data + 1;
                PATTERN_RANDOM: sensor_data <= random_data();
                PATTERN_FIXED: sensor_data <= fixed_pattern;
                PATTERN_ALTERNATING: sensor_data <= ~sensor_data;
                default: sensor_data <= sensor_data + 1;
            endcase
            
            sensor_shift_reg <= sensor_data;
            bit_cnt <= 6'd0;
            
            // Push to scoreboard
            sb_push(sensor_data, 8'h00);
        end
    end
    
    always @(posedge sclk or negedge cs_n) begin
        if (!cs_n) begin
            miso <= sensor_shift_reg[31];
            sensor_shift_reg <= {sensor_shift_reg[30:0], 1'b0};
            bit_cnt <= bit_cnt + 1;
        end else begin
            miso <= 1'b0;
        end
    end

    // ========================================================================
    // Scoreboard-based Verification
    // ========================================================================
    
    integer frames_transmitted;
    integer frames_received;
    integer frames_matched;
    integer frames_mismatched;
    integer lock_time;
    integer first_valid_time;
    reg matched;
    
    // Monitor transmissions
    always @(posedge clk_spi) begin
        if (cs_n === 1'b0 && bit_cnt === 6'd0) begin  // Start of SPI transaction
            frames_transmitted = frames_transmitted + 1;
        end
    end
    
    // Check received data against scoreboard
    always @(posedge clk_sys) begin
        if (rx_valid) begin
            frames_received = frames_received + 1;
            
            if (first_valid_time == 0) first_valid_time = $time;
            
            // Check against scoreboard
            sb_check(rx_data, 8'h00, matched);
            
            if (matched) begin
                frames_matched = frames_matched + 1;
            end else begin
                frames_mismatched = frames_mismatched + 1;
            end
        end
        
        if (frame_error) begin
            $warning("[FRAME ERROR] CRC mismatch detected at time %0t", $time);
        end
    end
    
    // Monitor CDR lock
    always @(posedge cdr_locked) begin
        lock_time = $time;
        $display("[CDR LOCK] Acquired at time %0t (%.2f us)", lock_time, lock_time / 1000.0);
    end

    // ========================================================================
    // Test Scenarios
    // ========================================================================
    
    task reset_sequence;
        begin
            `TEST_SECTION("Reset Sequence")
            
            rst_n = 0;
            enable = 0;
            miso = 0;
            sensor_data = 32'h00000000;
            
            #500;
            rst_n = 1;
            #500;
            
            $display("Reset sequence completed");
        end
    endtask
    
    task basic_loopback_test;
        integer timeout;
        begin
            `TEST_SECTION("Basic Loopback - Increment Pattern")
            
            pattern_mode = PATTERN_INCREMENT;
            sensor_data = 32'h00000000;
            
            // Initialize scoreboard
            sb_init(1024);
            
            // Enable link
            enable = 1;
            
            // Wait for CDR lock
            timeout = 0;
            while (!cdr_locked && timeout < 2000000) begin  // 2ms timeout
                @(posedge clk_sys);
                timeout = timeout + 1;
            end
            
            `ASSERT(cdr_locked === 1'b1, "CDR should lock within 2ms")
            
            // Wait for first valid data
            wait(rx_valid);
            $display("[FIRST DATA] Received at time %0t", $time);
            
            // Collect frames
            while (frames_received < 20) begin
                @(posedge clk_sys);
            end
            
            $display("Basic loopback test completed");
        end
    endtask
    
    task random_data_test;
        begin
            `TEST_SECTION("Random Data Pattern")
            
            pattern_mode = PATTERN_RANDOM;
            
            // Collect frames
            while (frames_received < 50) begin
                @(posedge clk_sys);
            end
            
            $display("Random data test completed");
        end
    endtask
    
    task fixed_pattern_test;
        begin
            `TEST_SECTION("Fixed Pattern Tests")
            
            // All zeros
            pattern_mode = PATTERN_FIXED;
            fixed_pattern = 32'h00000000;
            
            repeat(10) begin
                wait(rx_valid);
                @(posedge clk_sys);
            end
            
            // All ones
            fixed_pattern = 32'hFFFFFFFF;
            repeat(10) begin
                wait(rx_valid);
                @(posedge clk_sys);
            end
            
            // Alternating
            fixed_pattern = 32'hAAAA5555;
            repeat(10) begin
                wait(rx_valid);
                @(posedge clk_sys);
            end
            
            $display("Fixed pattern test completed");
        end
    endtask
    
    task long_duration_test;
        integer start_time, end_time;
        integer target_frames;
        begin
            `TEST_SECTION("Long Duration Stress Test")
            
            pattern_mode = PATTERN_INCREMENT;
            target_frames = 1000;
            
            start_time = $time;
            
            // Run until we get target frames
            while (frames_received < target_frames) begin
                @(posedge clk_sys);
                
                // Monitor for errors
                if (sync_lost) begin
                    $error("[SYNC LOST] During long duration test at frame %0d", frames_received);
                end
            end
            
            end_time = $time;
            
            $display("[LONG TEST] Received %0d frames in %0d ns (%.2f ms)", 
                     target_frames, end_time - start_time, (end_time - start_time) / 1e6);
            
            $display("Long duration test completed");
        end
    endtask
    
    task reset_during_operation_test;
        begin
            `TEST_SECTION("Reset During Active Operation")
            
            pattern_mode = PATTERN_INCREMENT;
            
            // Let system run
            repeat(20) begin
                wait(rx_valid);
                @(posedge clk_sys);
            end
            
            // Assert reset
            $display("Asserting reset during operation");
            rst_n = 0;
            #1000;
            rst_n = 1;
            #1000;
            
            // Re-enable
            enable = 1;
            
            // Wait for CDR lock
            wait(cdr_locked);
            $display("CDR relocked after reset");
            
            // Verify recovery
            wait(rx_valid);
            $display("Data reception recovered");
            
            $display("Reset during operation test completed");
        end
    endtask
    
    task performance_measurement;
        integer start_time, end_time;
        integer measurement_frames;
        integer start_frames;
        real throughput_mbps;
        real latency_avg;
        real frame_rate;
        begin
            `TEST_SECTION("Performance Measurement")
            
            measurement_frames = 100;
            start_frames = frames_received;
            start_time = $time;
            
            // Collect measurement frames
            while (frames_received < (start_frames + measurement_frames)) begin
                @(posedge clk_sys);
            end
            
            end_time = $time;
            
            // Calculate metrics
            throughput_mbps = (measurement_frames * 32 * 1000.0) / (end_time - start_time);
            frame_rate = (measurement_frames * 1e9) / (end_time - start_time);
            
            if (sb_matched > 0) begin
                latency_avg = sb_latency_sum / sb_matched;
            end else begin
                latency_avg = 0;
            end
            
            $display("");
            $display("========================================");
            $display("PERFORMANCE METRICS");
            $display("========================================");
            $display("Measurement Period:  %0d ns (%.2f ms)", 
                     end_time - start_time, (end_time - start_time) / 1e6);
            $display("Frames Measured:     %0d", measurement_frames);
            $display("Data Throughput:     %.2f Mbps", throughput_mbps);
            $display("Frame Rate:          %.2f frames/sec", frame_rate);
            $display("CDR Lock Time:       %0d ns (%.2f us)", lock_time, lock_time / 1000.0);
            
            if (sb_matched > 0) begin
                $display("Latency Min:         %0d ns", sb_latency_min);
                $display("Latency Avg:         %.2f ns (%.2f us)", latency_avg, latency_avg / 1000.0);
                $display("Latency Max:         %0d ns", sb_latency_max);
            end
            
            $display("========================================");
            
            // Verify performance targets
            `CHECK_RANGE(throughput_mbps, 20, 25, "Throughput (Mbps)")
            `CHECK_RANGE(lock_time, 0, 20000000, "Lock Time (ns, < 20ms)")
            
            $display("Performance measurement completed");
        end
    endtask

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    
    initial begin
        // Initialize
        test_failed = 0;
        check_count = 0;
        pass_count = 0;
        fail_count = 0;
        frames_transmitted = 0;
        frames_received = 0;
        frames_matched = 0;
        frames_mismatched = 0;
        lock_time = 0;
        first_valid_time = 0;
        
        $display("========================================");
        $display("SPI-Coax System Testbench - Production Grade");
        $display("========================================");
        
        $dumpfile("tb_spi_coax_system_enhanced.vcd");
        $dumpvars(0, tb_spi_coax_system_enhanced);

        // Run test sequence
        reset_sequence();
        basic_loopback_test();
        random_data_test();
        fixed_pattern_test();
        long_duration_test();
        reset_during_operation_test();
        performance_measurement();
        
        // Scoreboard report
        sb_report();
        
        // System statistics
        $display("");
        $display("========================================");
        $display("SYSTEM STATISTICS");
        $display("========================================");
        $display("Frames Transmitted:  %0d", frames_transmitted);
        $display("Frames Received:     %0d", frames_received);
        $display("Frames Matched:      %0d", frames_matched);
        $display("Frames Mismatched:   %0d", frames_mismatched);
        if (frames_received > 0) begin
            $display("Match Rate:          %.2f%%", (frames_matched * 100.0) / frames_received);
        end
        $display("========================================");
        
        // Final assertions
        `ASSERT(frames_mismatched === 0, "No data mismatches should occur")
        `ASSERT(sb_has_errors() === 0, "Scoreboard should have no errors")
        
        // Final report
        #1000;
        `TEST_REPORT
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100000000;  // 100ms total test timeout
        $error("[TIMEOUT] Test did not complete within 100ms");
        $finish;
    end

endmodule
