`timescale 1ns / 1ps

module tb_spi_coax_system;

    // ========================================================================
    // Clock generation
    // ========================================================================
    reg clk_spi;    // 64MHz
    reg clk_sys;    // 100MHz
    reg clk_link;   // 200MHz
    reg rst_n;

    initial begin
        clk_spi = 0;
        forever #7.8125 clk_spi = ~clk_spi; // 64MHz (15.625ns period)
    end

    initial begin
        clk_sys = 0;
        forever #5 clk_sys = ~clk_sys;      // 100MHz (10ns period)
    end

    initial begin
        clk_link = 0;
        forever #2.5 clk_link = ~clk_link;  // 200MHz (5ns period)
    end

    // ========================================================================
    // Signals
    // ========================================================================
    reg enable;

    // SPI Interface (Encoder <-> Simulated Sensor)
    wire cs_n;
    wire sclk;
    wire mosi;
    reg  miso;

    // Coax Interface (Encoder <-> Decoder)
    wire ddr_p;
    wire ddr_n;
    wire manch_in;

    // Decoder Output
    wire [31:0] rx_data;
    wire        rx_valid;
    wire        cdr_locked;
    wire        frame_error;
    wire        sync_lost;

    // Status
    wire link_active;
    wire [7:0] tx_frame_cnt;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    top u_top (
        .clk_spi    (clk_spi),
        .clk_sys    (clk_sys),
        .clk_link   (clk_link),
        .rst_n      (rst_n),
        .enable     (enable),
        .cs_n       (cs_n),
        .sclk       (sclk),
        .mosi       (mosi),
        .miso       (miso),
        .rx_data    (rx_data),
        .rx_valid   (rx_valid),
        .link_active(link_active),
        .cdr_locked (cdr_locked),
        .frame_error(frame_error),
        .sync_lost  (sync_lost),
        .tx_frame_cnt(tx_frame_cnt)
    );

    // ========================================================================
    // Simulated RHS2116 Sensor Behavior
    // ========================================================================

    reg [31:0] sensor_data;
    reg [5:0]  bit_cnt;

    always @(negedge cs_n or negedge rst_n) begin
        if (!rst_n) begin
            sensor_data <= 32'h00000000;
            bit_cnt <= 6'd0;
        end else begin
            // Prepare data for the transfer
            // Format: {Channel[3:0], Counter[27:0]}
            sensor_data <= sensor_data + 1;
            bit_cnt <= 6'd0;
        end
    end

    always @(posedge sclk or negedge cs_n) begin
        if (!cs_n) begin
            miso <= sensor_data[31 - bit_cnt];
            bit_cnt <= bit_cnt + 1;
        end else begin
            miso <= 1'b0;
        end
    end

    // ========================================================================
    // Test Procedure
    // ========================================================================
    integer rx_count;

    initial begin
        // Initialize
        rst_n = 0;
        enable = 0;
        miso = 0;
        rx_count = 0;

        $display("Fast Simulation Start");
        $dumpfile("tb_spi_coax_system_fast.vcd");
        $dumpvars(1, tb_spi_coax_system);  // Only dump top level

        // Reset sequence
        #100;
        rst_n = 1;
        #100;

        // Enable Link
        $display("Enabling Link...");
        enable = 1;

        // Wait for lock or timeout
        fork
            begin
                // Wait for CDR lock
                wait(cdr_locked);
                $display("CDR Locked at time %t", $time);

                // Wait for 3 valid frames only
                while (rx_count < 3) begin
                    @(posedge clk_sys);
                    if (rx_valid) begin
                        $display("RX Data: %h (Time: %t)", rx_data, $time);
                        rx_count = rx_count + 1;
                    end
                end
                $display("Received 3 frames successfully - Test PASSED!");
                #1000;
                $finish;
            end

            begin
                // Timeout after 100us
                #100000;
                $display("Simulation Timeout - Test FAILED!");
                $finish;
            end
        join
    end

endmodule