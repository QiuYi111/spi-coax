`timescale 1ns / 1ps

module tb_manchester_encoder;

    reg clk_sys;
    reg rst_n;
    reg tx_en;
    reg bit_in;
    reg bit_valid;
    wire bit_ready;
    wire ddr_p;
    wire ddr_n;

    // Clock generation (100MHz)
    initial begin
        clk_sys = 0;
        forever #5 clk_sys = ~clk_sys;
    end

    // DUT
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

    initial begin
        $dumpfile("tb_manchester_encoder.vcd");
        $dumpvars(0, tb_manchester_encoder);

        // Initialize
        rst_n = 0;
        tx_en = 0;
        bit_in = 0;
        bit_valid = 0;

        #100;
        rst_n = 1;
        #20;
        tx_en = 1;

        // Send bit 0
        wait(bit_ready);
        @(posedge clk_sys);
        bit_in = 0;
        bit_valid = 1;
        @(posedge clk_sys);
        bit_valid = 0;

        // Send bit 1
        wait(bit_ready);
        @(posedge clk_sys);
        bit_in = 1;
        bit_valid = 1;
        @(posedge clk_sys);
        bit_valid = 0;
        
        // Send bit 0 again
        wait(bit_ready);
        @(posedge clk_sys);
        bit_in = 0;
        bit_valid = 1;
        @(posedge clk_sys);
        bit_valid = 0;

        #200;
        $finish;
    end

endmodule
