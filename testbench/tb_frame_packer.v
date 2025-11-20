`timescale 1ns / 1ps

module tb_frame_packer;

    reg clk_spi;
    reg clk_sys;
    reg rst_n;
    reg [31:0] din;
    reg din_valid;
    wire tx_bit;
    wire tx_bit_valid;
    reg tx_bit_ready;
    wire [7:0] frame_count;

    // Clock generation
    initial begin
        clk_spi = 0;
        forever #7.8125 clk_spi = ~clk_spi;
    end

    initial begin
        clk_sys = 0;
        forever #5 clk_sys = ~clk_sys;
    end

    // DUT
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

    initial begin
        $dumpfile("tb_frame_packer.vcd");
        $dumpvars(0, tb_frame_packer);

        rst_n = 0;
        din = 0;
        din_valid = 0;
        tx_bit_ready = 0;

        #100;
        rst_n = 1;
        
        // Write to FIFO
        @(posedge clk_spi);
        din = 32'hAABBCCDD;
        din_valid = 1;
        @(posedge clk_spi);
        din_valid = 0;

        // Enable reading
        #100;
        tx_bit_ready = 1;

        // Wait for frame transmission
        repeat(56) @(posedge clk_sys);
        
        #1000;
        $finish;
    end

endmodule
