// Soft Clock Data Recovery (CDR) with 3x oversampling
// - Recovers clock and data from Manchester encoded stream
// - Uses phase tracking to handle drift and jitter
// - 240 MHz sampling for 80 Mbps data rate

module soft_cdr #(
    parameter OVERSAMPLE_RATE = 3,  // 3x oversampling
    parameter PHASE_ADJUST_THRESHOLD = 4  // Adjust phase after this many errors
)(
    input  wire clk_240m,
    input  wire rst_n,

    // Raw Manchester input
    input  wire manch_in,

    // Recovered data output
    output reg  data_out,
    output reg  data_valid,
    input  wire data_ready,

    // Status outputs
    output reg [1:0] phase_error_cnt,  // Count of phase errors
    output reg       phase_locked       // CDR is locked to incoming data
);

    // 3-sample history for edge detection
    reg [2:0] sample_hist;
    wire edge_now = (sample_hist[2] != sample_hist[1]);

    // Phase tracking
    reg [1:0] current_phase;     // 0-2 for 3x oversampling
    reg [1:0] sample_phase;      // Where to sample data
    reg [1:0] next_sample_phase; // Next sample position

    // Error tracking
    reg [2:0] consecutive_errors;
    reg last_was_error;

    // Bit recovery state
    reg bit_start_seen;
    reg last_level;
    reg [1:0] phase_counter;

    always @(posedge clk_240m or negedge rst_n) begin
        if (!rst_n) begin
            sample_hist        <= 3'b000;
            current_phase      <= 2'd0;
            sample_phase       <= 2'd1;  // Start sampling in middle
            next_sample_phase  <= 2'd1;
            data_out           <= 1'b0;
            data_valid         <= 1'b0;
            phase_error_cnt    <= 2'd0;
            phase_locked       <= 1'b0;
            consecutive_errors <= 3'd0;
            last_was_error     <= 1'b0;
            bit_start_seen     <= 1'b0;
            last_level         <= 1'b0;
            phase_counter      <= 2'd0;
        end else begin
            // Shift in new sample
            sample_hist <= {sample_hist[1:0], manch_in};

            // Default outputs
            data_valid <= 1'b0;
            last_was_error <= 1'b0;

            // Phase counter
            if (current_phase == 2'd2)
                current_phase <= 2'd0;
            else
                current_phase <= current_phase + 2'd1;

            // Edge detection and phase adjustment
            if (edge_now) begin
                // Check if edge is where we expect it
                if (current_phase != next_sample_phase) begin
                    // Phase error - edge not where expected
                    consecutive_errors <= consecutive_errors + 3'd1;
                    last_was_error <= 1'b1;

                    if (consecutive_errors >= PHASE_ADJUST_THRESHOLD) begin
                        // Too many errors - adjust sampling phase
                        if (current_phase > next_sample_phase) begin
                            // Late edge - sample earlier
                            sample_phase <= sample_phase - 2'd1;
                        end else begin
                            // Early edge - sample later
                            sample_phase <= sample_phase + 2'd1;
                        end
                        consecutive_errors <= 3'd0;
                        phase_error_cnt <= phase_error_cnt + 2'd1;
                    end
                end else begin
                    // Edge where expected - good
                    consecutive_errors <= 3'd0;
                    phase_locked <= 1'b1;
                end

                bit_start_seen <= 1'b1;
                last_level <= manch_in;
                next_sample_phase <= current_phase + 2'd2;  // Sample one bit period later
            end

            // Sample data at the right phase
            if (bit_start_seen && (current_phase == sample_phase)) begin
                if (data_ready) begin
                    // Manchester decode: compare first and second half
                    data_out <= last_level;
                    data_valid <= 1'b1;
                    bit_start_seen <= 1'b0;
                end
            end

            // Keep track of phase for next bit
            if (phase_counter == 2'd2)
                phase_counter <= 2'd0;
            else
                phase_counter <= phase_counter + 2'd1;
        end
    end

endmodule