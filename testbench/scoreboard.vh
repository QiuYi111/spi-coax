// Scoreboard for Transaction-Level Verification
// Tracks expected vs actual data with automatic checking

`ifndef SCOREBOARD_VH
`define SCOREBOARD_VH

// ============================================================================
// SCOREBOARD DATA STRUCTURE
// ============================================================================

// Simple scoreboard using arrays (Verilog doesn't have classes in all versions)
// We'll use a queue-like structure with read/write pointers

// Global scoreboard state
integer sb_wr_ptr;      // Write pointer (producer)
integer sb_rd_ptr;      // Read pointer (consumer)
integer sb_size;        // Current size
integer sb_max_size;    // Maximum size reached
integer sb_capacity;    // Total capacity

// Data storage (sized for 1024 entries)
reg [31:0] sb_data [0:1023];
reg [31:0] sb_timestamp [0:1023];
reg [7:0]  sb_metadata [0:1023];  // Optional metadata (e.g., frame counter)

// Statistics
integer sb_pushed;      // Total items pushed
integer sb_popped;      // Total items popped
integer sb_matched;     // Successful matches
integer sb_mismatched;  // Mismatches detected
integer sb_latency_sum; // Sum of latencies for average calculation
integer sb_latency_min; // Minimum latency
integer sb_latency_max; // Maximum latency

// ============================================================================
// SCOREBOARD INITIALIZATION
// ============================================================================

task sb_init;
    input integer capacity;
    begin
        sb_wr_ptr = 0;
        sb_rd_ptr = 0;
        sb_size = 0;
        sb_max_size = 0;
        sb_capacity = capacity;
        
        sb_pushed = 0;
        sb_popped = 0;
        sb_matched = 0;
        sb_mismatched = 0;
        sb_latency_sum = 0;
        sb_latency_min = 32'hFFFFFFFF;
        sb_latency_max = 0;
        
        $display("[SCOREBOARD] Initialized with capacity %0d", capacity);
    end
endtask

// ============================================================================
// SCOREBOARD OPERATIONS
// ============================================================================

// Push expected data to scoreboard
task sb_push;
    input [31:0] data;
    input [7:0] metadata;
    begin
        if (sb_size >= sb_capacity) begin
            $error("[SCOREBOARD] Overflow! Cannot push data %h", data);
        end else begin
            sb_data[sb_wr_ptr] = data;
            sb_timestamp[sb_wr_ptr] = $time;
            sb_metadata[sb_wr_ptr] = metadata;
            
            sb_wr_ptr = (sb_wr_ptr + 1) % sb_capacity;
            sb_size = sb_size + 1;
            sb_pushed = sb_pushed + 1;
            
            if (sb_size > sb_max_size) sb_max_size = sb_size;
            
            $display("[SCOREBOARD] Pushed: data=%h metadata=%h size=%0d time=%0t", 
                     data, metadata, sb_size, $time);
        end
    end
endtask

// Check received data against scoreboard
task sb_check;
    input [31:0] actual_data;
    input [7:0] actual_metadata;
    output matched;
    
    reg [31:0] expected_data;
    reg [7:0] expected_metadata;
    integer latency;
    begin
        matched = 0;
        
        if (sb_size == 0) begin
            $error("[SCOREBOARD] Underflow! Received unexpected data %h at time %0t", 
                   actual_data, $time);
            sb_mismatched = sb_mismatched + 1;
        end else begin
            expected_data = sb_data[sb_rd_ptr];
            expected_metadata = sb_metadata[sb_rd_ptr];
            latency = $time - sb_timestamp[sb_rd_ptr];
            
            sb_rd_ptr = (sb_rd_ptr + 1) % sb_capacity;
            sb_size = sb_size - 1;
            sb_popped = sb_popped + 1;
            
            // Check data match
            if (actual_data === expected_data) begin
                matched = 1;
                sb_matched = sb_matched + 1;
                
                // Update latency statistics
                sb_latency_sum = sb_latency_sum + latency;
                if (latency < sb_latency_min) sb_latency_min = latency;
                if (latency > sb_latency_max) sb_latency_max = latency;
                
                $display("[SCOREBOARD] MATCH: data=%h metadata=%h latency=%0dns time=%0t", 
                         actual_data, actual_metadata, latency, $time);
            end else begin
                sb_mismatched = sb_mismatched + 1;
                $error("[SCOREBOARD] MISMATCH: expected=%h actual=%h metadata=%h time=%0t", 
                       expected_data, actual_data, actual_metadata, $time);
            end
            
            // Optional: Check metadata
            if (actual_metadata !== expected_metadata) begin
                $warning("[SCOREBOARD] Metadata mismatch: expected=%h actual=%h", 
                         expected_metadata, actual_metadata);
            end
        end
    end
endtask

// Peek at next expected value without removing
task sb_peek;
    output [31:0] data;
    output [7:0] metadata;
    begin
        if (sb_size == 0) begin
            data = 32'hXXXXXXXX;
            metadata = 8'hXX;
        end else begin
            data = sb_data[sb_rd_ptr];
            metadata = sb_metadata[sb_rd_ptr];
        end
    end
endtask

// ============================================================================
// SCOREBOARD REPORTING
// ============================================================================

task sb_report;
    real avg_latency;
    real match_rate;
    begin
        $display("");
        $display("========================================");
        $display("SCOREBOARD REPORT");
        $display("========================================");
        $display("Capacity:        %0d entries", sb_capacity);
        $display("Max Utilization: %0d entries", sb_max_size);
        $display("Total Pushed:    %0d", sb_pushed);
        $display("Total Popped:    %0d", sb_popped);
        $display("Matched:         %0d", sb_matched);
        $display("Mismatched:      %0d", sb_mismatched);
        $display("Remaining:       %0d", sb_size);
        
        if (sb_popped > 0) begin
            match_rate = (sb_matched * 100.0) / sb_popped;
            $display("Match Rate:      %.2f%%", match_rate);
        end
        
        if (sb_matched > 0) begin
            avg_latency = sb_latency_sum / sb_matched;
            $display("Latency Min:     %0d ns", sb_latency_min);
            $display("Latency Avg:     %.2f ns", avg_latency);
            $display("Latency Max:     %0d ns", sb_latency_max);
        end
        
        if (sb_mismatched > 0) begin
            $display("STATUS:          FAILED (%0d mismatches)", sb_mismatched);
        end else if (sb_size > 0) begin
            $display("STATUS:          WARNING (%0d items not checked)", sb_size);
        end else begin
            $display("STATUS:          PASSED");
        end
        $display("========================================");
    end
endtask

// Check if scoreboard is empty (all transactions completed)
function sb_is_empty;
    begin
        sb_is_empty = (sb_size == 0);
    end
endfunction

// Check if scoreboard has errors
function sb_has_errors;
    begin
        sb_has_errors = (sb_mismatched > 0);
    end
endfunction

// Get current scoreboard size
function integer sb_get_size;
    begin
        sb_get_size = sb_size;
    end
endfunction

`endif // SCOREBOARD_VH
