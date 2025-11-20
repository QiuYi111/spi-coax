`timescale 1ns / 1ps

module tb_encoder;

    reg clk_spi;
    reg clk_sys;
    reg rst_n;
    reg enable;
    reg miso;
    wire cs_n;
    wire sclk;
    wire mosi;
    wire ddr_p;
    wire ddr_n;
    wire link_active;
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
    rhs2116_link_encoder u_dut (
        .clk_spi(clk_spi),
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .enable(enable),
        .cs_n(cs_n),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .ddr_p(ddr_p),
        .ddr_n(ddr_n),
        .link_active(link_active),
        .frame_count(frame_count)
    );

    // Simulated Sensor
    reg [31:0] sensor_data = 32'h12345678;
    reg [5:0] bit_cnt;

    always @(posedge sclk or negedge cs_n) begin
        if (!cs_n) begin
            miso <= sensor_data[31 - bit_cnt];
            bit_cnt <= bit_cnt + 1;
        end else begin
            miso <= 0;
            bit_cnt <= 0;
        end
    end

    initial begin
        $dumpfile("tb_encoder.vcd");
        $dumpvars(0, tb_encoder);

        rst_n = 0;
        enable = 0;
        miso = 0;

        #100;
        rst_n = 1;
        #100;
        enable = 1;

        // Wait for some frames to be sent
        repeat(10000) @(posedge clk_sys);
        
        $finish;
    end

endmodule
