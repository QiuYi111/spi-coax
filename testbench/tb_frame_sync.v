`timescale 1ns / 1ps

`include "tb_common.vh"

module tb_frame_sync;

    // ========================================================================
    // Test Control
    // ========================================================================
    reg test_failed;
    integer check_count, pass_count, fail_count;
    string section_name;

    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg clk_sys;
    reg rst_n;
    reg bit_in;
    reg bit_valid;
    wire [31:0] data_out;
    wire data_valid;
    wire frame_error;
    wire sync_lost;

    // ========================================================================
    // Clock Generation (200MHz - same as CDR output)
    // ========================================================================
    parameter real CLK_PERIOD = 5.0;  // 200MHz (clk_link in actual system)
    
    initial begin
        clk_sys = 0;
        forever #(CLK_PERIOD/2) clk_sys = ~clk_sys;
    end

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    frame_sync_100m u_dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .bit_in(bit_in),
        .bit_valid(bit_valid),
        .data_out(data_out),
        .data_valid(data_valid),
        .frame_error(frame_error),
        .sync_lost(sync_lost)
    );

    // ========================================================================
    // Frame Generation
    // ========================================================================
    
    // Send complete frame (56 bits)
    task send_frame;
        input [7:0] cnt;
        input [31:0] data;
        input inject_crc_error;
        input inject_sync_error;
        
        reg [55:0] frame;
        reg [7:0] crc;
        integer i;
        begin
            // Construct frame
            frame[55:48] = inject_sync_error ? 8'h55 : 8'hAA;  // SYNC (corrupt if error)
            frame[47:40] = cnt;
            frame[39:8] = data;
            
            // Calculate CRC
            crc = calc_crc8(frame[55:8]);
            if (inject_crc_error) crc = ~crc;  // Corrupt CRC
            frame[7:0] = crc;
            
            $display("[SEND FRAME] SYNC=%02h CNT=%02h DATA=%08h CRC=%02h%s%s", 
                     frame[55:48], cnt, data, crc,
                     inject_sync_error ? " (SYNC ERROR)" : "",
                     inject_crc_error ? " (CRC ERROR)" : "");
            
            // Send frame bit by bit
            for (i = 55; i >= 0; i = i - 1) begin
                @(posedge clk_sys);
                bit_in = frame[i];
                bit_valid = 1;
                @(posedge clk_sys);
                bit_valid = 0;
                repeat(3) @(posedge clk_sys);  // Simulate 25 Mbps bit rate
            end
        end
    endtask
    
    // Send random noise (no sync pattern)
    task send_noise;
        input integer num_bits;
        integer i;
        begin
            for (i = 0; i < num_bits; i = i + 1) begin
                @(posedge clk_sys);
                bit_in = $random & 1'b1;
                bit_valid = 1;
                @(posedge clk_sys);
                bit_valid = 0;
                repeat(3) @(posedge clk_sys);
            end
        end
    endtask
    
    // Inject bit errors in specific position
    task send_frame_with_bit_errors;
        input [7:0] cnt;
        input [31:0] data;
        input integer error_positions [0:9];  // Positions to flip
        input integer num_errors;
        
        reg [55:0] frame;
        reg [7:0] crc;
        integer i, j;
        reg should_flip;
        begin
            // Construct frame
            frame[55:48] = 8'hAA;
            frame[47:40] = cnt;
            frame[39:8] = data;
            crc = calc_crc8(frame[55:8]);
            frame[7:0] = crc;
            
            $display("[SEND FRAME WITH ERRORS] %0d bit errors at positions:", num_errors);
            for (i = 0; i < num_errors; i = i + 1) begin
                $display("  Position %0d", error_positions[i]);
            end
            
            // Send frame with errors
            for (i = 55; i >= 0; i = i - 1) begin
                should_flip = 0;
                for (j = 0; j < num_errors; j = j + 1) begin
                    if (i == error_positions[j]) should_flip = 1;
                end
                
                @(posedge clk_sys);
                bit_in = should_flip ? ~frame[i] : frame[i];
                bit_valid = 1;
                @(posedge clk_sys);
                bit_valid = 0;
                repeat(3) @(posedge clk_sys);
            end
        end
    endtask

    // ========================================================================
    // Monitoring
    // ========================================================================
    
    integer frames_received;
    integer frames_with_errors;
    integer sync_lost_count;
    
    always @(posedge clk_sys) begin
        if (data_valid) begin
            frames_received = frames_received + 1;
            $display("[RX FRAME] #%0d: data=%08h time=%0t", frames_received, data_out, $time);
        end
        
        if (frame_error) begin
            frames_with_errors = frames_with_errors + 1;
            $display("[FRAME ERROR] Detected at time %0t", $time);
        end
    end
    
    always @(posedge sync_lost) begin
        sync_lost_count = sync_lost_count + 1;
        $display("[SYNC LOST] Lost synchronization at time %0t", $time);
    end

    // ========================================================================
    // Test Scenarios
    // ========================================================================
    
    task reset_test;
        begin
            `TEST_SECTION("Reset and Initialization")
            
            rst_n = 0;
            bit_in = 0;
            bit_valid = 0;
            
            #200;
            rst_n = 1;
            #100;
            
            `ASSERT(data_valid === 1'b0, "No valid data after reset")
            `ASSERT(frame_error === 1'b0, "No frame error after reset")
            `ASSERT(sync_lost === 1'b0, "Sync lost should be clear after reset")
            
            $display("Reset test completed");
        end
    endtask
    
    task sync_acquisition_test;
        integer start_time;
        begin
            `TEST_SECTION("SYNC Pattern Acquisition")
            
            start_time = $time;
            
            // Send noise first (should not sync)
            $display("Sending noise...");
            send_noise(100);
            
            `ASSERT(data_valid === 1'b0, "Should not output data on noise")
            
            // Send valid frame (should sync)
            $display("Sending valid frame...");
            send_frame(8'h00, 32'h12345678, 0, 0);
            
            // Wait for sync
            wait(data_valid);
            
            $display("Synchronized in %0d ns", $time - start_time);
            
            $display("Sync acquisition test completed");
        end
    endtask
    
    task normal_operation_test;
        integer i;
        reg [31:0] test_data;
        integer start_frames;
        begin
            `TEST_SECTION("Normal Operation - Sequential Frames")
            
            start_frames = frames_received;
            
            for (i = 0; i < 10; i = i + 1) begin
                test_data = 32'hA0000000 + i;
                send_frame(i[7:0], test_data, 0, 0);
                
                // Wait for frame
                wait(data_valid);
                @(posedge clk_sys);
                
                // Verify data
                `CHECK_EQ(data_out, test_data, $sformatf("Frame %0d Data", i))
                `ASSERT(frame_error === 1'b0, "No frame error should occur")
            end
            
            $display("Received %0d frames", frames_received - start_frames);
            $display("Normal operation test completed");
        end
    endtask
    
    task crc_error_detection_test;
        integer start_errors;
        begin
            `TEST_SECTION("CRC Error Detection")
            
            start_errors = frames_with_errors;
            
            // Send frame with CRC error
            send_frame(8'h10, 32'hDEADBEEF, 1, 0);  // inject_crc_error = 1
            
            // Wait for processing
            #5000;
            
            // Should detect error
            `ASSERT(frames_with_errors > start_errors, "Should detect CRC error")
            
            $display("CRC error detection test completed");
        end
    endtask
    
    task sync_corruption_test;
        begin
            `TEST_SECTION("SYNC Pattern Corruption")
            
            // Send frame with corrupted SYNC
            $display("Sending frame with corrupted SYNC pattern");
            send_frame(8'h02, 32'h11111111, 0, 1);  // inject_sync_error = 1
            
            // Should not produce valid output (or trigger resync)
            #10000;
            
            // Send valid frame to resync
            $display("Sending valid frame to resynchronize");
            send_frame(8'h03, 32'h22222222, 0, 0);
            
            wait(data_valid);
            $display("Resynchronized successfully");
            
            $display("SYNC corruption test completed");
        end
    endtask
    
    task bit_error_injection_test;
        integer error_pos [0:9];
        begin
            `TEST_SECTION("Bit Error Injection")
            
            // Inject single bit error in data field
            error_pos[0] = 20;  // Bit 20 of frame (in data field)
            send_frame_with_bit_errors(8'h05, 32'h55555555, error_pos, 1);
            
            #5000;
            
            // Should detect as CRC error
            $display("Single bit error test completed");
            
            // Inject multiple bit errors
            error_pos[0] = 30;
            error_pos[1] = 25;
            error_pos[2] = 15;
            send_frame_with_bit_errors(8'h06, 32'hAAAAAAAA, error_pos, 3);
            
            #5000;
            
            $display("Multiple bit error test completed");
        end
    endtask
    
    task counter_discontinuity_test;
        begin
            `TEST_SECTION("Frame Counter Discontinuity")
            
            // Send frames with sequential counters
            send_frame(8'h10, 32'h11111111, 0, 0);
            wait(data_valid);
            @(posedge clk_sys);
            
            send_frame(8'h11, 32'h22222222, 0, 0);
            wait(data_valid);
            @(posedge clk_sys);
            
            // Skip counter (discontinuity)
            $display("Injecting counter discontinuity (skip from 17 to 20)");
            send_frame(8'h14, 32'h33333333, 0, 0);
            wait(data_valid);
            @(posedge clk_sys);
            
            // System should still work (counter check may warn but not fail)
            $display("Counter discontinuity test completed");
        end
    endtask
    
    task resynchronization_test;
        integer i;
        begin
            `TEST_SECTION("Resynchronization After Errors")
            
            // Establish sync
            send_frame(8'h20, 32'h12121212, 0, 0);
            wait(data_valid);
            @(posedge clk_sys);
            
            // Send multiple bad frames
            $display("Sending 5 frames with CRC errors");
            for (i = 0; i < 5; i = i + 1) begin
                send_frame(8'h21 + i, 32'hBADBAD00 + i, 1, 0);  // Bad CRC
                #5000;
            end
            
            // Send noise
            $display("Sending noise");
            send_noise(50);
            
            // Send valid frame - should resync
            $display("Sending valid frame for resync");
            send_frame(8'h30, 32'hC0C0C0C0, 0, 0);
            
            wait(data_valid);
            $display("Resynchronized after errors");
            
            `CHECK_EQ(data_out, 32'hC0C0C0C0, "Resync Data")
            
            $display("Resynchronization test completed");
        end
    endtask
    
    task performance_test;
        integer start_time, end_time;
        integer num_frames;
        integer start_frames, start_errors;
        real frame_error_rate;
        begin
            `TEST_SECTION("Performance Measurement")
            
            num_frames = 50;
            start_time = $time;
            start_frames = frames_received;
            start_errors = frames_with_errors;
            
            // Send continuous frames
            for (integer i = 0; i < num_frames; i = i + 1) begin
                send_frame(i[7:0], 32'hFACE0000 + i, 0, 0);
            end
            
            // Wait for all frames
            while (frames_received < (start_frames + num_frames)) begin
                @(posedge clk_sys);
            end
            
            end_time = $time;
            
            frame_error_rate = ((frames_with_errors - start_errors) * 100.0) / num_frames;
            
            $display("[PERFORMANCE] Processed %0d frames in %0d ns", 
                     num_frames, end_time - start_time);
            $display("[PERFORMANCE] Frame error rate: %.2f%%", frame_error_rate);
            $display("[PERFORMANCE] Total frames received: %0d", frames_received);
            $display("[PERFORMANCE] Total frame errors: %0d", frames_with_errors);
            $display("[PERFORMANCE] Sync lost events: %0d", sync_lost_count);
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
        frames_received = 0;
        frames_with_errors = 0;
        sync_lost_count = 0;
        
        $display("========================================");
        $display("Frame Sync Testbench - Production Grade");
        $display("========================================");
        
        $dumpfile("tb_frame_sync.vcd");
        $dumpvars(0, tb_frame_sync);

        // Run test sequence
        reset_test();
        sync_acquisition_test();
        normal_operation_test();
        crc_error_detection_test();
        sync_corruption_test();
        bit_error_injection_test();
        counter_discontinuity_test();
        resynchronization_test();
        performance_test();
        
        // Final report
        #1000;
        `TEST_REPORT
        
        $finish;
    end

endmodule
