`timescale 1ns / 1ps

`include "tb_common.vh"

module tb_spi_master;

    // ========================================================================
    // Test Control
    // ========================================================================
    reg test_failed;
    integer check_count, pass_count, fail_count;
    string section_name;
    
    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg clk_spi;
    reg rst_n;
    reg enable;
    reg miso;
    wire cs_n;
    wire sclk;
    wire mosi;
    wire [31:0] data_out;
    wire data_valid;

    // ========================================================================
    // Clock Generation (64MHz)
    // ========================================================================
    parameter real CLK_PERIOD = 15.625; // 64MHz
    
    initial begin
        clk_spi = 0;
        forever #(CLK_PERIOD/2) clk_spi = ~clk_spi;
    end

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    spi_master_rhs2116 u_dut (
        .clk_spi(clk_spi),
        .rst_n(rst_n),
        .enable(enable),
        .cs_n(cs_n),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .data_out(data_out),
        .data_valid(data_valid)
    );

    // ========================================================================
    // Simulated Slave with Configurable Response
    // ========================================================================
    reg [31:0] slave_data;
    reg [5:0] bit_cnt;
    reg [31:0] slave_shift_reg;
    
    always @(negedge cs_n) begin
        bit_cnt <= 0;
        slave_shift_reg <= slave_data;
    end

    always @(posedge sclk) begin
        if (!cs_n) begin
            miso <= slave_shift_reg[31];
            slave_shift_reg <= {slave_shift_reg[30:0], 1'b0};
            bit_cnt <= bit_cnt + 1;
        end else begin
            miso <= 1'b0;
        end
    end

    // ========================================================================
    // Monitoring and Checking
    // ========================================================================
    integer frame_count;
    integer sclk_period_start;
    integer sclk_period_measured;
    integer cs_inactive_start;
    integer cs_inactive_measured;
    
    // Monitor SCLK frequency
    always @(posedge sclk) begin
        if (sclk_period_start > 0) begin
            sclk_period_measured = $time - sclk_period_start;
            // Check SCLK is 16MHz (62.5ns period)
            `CHECK_RANGE(sclk_period_measured, 60, 65, "SCLK Period (ns)")
        end
        sclk_period_start = $time;
    end
    
    // Monitor CS inactive time
    always @(posedge cs_n) begin
        cs_inactive_start = $time;
    end
    
    always @(negedge cs_n) begin
        if (cs_inactive_start > 0) begin
            cs_inactive_measured = $time - cs_inactive_start;
            // CS should be inactive for 16 SCLK cycles (16 * 62.5ns = 1000ns)
            `CHECK_RANGE(cs_inactive_measured, 950, 1050, "CS Inactive Time (ns)")
        end
    end
    
    // Monitor data reception
    always @(posedge clk_spi) begin
        if (data_valid) begin
            frame_count = frame_count + 1;
            $display("[RX] Frame %0d: data=%h time=%0t", frame_count, data_out, $time);
        end
    end

    // ========================================================================
    // Test Scenarios
    // ========================================================================
    
    task reset_test;
        begin
            `TEST_SECTION("Reset and Initialization")
            
            rst_n = 0;
            enable = 0;
            #200;
            
            // Check outputs during reset
            `ASSERT(cs_n === 1'b1, "CS should be high during reset")
            `ASSERT(sclk === 1'b0, "SCLK should be low during reset")
            
            rst_n = 1;
            #100;
            
            `ASSERT(cs_n === 1'b1, "CS should remain high before enable")
            $display("Reset test completed");
        end
    endtask
    
    task normal_operation_test;
        begin
            `TEST_SECTION("Normal Operation - Single Transfer")
            
            slave_data = 32'hDEADBEEF;
            enable = 1;
            
            // Wait for first valid frame (after 2 discarded frames)
            repeat(2) @(posedge data_valid);
            @(posedge data_valid);
            
            // Check received data
            `CHECK_EQ(data_out, 32'hDEADBEEF, "First Valid Data")
            
            $display("Normal operation test completed");
        end
    endtask
    
    task continuous_operation_test;
        integer i;
        reg [31:0] expected_data;
        begin
            `TEST_SECTION("Continuous Operation - 20 Frames")
            
            for (i = 0; i < 20; i = i + 1) begin
                expected_data = 32'hA5A50000 + i;
                slave_data = expected_data;
                
                @(posedge data_valid);
                
                if (frame_count > 2) begin // Skip first 2 discarded frames
                    `CHECK_EQ(data_out, expected_data, $sformatf("Frame %0d", i))
                end
            end
            
            $display("Continuous operation test completed");
        end
    endtask
    
    task reset_during_transfer_test;
        begin
            `TEST_SECTION("Reset During Active Transfer")
            
            slave_data = 32'h12345678;
            enable = 1;
            
            // Wait for transfer to start
            @(negedge cs_n);
            #500;  // Mid-transfer
            
            // Assert reset
            rst_n = 0;
            #100;
            
            // Check CS goes high immediately
            `ASSERT(cs_n === 1'b1, "CS should go high on reset")
            
            // Release reset
            rst_n = 1;
            #100;
            
            // System should recover
            @(posedge data_valid);
            $display("System recovered after reset during transfer");
        end
    endtask
    
    task all_zeros_test;
        begin
            `TEST_SECTION("Data Pattern - All Zeros")
            
            slave_data = 32'h00000000;
            @(posedge data_valid);
            
            `CHECK_EQ(data_out, 32'h00000000, "All Zeros Pattern")
        end
    endtask
    
    task all_ones_test;
        begin
            `TEST_SECTION("Data Pattern - All Ones")
            
            slave_data = 32'hFFFFFFFF;
            @(posedge data_valid);
            
            `CHECK_EQ(data_out, 32'hFFFFFFFF, "All Ones Pattern")
        end
    endtask
    
    task alternating_pattern_test;
        begin
            `TEST_SECTION("Data Pattern - Alternating")
            
            slave_data = 32'hAA55AA55;
            @(posedge data_valid);
            `CHECK_EQ(data_out, 32'hAA55AA55, "Alternating Pattern 1")
            
            slave_data = 32'h55AA55AA;
            @(posedge data_valid);
            `CHECK_EQ(data_out, 32'h55AA55AA, "Alternating Pattern 2")
        end
    endtask
    
    task performance_measurement_test;
        integer start_time, end_time;
        integer num_frames;
        real frames_per_sec;
        begin
            `TEST_SECTION("Performance Measurement")
            
            num_frames = 100;
            slave_data = 32'hABCDEF00;
            
            start_time = $time;
            
            repeat(num_frames) @(posedge data_valid);
            
            end_time = $time;
            
            frames_per_sec = (num_frames * 1e9) / (end_time - start_time);
            
            $display("[PERFORMANCE] %0d frames in %0d ns", num_frames, end_time - start_time);
            $display("[PERFORMANCE] Frame rate: %.2f frames/sec", frames_per_sec);
            $display("[PERFORMANCE] Expected: ~446400 frames/sec (16MHz SCLK / 32 bits / 1.0625 gap)");
            
            // Should be around 446.4k frames/sec (allow ±10%)
            `CHECK_RANGE(frames_per_sec, 400000, 490000, "Frame Rate (frames/sec)")
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
        frame_count = 0;
        sclk_period_start = 0;
        cs_inactive_start = 0;
        
        $display("========================================");
        $display("SPI Master Testbench - Production Grade");
        $display("========================================");
        
        $dumpfile("tb_spi_master.vcd");
        $dumpvars(0, tb_spi_master);

        // Run test sequence
        reset_test();
        normal_operation_test();
        continuous_operation_test();
        all_zeros_test();
        all_ones_test();
        alternating_pattern_test();
        reset_during_transfer_test();
        performance_measurement_test();
        
        // Final report
        #1000;
        `TEST_REPORT
        
        $finish;
    end

endmodule
