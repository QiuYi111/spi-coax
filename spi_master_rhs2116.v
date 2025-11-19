// ============================================================================
// SPI Master for RHS2116 - 64MHz Input, 16MHz SCLK
// ============================================================================
// Clock: 64MHz dedicated PLL output (clk_spi)
// SCLK: 16MHz (64MHz / 4)
// Data rate: 32-bit frames @ 16MHz = 446.4k frames/sec (16 channels)
//
// Features:
//   - Automatic channel polling (0-15) with CONVERT commands
//   - First 2 frames discarded (RHS2116 latency compensation)
//   - Mode 1: CPOL=0, CPHA=1 (sample on falling edge)
//
// Interface:
//   - Control: enable (clk_sys domain), synced to clk_spi
//   - SPI: cs_n, sclk, mosi, miso
//   - Output: data_out[31:0], data_valid (clk_sys domain, synced)
// ============================================================================

module spi_master_rhs2116 (
    input  wire        clk_spi,    // 64MHz (dedicated PLL output)
    input  wire        rst_n,
    input  wire        enable,     // From clk_sys domain (will be synced)

    // SPI interface
    output reg         cs_n,
    output wire        sclk,       // 16MHz = 64MHz / 4
    output reg         mosi,
    input  wire        miso,

    // Output data (clk_spi domain)
    output reg [31:0]  data_out,
    output reg         data_valid
);

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam CMD_CONVERT     = 2'b00;
    localparam CMD_PADDING     = 16'h0000;
    localparam GAP_CYCLES      = 6'h0F;  // 16 cycles
    localparam DISCARD_FRAMES  = 8'd2;
    localparam SCLK_DIV_MAX    = 2'b11;  // Divide by 4
    localparam SCLK_RISING_EDGE = 2'b01;
    localparam SCLK_FALLING_EDGE = 2'b11;

    // ========================================================================
    // Input synchronization (enable from clk_sys -> clk_spi)
    // ========================================================================
    reg enable_spi1, enable_spi2;

    always @(posedge clk_spi) begin
        enable_spi1 <= enable;
        enable_spi2 <= enable_spi1;
    end

    wire enable_sync = enable_spi2;  // Synchronized enable signal

    // ========================================================================
    // SCLK generation: 64MHz / 4 = 16MHz
    // ========================================================================
    reg [1:0] sclk_cnt;

    always @(posedge clk_spi or negedge rst_n) begin
        if (!rst_n)
            sclk_cnt <= 2'b00;
        else
            sclk_cnt <= sclk_cnt + 1'b1;
    end

    assign sclk = sclk_cnt[1];  // 16MHz output (toggle every 4 cycles)

    // SCLK edge detection
    wire sclk_falling = (sclk_cnt == SCLK_FALLING_EDGE);  // Falling edge (sample MISO)
    wire sclk_rising  = (sclk_cnt == SCLK_RISING_EDGE);  // Rising edge (update MOSI)

    // ========================================================================
    // RHS2116 CONVERT command generation
    // ========================================================================
    wire [31:0] convert_cmd = {
        CMD_CONVERT,    // CONVERT command
        1'b0,     // U
        1'b0,     // M
        1'b1,     // D (DC-coupled, 10-bit mode)
        1'b0,     // H
        4'b0000,
        curr_chan,  // Channel number (6-bit)
        CMD_PADDING
    };

    // ========================================================================
    // State machine
    // ========================================================================
    localparam IDLE  = 3'b000;
    localparam LOAD  = 3'b001;
    localparam XFER  = 3'b010;
    localparam GAP   = 3'b011;
    localparam DONE  = 3'b100;

    reg [2:0] state;
    reg [5:0] bit_cnt;      // 0-31
    reg [5:0] gap_cnt;      // CS gap counter (16 cycles)
    reg [3:0] curr_chan;    // Current channel (0-15)
    reg [7:0] frame_cnt;    // Frame counter (discard first 2)

    reg [31:0] shifter_tx;  // Transmit shift register
    reg [31:0] shifter_rx;  // Receive shift register

    // Output data (clk_spi domain)
    // Note: Downstream modules must handle CDC (e.g., via Async FIFO)
    reg [31:0] data_out_reg;
    reg        data_valid_reg;

    // ========================================================================
    // Main state machine
    // ========================================================================
    always @(posedge clk_spi or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            cs_n          <= 1'b1;
            mosi          <= 1'b0;
            bit_cnt       <= 6'b0;
            gap_cnt       <= 6'b0;
            curr_chan     <= 4'b0;
            frame_cnt     <= 8'b0;
            shifter_tx    <= 32'b0;
            shifter_rx    <= 32'b0;
            data_out_reg   <= 32'b0;
            data_valid_reg <= 1'b0;
            data_out       <= 32'b0;
            data_valid     <= 1'b0;
        end else begin
            data_valid_reg <= 1'b0;  // Default

            case (state)
                // IDLE: Wait for enable
                IDLE: begin
                    cs_n <= 1'b1;
                    mosi <= 1'b0;

                    if (enable_sync) begin
                        state <= LOAD;
                    end
                end

                // LOAD: Setup new CONVERT command
                LOAD: begin
                    cs_n       <= 1'b0;           // Assert CS
                    shifter_tx <= convert_cmd;
                    mosi       <= convert_cmd[31]; // First bit
                    bit_cnt    <= 6'b0;
                    state      <= XFER;
                end

                // XFER: Transfer 32 bits
                XFER: begin
                    cs_n <= 1'b0;

                    // On falling edge: sample MISO
                    if (sclk_falling) begin
                        shifter_rx <= {shifter_rx[30:0], miso};

                        if (bit_cnt == 6'd31) begin
                            // Transfer complete
                            data_out_reg <= {shifter_rx[30:0], miso};
                            frame_cnt <= frame_cnt + 1'b1;

                            // Discard first 2 frames (RHS2116 latency)
                            if (frame_cnt >= DISCARD_FRAMES)
                                data_valid_reg <= 1'b1;

                            state <= GAP;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end

                    // On rising edge: update MOSI
                    if (sclk_rising && (bit_cnt < 6'd31)) begin
                        mosi <= shifter_tx[31];
                        shifter_tx <= {shifter_tx[30:0], 1'b0};
                    end
                end

                // GAP: CS high time between frames
                GAP: begin
                    cs_n <= 1'b1;
                    mosi <= 1'b0;

                    if (gap_cnt >= GAP_CYCLES) begin  // 16 cycles gap
                        gap_cnt <= 6'b0;
                        curr_chan <= curr_chan + 1'b1;  // Next channel
                        state <= enable_sync ? LOAD : IDLE;
                    end else begin
                        gap_cnt <= gap_cnt + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase

            // Output assignment
            data_out   <= data_out_reg;
            data_valid <= data_valid_reg;
        end
    end

endmodule
