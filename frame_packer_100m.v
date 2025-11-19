// ============================================================================
// Frame Packer - 100MHz with Async FIFO
// ============================================================================
// Packs 32-bit data into 56-bit frames: {SYNC(8), CNT(8), DATA(32), CRC(8)}
// Handles clk_spi (64MHz) -> clk_sys (100MHz) CDC internally
//
// Data flow:
//   din (clk_spi) → Async FIFO → Frame assembly → Bit serialization
//
// Frame rate: 446.4k frames/sec (matches SPI rate)
// Bit rate: 25 Mbps (data) → 50 Mbps Manchester line rate
// ============================================================================

module frame_packer_100m (
    // Clocks
    input wire clk_spi,      // 64MHz SPI clock (write side)
    input wire clk_sys,      // 100MHz system clock (read side)
    input wire rst_n,

    // Input from SPI Master (clk_spi domain)
    input  wire [31:0] din,
    input  wire        din_valid,

    // Serial output (clk_sys domain)
    output reg         tx_bit,
    output reg         tx_bit_valid,
    input  wire        tx_bit_ready,

    // Status
    output wire [7:0]  frame_count
);

    // ========================================================================
    // Frame format: {SYNC(8), CNT(8), DATA(32), CRC(8)}
    // ========================================================================
    localparam SYNC_BYTE = 8'hAA;
    localparam CRC_POLY  = 8'h07;  // x^8 + x^2 + x + 1

    // ========================================================================
    // Async FIFO (SPI domain -> System domain)
    // ========================================================================
    wire [31:0] fifo_dout;
    wire        fifo_empty;
    wire        fifo_full;
    wire        fifo_rd_en;

    async_fifo_generic #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(4)  // 16 entries
    ) u_async_fifo (
        .clk_wr      (clk_spi),
        .rst_wr_n    (rst_n),
        .din         (din),
        .wr_en       (din_valid),
        .full        (fifo_full),
        .almost_full (),  // Not used

        .clk_rd      (clk_sys),
        .rst_rd_n    (rst_n),
        .dout        (fifo_dout),
        .rd_en       (fifo_rd_en),
        .empty       (fifo_empty),
        .valid       ()
    );

    // ========================================================================
    // Frame assembly and serialization
    // ========================================================================
    reg [7:0]   frame_cnt;      // 8-bit frame counter
    reg [55:0]  shift_reg;      // Frame shift register
    reg [5:0]   bit_cnt;        // 0-55 (56 bits)
    reg         sending;        // Frame transmission in progress

    wire [31:0] convert_data = fifo_dout;
    wire [7:0]  convert_crc  = calc_crc8(convert_data, frame_cnt);

    function [7:0] calc_crc8;
        input [31:0] data;
        input [7:0]  cnt;
        integer i;
        reg [7:0] crc;
        reg [39:0] msg;
        begin
            msg = {cnt, data};
            crc = 8'h00;
            for (i = 39; i >= 0; i = i - 1) begin
                if ((crc[7] ^ msg[i]) == 1'b1)
                    crc = {crc[6:0], 1'b0} ^ 8'h07;
                else
                    crc = {crc[6:0], 1'b0};
            end
            calc_crc8 = crc;
        end
    endfunction

    // ========================================================================
    // State machine: IDLE -> LOAD -> SEND
    // ========================================================================
    localparam IDLE = 2'b00;
    localparam LOAD = 2'b01;
    localparam SEND = 2'b10;

    reg [1:0] state;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            frame_cnt   <= 8'b0;
            shift_reg   <= 56'b0;
            bit_cnt     <= 6'b0;
            sending     <= 1'b0;
            tx_bit      <= 1'b0;
            tx_bit_valid <= 1'b0;
            fifo_rd_en  <= 1'b0;
        end else begin
            tx_bit_valid <= 1'b0;  // Default
            fifo_rd_en   <= 1'b0;

            case (state)
                IDLE: begin
                    if (!fifo_empty && tx_bit_ready) begin
                        state      <= LOAD;
                        fifo_rd_en <= 1'b1;
                    end
                end

                LOAD: begin
                    // Assemble frame: {SYNC, CNT, DATA, CRC}
                    shift_reg <= {
                        SYNC_BYTE,
                        frame_cnt,
                        convert_data,
                        convert_crc
                    };

                    frame_cnt <= frame_cnt + 8'b1;
                    bit_cnt   <= 6'b0;
                    sending   <= 1'b1;
                    state     <= SEND;
                end

                SEND: begin
                    if (tx_bit_ready) begin
                        tx_bit       <= shift_reg[55];        // MSB first
                        tx_bit_valid <= 1'b1;
                        shift_reg    <= {shift_reg[54:0], 1'b0}; // Shift left
                        bit_cnt      <= bit_cnt + 1'b1;

                        if (bit_cnt == 6'b110111) begin  // All 56 bits sent
                            sending <= 1'b0;
                            state   <= IDLE;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // ========================================================================
    // Status outputs
    // ========================================================================
    assign frame_count = frame_cnt;

endmodule
