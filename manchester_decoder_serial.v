// Manchester decoder with serial bit output
// - clk_240m: 240 MHz clock (3x oversampling)
// - Effective bit rate: 80 Mbps
// - Recovers original bit stream from Manchester encoded signal

module manchester_decoder_serial (
    input  wire clk_240m,
    input  wire rst_n,

    // Manchester encoded input
    input  wire manch_in,

    // Decoded bit output
    output reg  bit_out,
    output reg  bit_valid,
    input  wire bit_ready
);

    // 3x oversampling - need to detect transitions and sample in middle
    reg [2:0] sample_history;  // Last 3 samples
    reg [1:0] phase_cnt;       // 0-2 counter for 3x oversampling

    // Edge detection
    wire edge_detected = (sample_history[2:1] != 2'b00) &&
                        (sample_history[2:1] != 2'b11);

    // State for bit recovery
    reg waiting_for_edge;
    reg [1:0] bit_phase;       // Which phase to sample the bit
    reg       last_manch_level;

    always @(posedge clk_240m or negedge rst_n) begin
        if (!rst_n) begin
            sample_history    <= 3'b000;
            phase_cnt         <= 2'd0;
            bit_out           <= 1'b0;
            bit_valid         <= 1'b0;
            waiting_for_edge  <= 1'b1;
            bit_phase         <= 2'd0;
            last_manch_level  <= 1'b0;
        end else begin
            // Shift in new sample
            sample_history <= {sample_history[1:0], manch_in};

            // Default outputs
            bit_valid <= 1'b0;

            // Phase counter
            if (phase_cnt == 2'd2)
                phase_cnt <= 2'd0;
            else
                phase_cnt <= phase_cnt + 2'd1;

            // Bit recovery logic
            if (edge_detected && waiting_for_edge) begin
                // Found edge - center our sampling
                bit_phase <= phase_cnt + 2'd1;  // Sample one phase after edge
                waiting_for_edge <= 1'b0;
                last_manch_level <= manch_in;
            end
            else if (phase_cnt == bit_phase && !waiting_for_edge) begin
                // Time to sample the bit
                if (bit_ready) begin
                    // Manchester decoding: 1->0 is logic 1, 0->1 is logic 0
                    bit_out <= last_manch_level;
                    bit_valid <= 1'b1;
                    waiting_for_edge <= 1'b1;  // Look for next edge
                end
            end
        end
    end

endmodule