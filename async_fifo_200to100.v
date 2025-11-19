// ============================================================================
// Asynchronous FIFO - 200MHz to 100MHz Clock Domain Crossing
// ============================================================================
// Clock domains:
//   - Write: clk_wr (200MHz) - CDR output data
//   - Read:  clk_rd (100MHz) - System processing
//
// Parameters:
//   - DATA_WIDTH: 32 bits (RHS2116 data width)
//   - ADDR_WIDTH: 4 (16-depth, enough for CDR buffering)
//
// Safety features:
//   - Gray code pointer synchronization
//   - Double flip-flop sync chain with ASYNC_REG protection
//   - Full/Empty flags with safe Gray code comparison
// ============================================================================

module async_fifo_200to100 #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 4
)(
    // Write port - 200MHz domain (CDR output)
    input  wire                     clk_wr,
    input  wire                     rst_wr_n,
    input  wire [DATA_WIDTH-1:0]    din,
    input  wire                     wr_en,
    output wire                     full,
    output wire                     almost_full,

    // Read port - 100MHz domain (System logic)
    input  wire                     clk_rd,
    input  wire                     rst_rd_n,
    output wire [DATA_WIDTH-1:0]    dout,
    input  wire                     rd_en,
    output wire                     empty,
    output wire                     valid
);

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam PTR_WIDTH = ADDR_WIDTH + 1;      // Extra bit for full/empty
    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);  // 16 entries
    localparam ALMOST_FULL_THRESHOLD = FIFO_DEPTH - 2;  // 14/16

    // ========================================================================
    // Memory array
    // ========================================================================
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // ========================================================================
    // Write domain - Binary and Gray pointers
    // ========================================================================
    reg [PTR_WIDTH-1:0] wr_ptr_bin;
    reg [PTR_WIDTH-1:0] wr_ptr_gray;

    wire [PTR_WIDTH-1:0] wr_ptr_bin_next = wr_ptr_bin + ((wr_en && !full) ? 1'b1 : 1'b0);
    wire [PTR_WIDTH-1:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    always @(posedge clk_wr or negedge rst_wr_n) begin
        if (!rst_wr_n) begin
            wr_ptr_bin  <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;

            // Write to memory
            if (wr_en && !full) begin
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
            end
        end
    end

    // ========================================================================
    // Read domain - Binary and Gray pointers
    // ========================================================================
    reg [PTR_WIDTH-1:0] rd_ptr_bin;
    reg [PTR_WIDTH-1:0] rd_ptr_gray;
    reg [DATA_WIDTH-1:0] rd_data_reg;
    reg rd_valid_reg;

    wire [PTR_WIDTH-1:0] rd_ptr_bin_next = rd_ptr_bin + ((rd_en && !empty) ? 1'b1 : 1'b0);
    wire [PTR_WIDTH-1:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    always @(posedge clk_rd or negedge rst_rd_n) begin
        if (!rst_rd_n) begin
            rd_ptr_bin   <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray  <= {PTR_WIDTH{1'b0}};
            rd_data_reg  <= {DATA_WIDTH{1'b0}};
            rd_valid_reg <= 1'b0;
        end else begin
            rd_ptr_bin   <= rd_ptr_bin_next;
            rd_ptr_gray  <= rd_ptr_gray_next;

            // Read from memory
            if (rd_en && !empty) begin
                rd_data_reg <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
                rd_valid_reg <= 1'b1;
            end else begin
                rd_valid_reg <= 1'b0;
            end
        end
    end

    // ========================================================================
    // CDC: Gray pointer synchronization with double flip-flop chain
    // ========================================================================

    // Read pointer Gray -> Write domain sync
    reg [PTR_WIDTH-1:0] rd_gray_wr1 /* synthesis altera_attribute = "-name ASYNC_REG ON" */;
    reg [PTR_WIDTH-1:0] rd_gray_wr2 /* synthesis altera_attribute = "-name ASYNC_REG ON" */;

    always @(posedge clk_wr or negedge rst_wr_n) begin
        if (!rst_wr_n) begin
            rd_gray_wr1 <= {PTR_WIDTH{1'b0}};
            rd_gray_wr2 <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_gray_wr1 <= rd_ptr_gray;
            rd_gray_wr2 <= rd_gray_wr1;
        end
    end

    // Write pointer Gray -> Read domain sync
    reg [PTR_WIDTH-1:0] wr_gray_rd1 /* synthesis altera_attribute = "-name ASYNC_REG ON" */;
    reg [PTR_WIDTH-1:0] wr_gray_rd2 /* synthesis altera_attribute = "-name ASYNC_REG ON" */;

    always @(posedge clk_rd or negedge rst_rd_n) begin
        if (!rst_rd_n) begin
            wr_gray_rd1 <= {PTR_WIDTH{1'b0}};
            wr_gray_rd2 <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_gray_rd1 <= wr_ptr_gray;
            wr_gray_rd2 <= wr_gray_rd1;
        end
    end

    // ========================================================================
    // Full/Empty flag generation
    // ========================================================================

    // Empty: read pointer == synchronized write pointer
    assign empty = (rd_ptr_gray == wr_gray_rd2);

    // Full: write pointer + 1 == synchronized read pointer (top bits differ)
    assign full = (wr_ptr_gray_next == {~wr_gray_rd2[PTR_WIDTH-1:PTR_WIDTH-2],
                                         wr_gray_rd2[PTR_WIDTH-3:0]});

    // Almost full: threshold-based for flow control
    wire [PTR_WIDTH-1:0] used_words_wr = wr_ptr_bin - rd_gray_wr2;
    assign almost_full = (used_words_wr >= ALMOST_FULL_THRESHOLD[PTR_WIDTH-1:0]);

    // ========================================================================
    // Outputs
    // ========================================================================
    assign dout  = rd_data_reg;
    assign valid = rd_valid_reg;

endmodule
