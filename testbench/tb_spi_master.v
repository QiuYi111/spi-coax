`timescale 1ns / 1ps

module tb_spi_master;

    reg clk_spi;
    reg rst_n;
    reg enable;
    reg miso;
    wire cs_n;
    wire sclk;
    wire mosi;
    wire [31:0] data_out;
    wire data_valid;

    // Clock generation (64MHz)
    initial begin
        clk_spi = 0;
        forever #7.8125 clk_spi = ~clk_spi;
    end

    // DUT
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

    // Simulated Slave
    reg [31:0] slave_data = 32'hDEADBEEF;
    reg [5:0] bit_cnt;
    
    always @(negedge cs_n) begin
        bit_cnt <= 0;
    end

    always @(posedge sclk) begin
        if (!cs_n) begin
            miso <= slave_data[31 - bit_cnt];
            bit_cnt <= bit_cnt + 1;
        end
    end

    initial begin
        $dumpfile("tb_spi_master.vcd");
        $dumpvars(0, tb_spi_master);

        rst_n = 0;
        enable = 0;
        miso = 0;

        #100;
        rst_n = 1;
        #100;
        enable = 1;

        // Wait for a few frames
        repeat(3) @(posedge data_valid);
        
        $display("Received data: %h", data_out);
        if (data_out == 32'hDEADBEEF)
            $display("SPI Test PASSED");
        else
            $display("SPI Test FAILED");

        #1000;
        $finish;
    end

endmodule
