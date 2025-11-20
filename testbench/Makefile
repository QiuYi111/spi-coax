#==============================================================================
# Makefile for SPI-Coax Test Suite
# Provides automated compilation, execution, and regression testing
#==============================================================================

# Configuration
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave
PYTHON = python3
TEST_DIR = .
RESULTS_DIR = test_results
LOG_DIR = logs
REPORTS_DIR = reports

# Source files
RTL_FILES = ../*.v
TB_COMMON_FILES = test_framework_simple.v error_injection_simple.v

# Testbench files
TB_FILES = \
	tb_spi_coax_system.v \
	tb_encoder.v \
	tb_decoder.v \
	tb_cdr.v \
	tb_frame_sync.v \
	tb_frame_packer.v \
	tb_manchester_encoder.v \
	tb_spi_master.v \
	tb_spi_coax_production_simple.v

# Test executables
TEST_EXES = $(TB_FILES:.v=.exe)
TEST_EXES := $(TEST_EXES:.sv=.exe)

# Default target
.PHONY: all
all: setup test_basic

# Create necessary directories
.PHONY: setup
setup:
	@mkdir -p $(RESULTS_DIR) $(LOG_DIR) $(REPORTS_DIR)
	@echo "Test directories created"

# Compile individual testbenches
.PHONY: compile_all
compile_all: $(TEST_EXES)

# Basic functionality test
.PHONY: test_basic
test_basic: tb_spi_coax_system.exe
	@echo "Running basic system test..."
	$(VVP) $< 2>&1 | tee $(LOG_DIR)/basic_test.log
	@if grep -q "TEST FAILED\|ERROR\|FATAL" $(LOG_DIR)/basic_test.log; then \
		echo "❌ Basic test FAILED"; exit 1; \
	else \
		echo "✅ Basic test PASSED"; \
	fi

# Production-level test suite
.PHONY: test_production
test_production: tb_spi_coax_production.exe
	@echo "Running production test suite..."
	$(VVP) $< 2>&1 | tee $(LOG_DIR)/production_test.log
	@python3 analyze_test_results.py $(LOG_DIR)/production_test.log $(REPORTS_DIR)/production_report.html

# Module-level tests
.PHONY: test_modules
test_modules: compile_all
	@echo "Running module-level tests..."
	@for test in $(filter-out tb_spi_coax_production.exe,$(TEST_EXES)); do \
		echo "Running $$test..."; \
		$(VVP) $$test 2>&1 | tee $(LOG_DIR)/$${test%.exe}.log; \
	done

# Regression test suite
.PHONY: test_regression
test_regression: test_basic test_production test_modules
	@echo "All regression tests completed"
	@python3 generate_regression_report.py $(LOG_DIR) $(REPORTS_DIR)

# Stress tests
.PHONY: test_stress
test_stress: tb_spi_coax_production.exe
	@echo "Running stress tests..."
	$(VVP) $< 2>&1 | tee $(LOG_DIR)/stress_test.log &
	@STRESS_PID=$$!; \
	sleep 60; \
	if kill -0 $$STRESS_PID 2>/dev/null; then \
		echo "✅ Stress test running normally (60s checkpoint)"; \
		wait $$STRESS_PID; \
	else \
		echo "❌ Stress test crashed"; \
		exit 1; \
	fi

# Performance benchmarks
.PHONY: test_performance
test_performance: tb_spi_coax_production.exe
	@echo "Running performance benchmarks..."
	@/usr/bin/time -v $(VVP) $< 2>&1 | tee $(LOG_DIR)/performance.log
	@python3 analyze_performance.py $(LOG_DIR)/performance.log $(REPORTS_DIR)/performance_report.html

# Code coverage analysis
.PHONY: coverage
coverage: clean compile_all
	@echo "Running code coverage analysis..."
	@for test in $(TEST_EXES); do \
		echo "Coverage for $$test..."; \
		$(VVP) $$test +coverage 2>&1 | tee $(LOG_DIR)/coverage_$${test%.exe}.log; \
	done
	@python3 merge_coverage.py $(LOG_DIR)/coverage_*.log $(REPORTS_DIR)/coverage_report.html

# Memory leak detection (if supported)
.PHONY: test_memory
test_memory: tb_spi_coax_production.exe
	@echo "Running memory leak detection..."
	@valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all \
		$(VVP) $< 2>&1 | tee $(LOG_DIR)/memory_test.log

# Continuous integration target
.PHONY: ci
ci: clean setup test_regression
	@echo "CI pipeline completed successfully"

# Clean targets
.PHONY: clean
clean:
	@echo "Cleaning generated files..."
	@rm -f *.exe *.vcd *.out
	@rm -rf $(RESULTS_DIR)/*
	@rm -rf $(LOG_DIR)/*
	@echo "Clean completed"

# Deep clean (including all results)
.PHONY: distclean
distclean: clean
	@rm -rf $(RESULTS_DIR) $(LOG_DIR) $(REPORTS_DIR)

# View waveforms
.PHONY: waves
waves: $(RESULTS_DIR)/dump.vcd
	@echo "Opening waveform viewer..."
	$(GTKWAVE) $< &

# Quick test (for development)
.PHONY: test_quick
test_quick: tb_spi_coax_system_fast.exe
	@echo "Running quick system test..."
	$(VVP) $< 2>&1 | tee $(LOG_DIR)/quick_test.log

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  all              - Build and run basic tests"
	@echo "  setup            - Create test directories"
	@echo "  compile_all      - Compile all testbenches"
	@echo "  test_basic       - Run basic functionality test"
	@echo "  test_production  - Run production-level test suite"
	@echo "  test_modules     - Run all module-level tests"
	@echo "  test_regression  - Run complete regression suite"
	@echo "  test_stress      - Run stress tests"
	@echo "  test_performance - Run performance benchmarks"
	@echo "  coverage         - Run code coverage analysis"
	@echo "  test_memory      - Run memory leak detection"
	@echo "  ci               - CI pipeline (full regression)"
	@echo "  clean            - Clean generated files"
	@echo "  distclean        - Deep clean including results"
	@echo "  waves            - View waveform viewer"
	@echo "  test_quick       - Quick development test"
	@echo "  help             - Show this help"

# Pattern rules for compilation
%.exe: %.v $(RTL_FILES) $(TB_COMMON_FILES)
	@echo "Compiling $<"
	$(IVERILOG) -o $@ $(RTL_FILES) $(TB_COMMON_FILES) $< -I$(TEST_DIR) -g2012

# SystemVerilog compilation (not used in this simplified version)
# %.exe: %.sv $(RTL_FILES) $(TB_COMMON_FILES)
#	@echo "Compiling SystemVerilog testbench $<"
#	$(IVERILOG) -o $@ $(RTL_FILES) $(TB_COMMON_FILES) $< -I$(TEST_DIR) -g2012