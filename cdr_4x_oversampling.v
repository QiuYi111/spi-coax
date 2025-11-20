// ============================================================================
// Clock Data Recovery (CDR) - 4x Oversampling
// ============================================================================
// Clock: 200MHz clk_link
// Manchester rate: ~50 Mbps (49.9968 Mbps exact)
// Oversample ratio: 4x (ideal for integer sampling)
//
// Architecture:
//   - 4-stage shift register for edge detection
//   - 4 selectable sampling phases (0-3)
//   - Phase quality tracking for drift compensation
//   - 3-state lock detection (UNLOCKED/LOCKING/LOCKED)
//
// Locking: 32 consecutive valid transitions required
// Unlock:  200 cycles without transition or sync loss
// Tracking range: ±150 ppm (covers 64 ppm initial offset)
// ============================================================================

module cdr_4x_oversampling (
    input  wire clk_link,     // 200MHz
    input  wire rst_n,
    input  wire manch_in,     // Manchester encoded input
    output wire bit_out,      // Recovered bit
    output wire bit_valid,    // Bit valid pulse (1 cycle per bit)
    output wire locked        // CDR lock status
);

    // ========================================================================
    // 4-stage shift register for edge detection
    // ========================================================================
    reg [3:0] sample_shift;

    always @(posedge clk_link) begin
        sample_shift <= {sample_shift[2:0], manch_in};
    end

    // Edge detection: check between samples 1 and 0 (200MHz domain)
    wire transition = (sample_shift[1] != sample_shift[0]);

    // ========================================================================
    // Phase quality tracking
    // ========================================================================
    // Measures if current phase samples in data eye center
    // Positive: sampling in stable region (00 or 11)
    // Negative: sampling near transition (01 or 10)
    reg signed [5:0] phase_quality;

    always @(posedge clk_link) begin
        if (!rst_n) begin
            phase_quality <= 6'sd0;
        end else if (bit_valid) begin
            // At bit center: check if samples 2:1 are stable
            if ((sample_shift[2:1] == 2'b00) || (sample_shift[2:1] == 2'b11))
                phase_quality <= phase_quality + 6'sd1;    // Good: in eye center
            else
                phase_quality <= phase_quality - 6'sd3;    // Bad: near edge, stronger penalty
        end
    end

    // ========================================================================
    // Phase selection (4 positions: 0-3)
    // ========================================================================
    // 0: Early (before transition)
    // 1: Slightly early (good for locked state)
    // 2: Center (optimal sampling point)
    // 3: Late (after transition)
    reg [1:0] phase_sel;

    always @(posedge clk_link) begin
        if (!rst_n) begin
            phase_sel <= 2'b10;  // Default: center position - align with Manchester first half
        end else if (phase_quality <= -16) begin
            // Quality too low: move to later phase
            phase_sel <= phase_sel + 1'b1;
        end else if (phase_quality >= 8) begin
            // Good quality but can optimize: move earlier
            phase_sel <= phase_sel - 1'b1;
        end
    end

    // ========================================================================
    // Bit period counter (4 cycles per bit)
    // ========================================================================
    reg [1:0] sample_cnt;


    // Logic moved to main state machine for synchronization

    // Bit output and valid signal (sample at bit center: sample_cnt == 1)
    wire at_bit_center = (sample_cnt == 2'b01);
    assign bit_out   = sample_shift[phase_sel];
    assign bit_valid = locked && at_bit_center;

    // ========================================================================
    // Lock detection state machine
    // ========================================================================
    localparam STATE_UNLOCKED = 2'b00;
    localparam STATE_LOCKING  = 2'b01;
    localparam STATE_LOCKED   = 2'b10;

    reg [1:0] lock_state;
    reg [7:0] lock_timer;  // Counts transitions in LOCKING, inactivity in LOCKED

    always @(posedge clk_link) begin
        if (!rst_n) begin
            lock_state <= STATE_UNLOCKED;
            lock_timer <= 8'h00;
            sample_cnt <= 2'b00;
        end else begin
            sample_cnt <= sample_cnt + 1'b1; // Default increment

            case (lock_state)
                // UNLOCKED: Search for valid Manchester transitions
                STATE_UNLOCKED: begin
                    if (transition) begin
                        lock_state <= STATE_LOCKING;
                        lock_timer <= 8'h01;
                        // Align sample counter to transition
                        // We want sample_cnt=1 (at_bit_center) at the NEXT transition (8 cycles later)
                        // So set current sample_cnt to 2
                        sample_cnt <= 2'b10;
                    end
                end

                // LOCKING: Count consecutive valid bits
                STATE_LOCKING: begin
                    if (at_bit_center && transition) begin
                        // Valid Manchester transition at expected position
                        lock_timer <= lock_timer + 1'b1;
                        if (lock_timer >= 32) begin
                            // 32 consecutive valid bits achieved
                            lock_state <= STATE_LOCKED;
                            lock_timer <= 8'h00;
                        end
                    end else if (at_bit_center && !transition) begin
                        // Missing transition - Manchester violation
                        lock_state <= STATE_UNLOCKED;
                        lock_timer <= 8'h00;
                    end
                end

                // LOCKED: Monitor for loss of signal
                STATE_LOCKED: begin
                    // Count cycles without transition
                    if (!transition && (lock_timer < 200))
                        lock_timer <= lock_timer + 1'b1;
                    else if (transition)
                        lock_timer <= 8'h00;

                    // Unlock if too long without transition (signal lost)
                    if (lock_timer >= 200)
                        lock_state <= STATE_UNLOCKED;
                end

                default: begin
                    lock_state <= STATE_UNLOCKED;
                    lock_timer <= 8'h00;
                end
            endcase
        end
    end

    assign locked = (lock_state == STATE_LOCKED);

endmodule
