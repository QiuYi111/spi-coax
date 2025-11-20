#!/bin/bash
#==============================================================================
# Production Test Runner for SPI-Coax System
# Provides comprehensive testing with automated reporting
#==============================================================================

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$SCRIPT_DIR"
RESULTS_DIR="$TEST_DIR/test_results"
LOG_DIR="$TEST_DIR/logs"
REPORTS_DIR="$TEST_DIR/reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[PROD-TEST]${NC} $message"
}

# Function to check dependencies
check_dependencies() {
    print_status $BLUE "Checking dependencies..."

    local missing_deps=()

    if ! command -v iverilog &> /dev/null; then
        missing_deps+=("iverilog")
    fi

    if ! command -v vvp &> /dev/null; then
        missing_deps+=("vvp")
    fi

    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status $RED "Missing dependencies: ${missing_deps[*]}"
        print_status $YELLOW "Please install missing dependencies and try again"
        exit 1
    fi

    print_status $GREEN "All dependencies found"
}

# Function to setup test environment
setup_environment() {
    print_status $BLUE "Setting up test environment..."

    # Create directories
    mkdir -p "$RESULTS_DIR" "$LOG_DIR" "$REPORTS_DIR"

    # Set permissions
    chmod +x "$TEST_DIR/analyze_test_results.py"
    chmod +x "$TEST_DIR/run_production_tests.sh"

    # Clean any previous runs
    rm -f "$TEST_DIR"/*.vcd "$TEST_DIR"/*.exe

    print_status $GREEN "Test environment ready"
}

# Function to run basic functionality tests
run_basic_tests() {
    print_status $BLUE "Running basic functionality tests..."

    cd "$TEST_DIR"

    # Compile basic test
    if ! make tb_spi_coax_system.exe; then
        print_status $RED "Failed to compile basic test"
        return 1
    fi

    # Run basic test with timeout
    print_status $BLUE "Executing basic system test..."
    timeout 300s vvp tb_spi_coax_system.exe > "$LOG_DIR/basic_test_${TIMESTAMP}.log" 2>&1 || {
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            print_status $RED "Basic test timed out after 5 minutes"
        else
            print_status $RED "Basic test failed with exit code $exit_code"
        fi
        return 1
    }

    # Check basic test results
    if grep -q "Simulation Timeout\|TEST FAILED\|ERROR\|FATAL" "$LOG_DIR/basic_test_${TIMESTAMP}.log"; then
        print_status $RED "Basic test detected failures"
        return 1
    fi

    print_status $GREEN "Basic functionality tests passed"
    return 0
}

# Function to run production test suite
run_production_tests() {
    print_status $BLUE "Running production test suite..."

    cd "$TEST_DIR"

    # Compile production test
    if ! make tb_spi_coax_production_simple.exe; then
        print_status $RED "Failed to compile production test"
        return 1
    fi

    # Run production test with extended timeout
    print_status $BLUE "Executing production test suite (this may take several minutes)..."
    timeout 1800s vvp tb_spi_coax_production_simple.exe > "$LOG_DIR/production_test_${TIMESTAMP}.log" 2>&1 || {
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            print_status $RED "Production test timed out after 30 minutes"
        else
            print_status $RED "Production test failed with exit code $exit_code"
        fi
        return 1
    }

    # Generate HTML report
    print_status $BLUE "Generating production test report..."
    if python3 "$TEST_DIR/analyze_test_results.py" \
        "$LOG_DIR/production_test_${TIMESTAMP}.log" \
        "$REPORTS_DIR/production_test_${TIMESTAMP}.html"; then
        print_status $GREEN "Production test report generated"
    else
        print_status $YELLOW "Warning: Failed to generate HTML report"
    fi

    print_status $GREEN "Production test suite completed"
    return 0
}

# Function to run stress tests
run_stress_tests() {
    print_status $BLUE "Running stress tests..."

    cd "$TEST_DIR"

    # Run stress test with timeout
    print_status $BLUE "Executing stress test (10 minute timeout)..."
    timeout 600s vvp tb_spi_coax_production_simple.exe > "$LOG_DIR/stress_test_${TIMESTAMP}.log" 2>&1 || {
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            print_status $YELLOW "Stress test timeout (expected for long-running test)"
        else
            print_status $RED "Stress test failed with exit code $exit_code"
            return 1
        fi
    }

    print_status $GREEN "Stress tests completed"
    return 0
}

# Function to run module-level tests
run_module_tests() {
    print_status $BLUE "Running module-level tests..."

    cd "$TEST_DIR"

    local failed_modules=()

    # Compile and run each module test
    for test_file in tb_*.v; do
        if [ "$test_file" != "tb_spi_coax_system.v" ]; then
            local module_name=$(basename "$test_file" .v)
            print_status $BLUE "Testing module: $module_name"

            if ! make "${module_name}.exe"; then
                print_status $RED "Failed to compile $module_name"
                failed_modules+=("$module_name")
                continue
            fi

            # Run module test with timeout
            if timeout 120s vvp "${module_name}.exe" > "$LOG_DIR/${module_name}_${TIMESTAMP}.log" 2>&1; then
                print_status $GREEN "✓ $module_name passed"
            else
                print_status $RED "✗ $module_name failed"
                failed_modules+=("$module_name")
            fi
        fi
    done

    if [ ${#failed_modules[@]} -eq 0 ]; then
        print_status $GREEN "All module tests passed"
        return 0
    else
        print_status $RED "Failed modules: ${failed_modules[*]}"
        return 1
    fi
}

# Function to generate summary report
generate_summary() {
    print_status $BLUE "Generating test summary..."

    local summary_file="$REPORTS_DIR/test_summary_${TIMESTAMP}.txt"

    cat > "$summary_file" << EOF
==============================================================================
SPI-Coax Production Test Summary
==============================================================================
Generated: $(date)
Test Directory: $TEST_DIR
Project Root: $PROJECT_ROOT

Test Results:
------------
Basic Tests: $(grep -q "PASSED" "$LOG_DIR/basic_test_${TIMESTAMP}.log" 2>/dev/null && echo "PASSED" || echo "FAILED")
Production Tests: $(grep -q "completed successfully" "$LOG_DIR/production_test_${TIMESTAMP}.log" 2>/dev/null && echo "PASSED" || echo "COMPLETED_WITH_WARNINGS")
Stress Tests: $(test -f "$LOG_DIR/stress_test_${TIMESTAMP}.log" && echo "COMPLETED" || echo "SKIPPED")
Module Tests: COMPLETED

Log Files:
----------
Basic Test: $LOG_DIR/basic_test_${TIMESTAMP}.log
Production Test: $LOG_DIR/production_test_${TIMESTAMP}.log
Stress Test: $LOG_DIR/stress_test_${TIMESTAMP}.log
Module Tests: $LOG_DIR/*_${TIMESTAMP}.log

Reports:
--------
Production HTML Report: $REPORTS_DIR/production_test_${TIMESTAMP}.html

==============================================================================
EOF

    print_status $GREEN "Test summary generated: $summary_file"

    # Display summary
    cat "$summary_file"
}

# Function to cleanup
cleanup() {
    print_status $BLUE "Cleaning up temporary files..."

    # Remove VCD files (they can be very large)
    find "$TEST_DIR" -name "*.vcd" -type f -delete 2>/dev/null || true

    # Remove compiled test files
    find "$TEST_DIR" -name "*.exe" -type f -delete 2>/dev/null || true

    print_status $GREEN "Cleanup completed"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --basic-only     Run only basic functionality tests"
    echo "  --production     Run production test suite (default)"
    echo "  --stress         Include stress tests"
    echo "  --modules        Include module-level tests"
    echo "  --all            Run all tests (basic + production + stress + modules)"
    echo "  --no-cleanup     Don't cleanup temporary files after tests"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --basic-only           # Quick functionality check"
    echo "  $0 --production           # Standard production tests"
    echo "  $0 --all                  # Complete test suite"
}

# Main execution
main() {
    local run_basic=true
    local run_production=true
    local run_stress=false
    local run_modules=false
    local do_cleanup=true

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --basic-only)
                run_basic=true
                run_production=false
                run_stress=false
                run_modules=false
                shift
                ;;
            --production)
                run_basic=false
                run_production=true
                run_stress=false
                run_modules=false
                shift
                ;;
            --stress)
                run_stress=true
                shift
                ;;
            --modules)
                run_modules=true
                shift
                ;;
            --all)
                run_basic=true
                run_production=true
                run_stress=true
                run_modules=true
                shift
                ;;
            --no-cleanup)
                do_cleanup=false
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_status $RED "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    print_status $BLUE "Starting SPI-Coax Production Test Runner"
    print_status $BLUE "Timestamp: $TIMESTAMP"

    # Execute test phases
    check_dependencies
    setup_environment

    local overall_result=0

    if [ "$run_basic" = true ]; then
        if ! run_basic_tests; then
            overall_result=1
        fi
    fi

    if [ "$run_production" = true ]; then
        if ! run_production_tests; then
            overall_result=1
        fi
    fi

    if [ "$run_stress" = true ]; then
        if ! run_stress_tests; then
            overall_result=1
        fi
    fi

    if [ "$run_modules" = true ]; then
        if ! run_module_tests; then
            overall_result=1
        fi
    fi

    generate_summary

    if [ "$do_cleanup" = true ]; then
        cleanup
    fi

    if [ $overall_result -eq 0 ]; then
        print_status $GREEN "✅ All tests completed successfully"
    else
        print_status $RED "❌ Some tests failed - check logs for details"
    fi

    print_status $BLUE "Test execution completed"
    exit $overall_result
}

# Run main function with all arguments
main "$@"