`timescale 1ns / 1ps

module tb_cdr;

    reg clk_link;
    reg rst_n;
    reg manch_in;
    wire bit_out;
    wire bit_valid;
    wire locked;

    // Clock generation (200MHz)
    initial begin
        clk_link = 0;
        forever #2.5 clk_link = ~clk_link;
    end

    // DUT
    cdr_4x_oversampling u_dut (
        .clk_link(clk_link),
        .rst_n(rst_n),
        .manch_in(manch_in),
        .bit_out(bit_out),
        .bit_valid(bit_valid),
        .locked(locked)
    );

    // Generate Manchester stream
    task send_bit(input reg b);
        begin
            // 50Mbps = 20ns period
            // 0 -> 01, 1 -> 10
            if (b == 0) begin
                manch_in = 0;
                #10;
                manch_in = 1;
                #10;
            end else begin
                manch_in = 1;
                #10;
                manch_in = 0;
                #10;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_cdr.vcd");
        $dumpvars(0, tb_cdr);

        rst_n = 0;
        manch_in = 0;

        #100;
        rst_n = 1;
        
        // Send training sequence (alternating 1s and 0s)
        repeat(100) begin
            send_bit(1);
            send_bit(0);
        end

        wait(locked);
        $display("CDR Locked");

        // Send data
        send_bit(1);
        send_bit(1);
        send_bit(0);
        send_bit(1);

        #1000;
        $finish;
    end

endmodule
