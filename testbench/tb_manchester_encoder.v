`timescale 1ns / 1ps

`include "tb_common.vh"

module tb_manchester_encoder;

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
    reg tx_en;
    reg bit_in;
    reg bit_valid;
    wire bit_ready;
    wire ddr_p;
    wire ddr_n;

    // ========================================================================
    // Clock Generation (100MHz)
    // ========================================================================
    parameter real CLK_PERIOD = 10.0;  // 100MHz
    
    initial begin
        clk_sys = 0;
        forever #(CLK_PERIOD/2) clk_sys = ~clk_sys;
    end

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    manchester_encoder_100m u_dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .tx_en(tx_en),
        .bit_in(bit_in),
        .bit_valid(bit_valid),
        .bit_ready(bit_ready),
        .ddr_p(ddr_p),
        .ddr_n(ddr_n)
    );

    // ========================================================================
    // Manchester Encoding Monitor
    // ========================================================================
    reg [1:0] prev_ddr_p;
    reg [3:0] half_cycles [0:1000];
    integer half_cycle_idx;
    integer transition_count;
    integer error_count;
    
    // Capture DDR output transitions
    always @(posedge clk_sys) begin
        if (tx_en) begin
            prev_ddr_p <= {prev_ddr_p[0], ddr_p};
            
            // Detect transitions (should occur every 2 clocks for Manchester)
            if (prev_ddr_p[0] !== prev_ddr_p[1]) begin
                transition_count = transition_count + 1;
            end
        end
    end
    
    // Verify DDR outputs are complements
    always @(posedge clk_sys) begin
        if (tx_en) begin
            if (ddr_p !== ~ddr_n) begin
                $error("[DDR ERROR] DDR_P and DDR_N are not complements at time %0t: p=%b n=%b", 
                       $time, ddr_p, ddr_n);
                error_count = error_count + 1;
            end
        end
    end
    
    // ========================================================================
    // Helper Tasks
    // ========================================================================
    
    // Send a single bit and verify Manchester encoding
    task send_bit_and_verify;
        input bit_val;
        reg [1:0] expected_pattern;
        reg [3:0] captured [0:3];
        integer i;
        integer pattern_start;
        begin
            // Manchester encoding: 0 -> 01, 1 -> 10
            expected_pattern = bit_val ? 2'b10 : 2'b01;
            
            pattern_start = $time;
            
            // Send bit
            wait(bit_ready);
            @(posedge clk_sys);
            bit_in = bit_val;
            bit_valid = 1;
            @(posedge clk_sys);
            bit_valid = 0;
            
            // Capture 4 clock cycles of output (bit takes 4 clocks)
            for (i = 0; i < 4; i = i + 1) begin
                @(posedge clk_sys);
                captured[i] = {ddr_p, ddr_n};
            end
            
            // Verify pattern (first 2 clocks = first half, last 2 clocks = second half)
            $display("[MANCH ENCODE] Bit %b -> Pattern: %b%b%b%b (expected %b in first half, %b in second)", 
                     bit_val, 
                     captured[0][1], captured[1][1], captured[2][1], captured[3][1],
                     expected_pattern[1], expected_pattern[0]);
            
            // Check that we got the expected Manchester pattern
            // First 2 clocks should have first half-bit, last 2 should have second half-bit
            `ASSERT(captured[0][1] === expected_pattern[1] && 
                    captured[1][1] === expected_pattern[1],
                    $sformatf("First half of Manchester bit %b should be %b", bit_val, expected_pattern[1]))
            
            `ASSERT(captured[2][1] === expected_pattern[0] && 
                    captured[3][1] === expected_pattern[0],
                    $sformatf("Second half of Manchester bit %b should be %b", bit_val, expected_pattern[0]))
        end
    endtask
    
    // Send random bit stream
    task send_random_stream;
        input integer num_bits;
        integer i;
        reg random_bit;
        begin
            for (i = 0; i < num_bits; i = i + 1) begin
                random_bit = $random & 1'b1;
                send_bit_and_verify(random_bit);
            end
        end
    endtask

    // ========================================================================
    // Test Scenarios
    // ========================================================================
    
    task reset_test;
        begin
            `TEST_SECTION("Reset and Initialization")
            
            rst_n = 0;
            tx_en = 0;
            bit_in = 0;
            bit_valid = 0;
            
            #200;
            rst_n = 1;
            #100;
            
            `ASSERT(bit_ready === 1'b0, "Bit ready should be low when tx_en is low")
            
            tx_en = 1;
            #50;
            
            `ASSERT(bit_ready === 1'b1, "Bit ready should go high after tx_en")
            
            $display("Reset test completed");
        end
    endtask
    
    task basic_encoding_test;
        begin
            `TEST_SECTION("Basic Manchester Encoding")
            
            tx_en = 1;
            
            // Test bit 0 (should encode as 01)
            $display("Encoding bit 0...");
            send_bit_and_verify(1'b0);
            
            // Test bit 1 (should encode as 10)
            $display("Encoding bit 1...");
            send_bit_and_verify(1'b1);
            
            // Test another 0
            $display("Encoding bit 0 again...");
            send_bit_and_verify(1'b0);
            
            // Test another 1
            $display("Encoding bit 1 again...");
            send_bit_and_verify(1'b1);
            
            $display("Basic encoding test completed");
        end
    endtask
    
    task alternating_pattern_test;
        integer i;
        begin
            `TEST_SECTION("Alternating Bit Pattern")
            
            tx_en = 1;
            
            // Alternating 0101010101
            for (i = 0; i < 10; i = i + 1) begin
                send_bit_and_verify(i % 2);
            end
            
            $display("Alternating pattern test completed");
        end
    endtask
    
    task all_zeros_test;
        integer i;
        begin
            `TEST_SECTION("All Zeros Pattern")
            
            tx_en = 1;
            
            for (i = 0; i < 8; i = i + 1) begin
                send_bit_and_verify(1'b0);
            end
            
            $display("All zeros test completed");
        end
    endtask
    
    task all_ones_test;
        integer i;
        begin
            `TEST_SECTION("All Ones Pattern")
            
            tx_en = 1;
            
            for (i = 0; i < 8; i = i + 1) begin
                send_bit_and_verify(1'b1);
            end
            
            $display("All ones test completed");
        end
    endtask
    
    task random_pattern_test;
        begin
            `TEST_SECTION("Random Bit Stream")
            
            tx_en = 1;
            
            send_random_stream(20);
            
            $display("Random pattern test completed");
        end
    endtask
    
    task ready_valid_handshake_test;
        begin
            `TEST_SECTION("Ready/Valid Handshake Protocol")
            
            tx_en = 1;
            
            // Test 1: Valid without ready (should wait)
            bit_in = 1;
            bit_valid = 1;
            
            // Wait for ready
            wait(bit_ready);
            $display("Ready/valid handshake working: ready signaled");
            
            @(posedge clk_sys);
            bit_valid = 0;
            
            // Wait for next ready
            wait(bit_ready);
            
            $display("Ready/valid handshake test completed");
        end
    endtask
    
    task transition_count_test;
        integer start_transitions;
        integer expected_transitions;
        begin
            `TEST_SECTION("Transition Count Verification")
            
            tx_en = 1;
            start_transitions = transition_count;
            
            // Send 10 bits - each bit should produce at least 1 transition
            send_random_stream(10);
            
            expected_transitions = 10;  // At least 1 transition per bit
            
            $display("[TRANSITIONS] Counted %0d transitions for 10 bits", 
                     transition_count - start_transitions);
            
            `ASSERT((transition_count - start_transitions) >= expected_transitions,
                    "Should have at least 1 transition per Manchester bit")
            
            $display("Transition count test completed");
        end
    endtask
    
    task throughput_test;
        integer start_time, end_time;
        integer num_bits;
        real mbps;
        begin
            `TEST_SECTION("Encoding Throughput")
            
            tx_en = 1;
            num_bits = 50;
            
            start_time = $time;
   send_random_stream(num_bits);
            end_time = $time;
            
            mbps = (num_bits * 1000.0) / (end_time - start_time);
            
            $display("[PERFORMANCE] Encoded %0d bits in %0d ns", num_bits, end_time - start_time);
            $display("[PERFORMANCE] Throughput: %.2f Mbps", mbps);
            $display("[PERFORMANCE] Expected: 25 Mbps (100MHz / 4 clocks per bit)");
            
            // Should be around 25 Mbps (100MHz / 4)
            `CHECK_RANGE(mbps, 20, 30, "Manchester Encoding Throughput (Mbps)")
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
        transition_count = 0;
        error_count = 0;
        half_cycle_idx = 0;
        
        $display("========================================");
        $display("Manchester Encoder Testbench - Production Grade");
        $display("========================================");
        
        $dumpfile("tb_manchester_encoder.vcd");
        $dumpvars(0, tb_manchester_encoder);

        // Run test sequence
        reset_test();
        basic_encoding_test();
        alternating_pattern_test();
        all_zeros_test();
        all_ones_test();
        random_pattern_test();
        ready_valid_handshake_test();
        transition_count_test();
        throughput_test();
        
        // Check for DDR errors
        `ASSERT(error_count === 0, "No DDR complement errors should occur")
        
        // Final report
        #1000;
        `TEST_REPORT
        
        $finish;
    end

endmodule
