`timescale 1ns / 1ps

module tb_decoder;

    reg clk_link;
    reg clk_sys;
    reg rst_n;
    reg manch_in;
    wire [31:0] data_out;
    wire data_valid;
    wire cdr_locked;
    wire frame_error;
    wire sync_lost;

    // Clock generation
    initial begin
        clk_link = 0;
        forever #2.5 clk_link = ~clk_link; // 200MHz
    end

    initial begin
        clk_sys = 0;
        forever #5 clk_sys = ~clk_sys; // 100MHz
    end

    // DUT
    rhs2116_link_decoder u_dut (
        .clk_link(clk_link),
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .manch_in(manch_in),
        .data_out(data_out),
        .data_valid(data_valid),
        .cdr_locked(cdr_locked),
        .frame_error(frame_error),
        .sync_lost(sync_lost)
    );

    // Helper to calculate CRC
    function [7:0] calc_crc8;
        input [47:0] data;
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

    task send_manchester_frame(input [7:0] cnt, input [31:0] data);
        reg [55:0] frame;
        reg [7:0] crc;
        integer i;
        reg bit_val;
        begin
            frame[55:48] = 8'hAA;
            frame[47:40] = cnt;
            frame[39:8]  = data;
            crc = calc_crc8(frame[55:8]);
            frame[7:0] = crc;

            for (i = 55; i >= 0; i = i - 1) begin
                bit_val = frame[i];
                // Manchester encoding: 0->01, 1->10
                if (bit_val == 0) begin
                    manch_in = 0; #10;
                    manch_in = 1; #10;
                    manch_in = 0; #10;
                    manch_in = 1; #10; // 4 cycles per bit? No, encoder uses 4 cycles per bit.
                    // Encoder: 100MHz clk_sys. 4 cycles = 40ns.
                    // CDR: 200MHz clk_link. 4x oversampling.
                    // So bit period is 40ns.
                    // Manchester transition is in the middle (20ns).
                    // 0 -> 0 for 20ns, 1 for 20ns.
                end else begin
                    manch_in = 1; #10;
                    manch_in = 0; #10;
                    manch_in = 1; #10;
                    manch_in = 0; #10; // Wait, this is 40ns total?
                    // 10+10+10+10 = 40ns. Correct.
                    // But Manchester is 0->1 or 1->0.
                    // 0: Low then High.
                    // 1: High then Low.
                    // Each half is 20ns.
                end
            end
        end
    endtask
    
    // Correct Manchester encoding task
    task send_manchester_bit(input reg b);
        begin
            // Bit period 40ns.
            // 0: 0 for 20ns, 1 for 20ns.
            // 1: 1 for 20ns, 0 for 20ns.
            if (b == 0) begin
                manch_in = 0; #20;
                manch_in = 1; #20;
            end else begin
                manch_in = 1; #20;
                manch_in = 0; #20;
            end
        end
    endtask

    task send_frame_bits(input [7:0] cnt, input [31:0] data);
        reg [55:0] frame;
        reg [7:0] crc;
        integer i;
        begin
            frame[55:48] = 8'hAA;
            frame[47:40] = cnt;
            frame[39:8]  = data;
            crc = calc_crc8(frame[55:8]);
            frame[7:0] = crc;
            
            $display("Sending Frame: %h (CRC: %h)", frame, crc);

            for (i = 55; i >= 0; i = i - 1) begin
                send_manchester_bit(frame[i]);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_decoder.vcd");
        $dumpvars(0, tb_decoder);

        rst_n = 0;
        manch_in = 0;

        #100;
        rst_n = 1;

        // Training
        repeat(200) send_manchester_bit(1); // Just toggle?
        // CDR needs transitions.
        // Alternating 1s and 0s is best for locking.
        repeat(100) begin
            send_manchester_bit(1);
            send_manchester_bit(0);
        end

        wait(cdr_locked);
        $display("CDR Locked");

        // Send frames
        send_frame_bits(8'h00, 32'h12345678);
        send_frame_bits(8'h01, 32'h87654321);

        repeat(100) @(posedge clk_sys);
        $finish;
    end

endmodule
