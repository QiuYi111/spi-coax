`timescale 1ns / 1ps

module tb_frame_sync;

    reg clk_sys;
    reg rst_n;
    reg bit_in;
    reg bit_valid;
    wire [31:0] data_out;
    wire data_valid;
    wire frame_error;
    wire sync_lost;

    // Clock generation (100MHz)
    initial begin
        clk_sys = 0;
        forever #5 clk_sys = ~clk_sys;
    end

    // DUT
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

    task send_frame(input [7:0] cnt, input [31:0] data);
        reg [55:0] frame;
        reg [7:0] crc;
        integer i;
        begin
            // Construct frame: SYNC + CNT + DATA
            // CRC is calculated over SYNC + CNT + DATA
            frame[55:48] = 8'hAA; // SYNC
            frame[47:40] = cnt;
            frame[39:8]  = data;
            
            crc = calc_crc8(frame[55:8]);
            frame[7:0] = crc;

            $display("Sending Frame: %h", frame);

            for (i = 55; i >= 0; i = i - 1) begin
                @(posedge clk_sys);
                bit_in = frame[i];
                bit_valid = 1;
                @(posedge clk_sys); // Wait a cycle? No, bit_valid is pulse or level?
                // In frame_sync, it samples on posedge if bit_valid is high.
                // So we should hold bit_valid high for one cycle.
                // But here we are driving it.
                // Let's assume 1 bit per 4 clocks (since it comes from CDR/Manchester)
                // But frame_sync takes bit_in/bit_valid.
                // If we drive bit_valid high for 1 cycle, it consumes 1 bit.
                bit_valid = 0;
                repeat(3) @(posedge clk_sys); // Simulate 25Mbps rate (1 bit per 4 sys clocks)
            end
        end
    endtask

    initial begin
        $dumpfile("tb_frame_sync.vcd");
        $dumpvars(0, tb_frame_sync);

        rst_n = 0;
        bit_in = 0;
        bit_valid = 0;

        #100;
        rst_n = 1;
        
        // Send a few frames
        send_frame(8'h00, 32'h12345678);
        send_frame(8'h01, 32'h87654321);

        repeat(100) @(posedge clk_sys);
        $finish;
    end

endmodule
