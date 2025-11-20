//==============================================================================
// Error Injection Framework for SPI-Coax System Testing
// Provides comprehensive error injection capabilities
//==============================================================================

`timescale 1ns/1ps

// Error injection types
typedef enum {
    ERROR_NONE = 0,
    ERROR_BIT_FLIP = 1,
    ERROR_FRAME_CORRUPT = 2,
    ERROR_CRC_MISMATCH = 3,
    ERROR_SYNC_LOST = 4,
    ERROR_CLOCK_GLITCH = 5,
    ERROR_BURST_ERROR = 6
} error_type_t;

// Error injection configuration
typedef struct {
    error_type_t error_type;
    real injection_probability;  // 0.0 to 1.0
    int injection_cycle_delay;
    int burst_length;
    bit inject_continuously;
    bit verbose;
} error_inject_config_t;

// Error injection class
class ErrorInjector;

    // Configuration
    error_inject_config_t cfg;

    // Internal state
    bit enabled;
    int cycle_counter;
    int error_counter;
    int burst_counter;

    // Constructor
    function new(string name = "default_inj");
        cfg.error_type = ERROR_NONE;
        cfg.injection_probability = 0.0;
        cfg.injection_cycle_delay = 0;
        cfg.burst_length = 1;
        cfg.inject_continuously = 0;
        cfg.verbose = 0;

        enabled = 0;
        cycle_counter = 0;
        error_counter = 0;
        burst_counter = 0;
    endfunction

    // Configuration methods
    function void set_error_type(error_type_t err_type);
        cfg.error_type = err_type;
        if (cfg.verbose) begin
            $display("[%0t] ErrorInjector: Set error type to %s", $time, err_type.name());
        end
    endfunction

    function void set_injection_probability(real prob);
        cfg.injection_probability = (prob >= 0.0 && prob <= 1.0) ? prob : 0.0;
        if (cfg.verbose) begin
            $display("[%0t] ErrorInjector: Set injection probability to %0.3f",
                    $time, cfg.injection_probability);
        end
    endfunction

    function void set_burst_parameters(int cycle_delay, int burst_len);
        cfg.injection_cycle_delay = cycle_delay;
        cfg.burst_length = burst_len;
        if (cfg.verbose) begin
            $display("[%0t] ErrorInjector: Set burst - delay=%0d, length=%0d",
                    $time, cycle_delay, burst_len);
        end
    endfunction

    function void enable();
        enabled = 1;
        cycle_counter = 0;
        error_counter = 0;
        burst_counter = 0;
        if (cfg.verbose) begin
            $display("[%0t] ErrorInjector: Enabled", $time);
        end
    endfunction

    function void disable();
        enabled = 0;
        if (cfg.verbose) begin
            $display("[%0t] ErrorInjector: Disabled (injected %0d errors)",
                    $time, error_counter);
        end
    endfunction

    // Bit flip injection
    function automatic bit inject_bit_flip(bit data_in);
        bit flipped_bit;
        int flip_position;

        if (cfg.error_type != ERROR_BIT_FLIP || !enabled) begin
            return data_in;
        end

        // Random bit flip based on probability
        if ($random % 1000 < (cfg.injection_probability * 1000.0)) begin
            flip_position = $random % 1;  // Single bit
            flipped_bit = data_in ^ (1 << flip_position);
            error_counter++;

            if (cfg.verbose) begin
                $display("[%0t] ErrorInjector: Bit flip - pos=%0d, data_in=%b->%b",
                        $time, flip_position, data_in, flipped_bit);
            end

            return flipped_bit;
        end

        return data_in;
    endfunction

    // Multi-bit injection for wider data
    function automatic logic [31:0] inject_multi_bit_flip(logic [31:0] data_in);
        logic [31:0] corrupted_data;
        int num_flips, flip_pos;
        int i;

        corrupted_data = data_in;

        if (cfg.error_type != ERROR_BIT_FLIP || !enabled) begin
            return corrupted_data;
        end

        // Determine number of bit flips based on probability
        if ($random % 1000 < (cfg.injection_probability * 1000.0)) begin
            num_flips = ($random % 4) + 1;  // 1 to 4 bit flips

            for (i = 0; i < num_flips; i++) begin
                flip_pos = $random % 32;
                corrupted_data[flip_pos] = ~corrupted_data[flip_pos];
            end

            error_counter++;

            if (cfg.verbose) begin
                $display("[%0t] ErrorInjector: Multi-bit flip - flips=%0d, data_in=0x%08h->0x%08h",
                        $time, num_flips, data_in, corrupted_data);
            end
        end

        return corrupted_data;
    endfunction

    // CRC corruption injection
    function automatic logic [7:0] inject_crc_error(logic [7:0] crc_in);
        logic [7:0] corrupted_crc;

        corrupted_crc = crc_in;

        if (cfg.error_type != ERROR_CRC_MISMATCH || !enabled) begin
            return corrupted_crc;
        end

        if ($random % 1000 < (cfg.injection_probability * 1000.0)) begin
            // Flip some bits in CRC
            corrupted_crc = corrupted_crc ^ ($random % 256);
            error_counter++;

            if (cfg.verbose) begin
                $display("[%0t] ErrorInjector: CRC corruption - crc=0x%02h->0x%02h",
                        $time, crc_in, corrupted_crc);
            end
        end

        return corrupted_crc;
    endfunction

    // Frame corruption (SYNC pattern corruption)
    function automatic logic [7:0] inject_sync_error(logic [7:0] sync_in);
        logic [7:0] corrupted_sync;

        corrupted_sync = sync_in;

        if (cfg.error_type != ERROR_FRAME_CORRUPT || !enabled) begin
            return corrupted_sync;
        end

        if ($random % 1000 < (cfg.injection_probability * 1000.0)) begin
            // Corrupt SYNC pattern (change from 0xAA)
            corrupted_sync = $random;
            error_counter++;

            if (cfg.verbose) begin
                $display("[%0t] ErrorInjector: SYNC corruption - sync=0x%02h->0x%02h",
                        $time, sync_in, corrupted_sync);
            end
        end

        return corrupted_sync;
    endfunction

    // Clock glitch simulation
    task automatic inject_clock_glitch(ref bit clk_signal, ref bit glitch_active);
        int glitch_duration;

        if (cfg.error_type != ERROR_CLOCK_GLITCH || !enabled) begin
            return;
        end

        if ($random % 10000 < (cfg.injection_probability * 10000.0)) begin
            glitch_duration = ($random % 10) + 1;  // 1-10 cycle glitch
            glitch_active = 1;
            error_counter++;

            if (cfg.verbose) begin
                $display("[%0t] ErrorInjector: Clock glitch - duration=%0d cycles",
                        $time, glitch_duration);
            end

            // Apply glitch
            fork
                begin
                    repeat (glitch_duration) @(posedge clk_signal);
                    glitch_active = 0;
                end
            join_none
        end
    endtask

    // Burst error injection
    function automatic bit inject_burst_error(bit data_in);
        bit corrupted_data;

        corrupted_data = data_in;

        if (cfg.error_type != ERROR_BURST_ERROR || !enabled) begin
            return corrupted_data;
        end

        // Check if we should start a burst
        if (burst_counter == 0 && cycle_counter >= cfg.injection_cycle_delay) begin
            if ($random % 1000 < (cfg.injection_probability * 1000.0)) begin
                burst_counter = cfg.burst_length;
                if (cfg.verbose) begin
                    $display("[%0t] ErrorInjector: Starting burst error - length=%0d",
                            $time, cfg.burst_length);
                end
            end
        end

        // Apply burst error
        if (burst_counter > 0) begin
            corrupted_data = ~data_in;
            burst_counter--;
            error_counter++;

            if (cfg.verbose && burst_counter == 0) begin
                $display("[%0t] ErrorInjector: Burst error completed", $time);
            end
        end

        cycle_counter++;
        return corrupted_data;
    endfunction

    // Statistics
    function int get_error_count();
        return error_counter;
    endfunction

    function void reset_stats();
        error_counter = 0;
        cycle_counter = 0;
        burst_counter = 0;
    endfunction

endclass

// Utility function to create pre-configured error injectors
function automatic ErrorInjector create_error_injector(error_type_t err_type, real prob);
    ErrorInjector inj = new();
    inj.set_error_type(err_type);
    inj.set_injection_probability(prob);
    return inj;
endfunction