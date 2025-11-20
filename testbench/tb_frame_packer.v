`timescale 1ns / 1ps

`include "tb_common.vh"

module tb_frame_packer;

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
    reg clk_sys;
    reg rst_n;
    reg [31:0] din;
    reg din_valid;
    wire tx_bit;
    wire tx_bit_valid;
    reg tx_bit_ready;
    wire [7:0] frame_count;

    // ========================================================================
    // Clock Generation
    // ========================================================================
    parameter real CLK_SPI_PERIOD = 15.625;  // 64MHz
    parameter real CLK_SYS_PERIOD = 10.0;    // 100MHz
    
    initial begin
        clk_spi = 0;
        forever #(CLK_SPI_PERIOD/2) clk_spi = ~clk_spi;
    end

    initial begin
        clk_sys = 0;
        forever #(CLK_SYS_PERIOD/2) clk_sys = ~clk_sys;
    end

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    frame_packer_100m u_dut (
        .clk_spi(clk_spi),
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .din(din),
        .din_valid(din_valid),
        .tx_bit(tx_bit),
        .tx_bit_valid(tx_bit_valid),
        .tx_bit_ready(tx_bit_ready),
        .frame_count(frame_count)
    );

    // ========================================================================
    // Frame Capture and Verification
    // ========================================================================
    reg [55:0] captured_frame;
    integer bit_index;
    reg [31:0] sent_data;
    reg [7:0] expected_frame_cnt;
    
    // Capture transmitted frame
    always @(posedge clk_sys) begin
        if (tx_bit_valid && tx_bit_ready) begin
            if (bit_index >= 56) bit_index = 0;
            
            captured_frame[55 - bit_index] = tx_bit;
            bit_index = bit_index + 1;
            
            // When frame complete, verify it
            if (bit_index == 56) begin
                verify_frame(captured_frame, sent_data, expected_frame_cnt);
            end
        end
    end
    
    // Verify frame structure and CRC
    task verify_frame;
        input [55:0] frame;
        input [31:0] expected_data;
        input [7:0] expected_cnt;
        
        reg [7:0] sync_byte;
        reg [7:0] cnt_byte;
        reg [31:0] data_field;
        reg [7:0] crc_field;
        reg [7:0] calculated_crc;
        begin
            sync_byte = frame[55:48];
            cnt_byte = frame[47:40];
            data_field = frame[39:8];
            crc_field = frame[7:0];
            
            $display("[FRAME VERIFY] SYNC=%02h CNT=%02h DATA=%08h CRC=%02h", 
                     sync_byte, cnt_byte, data_field, crc_field);
            
            // Check SYNC byte
            `CHECK_EQ(sync_byte, 8'hAA, "SYNC Byte")
            
            // Check counter
            `CHECK_EQ(cnt_byte, expected_cnt, "Frame Counter")
            
            // Check data
            `CHECK_EQ(data_field, expected_data, "Data Field")
            
            // Verify CRC
            calculated_crc = calc_crc8({sync_byte, cnt_byte, data_field});
            `CHECK_EQ(crc_field, calculated_crc, "CRC")
        end
    endtask
    
    // ========================================================================
    // Test Scenarios
    // ========================================================================
    
    task reset_test;
        begin
            `TEST_SECTION("Reset and Initialization")
            
            rst_n = 0;
            din = 0;
            din_valid = 0;
            tx_bit_ready = 0;
            bit_index = 0;
            
            #200;
            rst_n = 1;
            #100;
            
            `ASSERT(frame_count === 8'h00, "Frame counter should be 0 after reset")
            `ASSERT(tx_bit_valid === 1'b0, "No valid bits should be output after reset")
            
            $display("Reset test completed");
        end
    endtask
    
    task single_frame_test;
        begin
            `TEST_SECTION("Single Frame Transmission")
            
            sent_data = 32'hAABBCCDD;
            expected_frame_cnt = 8'h00;
            bit_index = 0;
            
            // Write data to FIFO
            @(posedge clk_spi);
            din = sent_data;
            din_valid = 1;
            @(posedge clk_spi);
            din_valid = 0;
            
            // Allow FIFO time to cross clock domains
            #200;
            
            // Enable bit transmission
            tx_bit_ready = 1;
            
            // Wait for frame to complete
            wait(bit_index == 56);
            #100;
            
            expected_frame_cnt = 8'h01;
            $display("Single frame test completed");
        end
    endtask
    
    task multiple_frames_test;
        integer i;
        reg [31:0] test_data;
        begin
            `TEST_SECTION("Multiple Frames - Sequential")
            
            tx_bit_ready = 1;
            
            for (i = 0; i < 5; i = i + 1) begin
                test_data = 32'h11110000 + i;
                sent_data = test_data;
                expected_frame_cnt = expected_frame_cnt;
                
                // Send data
                @(posedge clk_spi);
                din = test_data;
                din_valid = 1;
                @(posedge clk_spi);
                din_valid = 0;
                
                // Wait for frame transmission
                bit_index = 0;
                wait(bit_index == 56);
                #100;
                
                expected_frame_cnt = expected_frame_cnt + 1;
            end
            
            $display("Multiple frames test completed");
        end
    endtask
    
    task backpressure_test;
        begin
            `TEST_SECTION("Backpressure Handling")
            
            sent_data = 32'h55555555;
            bit_index = 0;
            
            // Send data
            @(posedge clk_spi);
            din = sent_data;
            din_valid = 1;
            @(posedge clk_spi);
            din_valid = 0;
            
            #200;
            
            // Start transmission with intermittent backpressure
            for (integer i = 0; i < 56; i = i + 1) begin
                @(posedge clk_sys);
                // Randomly deassert ready
                if ((i % 7) == 0)
                    tx_bit_ready = 0;
                else
                    tx_bit_ready = 1;
            end
            
            tx_bit_ready = 1;
            wait(bit_index == 56);
            
            $display("Backpressure test completed");
            expected_frame_cnt = expected_frame_cnt + 1;
        end
    endtask
    
    task counter_increment_test;
        integer i;
        reg [7:0] prev_count;
        begin
            `TEST_SECTION("Frame Counter Increment")
            
            tx_bit_ready = 1;
            prev_count = frame_count;
            
            for (i = 0; i < 10; i = i + 1) begin
                sent_data = 32'hC0FFEE00 + i;
                
                @(posedge clk_spi);
                din = sent_data;
                din_valid = 1;
                @(posedge clk_spi);
                din_valid = 0;
                
                // Wait for frame
                bit_index = 0;
                wait(bit_index == 56);
                #100;
                
                // Check counter incremented
                `ASSERT(frame_count === (prev_count + 1), 
                        $sformatf("Counter should increment (prev=%h current=%h)", 
                                  prev_count, frame_count))
                
                prev_count = frame_count;
                expected_frame_cnt = expected_frame_cnt + 1;
            end
            
            $display("Counter increment test completed");
        end
    endtask
    
    task data_pattern_test;
        begin
            `TEST_SECTION("Data Patterns - Edge Cases")
            
            tx_bit_ready = 1;
            
            // All zeros
            sent_data = 32'h00000000;
            @(posedge clk_spi);
            din = sent_data;
            din_valid = 1;
            @(posedge clk_spi);
            din_valid = 0;
            bit_index = 0;
            wait(bit_index == 56);
            expected_frame_cnt = expected_frame_cnt + 1;
            #100;
            
            // All ones
            sent_data = 32'hFFFFFFFF;
            @(posedge clk_spi);
            din = sent_data;
            din_valid = 1;
            @(posedge clk_spi);
            din_valid = 0;
            bit_index = 0;
            wait(bit_index == 56);
            expected_frame_cnt = expected_frame_cnt + 1;
            #100;
            
            $display("Data pattern test completed");
        end
    endtask
    
    task throughput_test;
        integer start_time, end_time;
        integer num_frames;
        real mbps;
        begin
            `TEST_SECTION("Throughput Measurement")
            
            num_frames = 20;
            tx_bit_ready = 1;
            
            start_time = $time;
            
            for (integer i = 0; i < num_frames; i = i + 1) begin
                sent_data = 32'hBEEF0000 + i;
                
                @(posedge clk_spi);
                din = sent_data;
                din_valid = 1;
                @(posedge clk_spi);
                din_valid = 0;
                
                bit_index = 0;
                wait(bit_index == 56);
                expected_frame_cnt = expected_frame_cnt + 1;
            end
            
            end_time = $time;
            
            // Calculate throughput
            mbps = (num_frames * 32 * 1000.0) / (end_time - start_time);
            
            $display("[PERFORMANCE] %0d frames (32-bit data each) in %0d ns", 
                     num_frames, end_time - start_time);
            $display("[PERFORMANCE] Data throughput: %.2f Mbps", mbps);
            $display("[PERFORMANCE] Frame rate: ~25 Mbps (56 bits @ 100MHz / 4 clocks per bit)");
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
        bit_index = 0;
        expected_frame_cnt = 8'h00;
        
        $display("========================================");
        $display("Frame Packer Testbench - Production Grade");
        $display("========================================");
        
        $dumpfile("tb_frame_packer.vcd");
        $dumpvars(0, tb_frame_packer);

        // Run test sequence
        reset_test();
        single_frame_test();
        multiple_frames_test();
        backpressure_test();
        counter_increment_test();
        data_pattern_test();
        throughput_test();
        
        // Final report
        #1000;
        `TEST_REPORT
        
        $finish;
    end

endmodule
