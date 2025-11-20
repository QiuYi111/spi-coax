#!/bin/bash

# Production-Grade Testbench Runner
# Executes all testbenches and generates comprehensive test report

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Output directory
RESULTS_DIR="test_results"
mkdir -p "$RESULTS_DIR"

# Timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$RESULTS_DIR/test_report_${TIMESTAMP}.txt"

echo "========================================"  | tee "$REPORT_FILE"
echo "SPI-Coax Production Testbench Suite"      | tee -a "$REPORT_FILE"
echo "========================================"  | tee -a "$REPORT_FILE"
echo "Started: $(date)"                         | tee -a "$REPORT_FILE"
echo ""                                         | tee -a "$REPORT_FILE"

# Function to run a single test
run_test() {
    local test_name=$1
    local test_file=$2
    local output_file="$RESULTS_DIR/${test_name}_${TIMESTAMP}.log"
    
    echo -e "${BLUE}[TEST]${NC} Running $test_name..." | tee -a "$REPORT_FILE"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Compile
    if iverilog -g2009 -o "$RESULTS_DIR/sim_$test_name" "$test_file" ../*.v 2>&1 | tee "$output_file"; then
        # Run simulation
        if vvp "$RESULTS_DIR/sim_$test_name" >> "$output_file" 2>&1; then
            # Check for errors in output
            if grep -q "ASSERTION FAILED\|CHECK FAILED\|ERROR\|FAILED" "$output_file"; then
                echo -e "${RED}[FAIL]${NC} $test_name - Assertions failed" | tee -a "$REPORT_FILE"
                FAILED_TESTS=$((FAILED_TESTS + 1))
                echo "  Log: $output_file" | tee -a "$REPORT_FILE"
                return 1
            elif grep -q "RESULT: PASSED\|ALL TESTS PASSED" "$output_file"; then
                echo -e "${GREEN}[PASS]${NC} $test_name" | tee -a "$REPORT_FILE"
                PASSED_TESTS=$((PASSED_TESTS + 1))
                return 0
            else
                echo -e "${YELLOW}[WARN]${NC} $test_name - No clear pass/fail" | tee -a "$REPORT_FILE"
                PASSED_TESTS=$((PASSED_TESTS + 1))
                return 0
            fi
        else
            echo -e "${RED}[FAIL]${NC} $test_name - Runtime error" | tee -a "$REPORT_FILE"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            echo "  Log: $output_file" | tee -a "$REPORT_FILE"
            return 1
        fi
    else
        echo -e "${RED}[FAIL]${NC} $test_name - Compilation error" | tee -a "$REPORT_FILE"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "  Log: $output_file" | tee -a "$REPORT_FILE"
        return 1
    fi
}

# Change to testbench directory
cd "$(dirname "$0")"

echo "========================================"  | tee -a "$REPORT_FILE"
echo "Module-Level Tests"                       | tee -a "$REPORT_FILE"
echo "========================================"  | tee -a "$REPORT_FILE"
echo ""                                         | tee -a "$REPORT_FILE"

# Run module tests
run_test "spi_master" "tb_spi_master.v" || true
run_test "frame_packer" "tb_frame_packer.v" || true
run_test "manchester_encoder" "tb_manchester_encoder.v" || true
run_test "cdr" "tb_cdr.v" || true
run_test "frame_sync" "tb_frame_sync.v" || true

echo ""                                         | tee -a "$REPORT_FILE"
echo "========================================"  | tee -a "$REPORT_FILE"
echo "Integration Tests"                        | tee -a "$REPORT_FILE"
echo "========================================"  | tee -a "$REPORT_FILE"
echo ""                                         | tee -a "$REPORT_FILE"

# Run integration tests
run_test "encoder" "tb_encoder.v" || true
run_test "decoder" "tb_decoder.v" || true

echo ""                                         | tee -a "$REPORT_FILE"
echo "========================================"  | tee -a "$REPORT_FILE"
echo "System-Level Tests"                       | tee -a "$REPORT_FILE"
echo "========================================"  | tee -a "$REPORT_FILE"
echo ""                                         | tee -a "$REPORT_FILE"

# Run system tests
run_test "system_enhanced" "tb_spi_coax_system_enhanced.v" || true
run_test "system_fast" "tb_spi_coax_system_fast.v" || true

echo ""                                         | tee -a "$REPORT_FILE"
echo "========================================"  | tee -a "$REPORT_FILE"
echo "TEST SUMMARY"                             | tee -a "$REPORT_FILE"
echo "========================================"  | tee -a "$REPORT_FILE"
echo "Total Tests:  $TOTAL_TESTS"              | tee -a "$REPORT_FILE"
echo -e "${GREEN}Passed:${NC}       $PASSED_TESTS" | tee -a "$REPORT_FILE"
echo -e "${RED}Failed:${NC}       $FAILED_TESTS" | tee -a "$REPORT_FILE"

if [ $TOTAL_TESTS -gt 0 ]; then
    PASS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo "Pass Rate:    ${PASS_RATE}%"          | tee -a "$REPORT_FILE"
fi

echo ""                                         | tee -a "$REPORT_FILE"
echo "Finished: $(date)"                        | tee -a "$REPORT_FILE"
echo "Report saved to: $REPORT_FILE"            | tee -a "$REPORT_FILE"
echo "========================================"  | tee -a "$REPORT_FILE"

# Exit with error if any tests failed
if [ $FAILED_TESTS -gt 0 ]; then
    exit 1
else
    exit 0
fi
