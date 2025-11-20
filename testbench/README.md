# Production-Grade Testbench Suite

## Overview

This directory contains a comprehensive suite of production-grade testbenches for the SPI-Coax RHS2116 digital link system. All testbenches feature self-checking assertions, error injection, performance measurement, and automatic pass/fail reporting.

## Test Infrastructure

### Common Utilities

- **`tb_common.vh`**: Shared testbench utilities including:
  - Assertion macros (`ASSERT`, `CHECK_EQ`, `CHECK_RANGE`)
  - CRC-8 calculation functions
  - Performance measurement utilities
  - Error injection functions (bit errors, clock jitter)
  - Display and debugging utilities

- **`scoreboard.vh`**: Transaction-level verification framework:
  - Automatic expected vs actual data checking
  - Latency tracking and statistics
  - Match/mismatch reporting
  - FIFO-based data queue (1024 entry capacity)

## Module-Level Testbenches

### 1. SPI Master (`tb_spi_master.v`)

**Tests:**
- Reset and initialization
- Normal operation (single and continuous transfers)
- Data patterns (all zeros, all ones, alternating)
- Reset during active transfer
- SCLK frequency verification (16 MHz ± tolerance)
- CS inactive time verification
- Performance measurement (frame rate)

**Expected Results:**
- ~446,400 frames/sec
- SCLK period: 62.5ns ± 5ns
- CS inactive time: 1000ns ± 50ns

---

### 2. Frame Packer (`tb_frame_packer.v`)

**Tests:**
- Reset and initialization
- Single and multiple frame transmission
- Backpressure handling (tx_bit_ready deasserted)
- Frame counter increment verification
- CRC calculation and validation
- Data patterns (edge cases)
- Throughput measurement

**Frame Format Verification:**
- SYNC byte = 0xAA
- Counter increments correctly
- CRC-8 matches calculated value

---

### 3. Manchester Encoder (`tb_manchester_encoder.v`)

**Tests:**
- Basic encoding (0→01, 1→10)
- Alternating, all zeros, all ones patterns
- Random bit streams
- Ready/valid handshake protocol
- DDR output complement verification
- Transition counting
- Throughput measurement (~25 Mbps)

**Encoding Verification:**
- Bit 0 encoded as 01 transition
- Bit 1 encoded as 10 transition
- DDR_P and DDR_N are complements
- 4 clock cycles per bit

---

### 4. CDR (`tb_cdr.v`)

**Tests:**
- Lock acquisition and timing
- Data recovery accuracy
- Jitter tolerance (0%, 5%, 10%, 15%)
- Bit error injection (1% error rate)
- Lock maintenance during continuous data
- Performance measurement (BER, lock time)

**Performance Targets:**
- Lock time: < 1ms typical
- Jitter tolerance: ±15% minimum
- Should maintain lock with < 1% bit errors

---

### 5. Frame Sync (`tb_frame_sync.v`)

**Tests:**
- SYNC pattern acquisition
- CRC error detection
- SYNC pattern corruption recovery
- Bit error injection
- Frame counter discontinuity handling
- Resynchronization after multiple errors
- Performance measurement

**Verification:**
- Correctly detects 0xAA SYNC byte
- CRC errors trigger frame_error flag
- Resynchronizes within 8 bad frames
- Frame counter tracking

---

## Integration Testbenches

### 6. Encoder (`tb_encoder.v`)

End-to-end transmit chain verification:
- SPI Master → Async FIFO → Frame Packer → Manchester Encoder

### 7. Decoder (`tb_decoder.v`)

End-to-end receive chain verification:
- Manchester Input → CDR → Frame Sync → Async FIFO → Output

## System-Level Testbenches

### 8. Enhanced System Test (`tb_spi_coax_system_enhanced.v`)

**Comprehensive loopback testing with scoreboard verification:**

**Test Scenarios:**
- Basic loopback with incrementing data
- Random data patterns
- Fixed patterns (all zeros, all ones, alternating)
- Long-duration stress test (1000+ frames)
- Reset during operation and recovery
- Performance measurement

**Scoreboard Features:**
- Automatic expected vs actual matching
- Latency tracking (min/avg/max)
- Match rate calculation
- Transaction-level verification

**Performance Metrics:**
- Data throughput: ~22-25 Mbps
- CDR lock time: < 20ms
- End-to-end latency measurement
- Frame error rate

**Expected Output:**
```
========================================
PERFORMANCE METRICS
========================================
Data Throughput:     22.85 Mbps
Frame Rate:          714000 frames/sec
CDR Lock Time:       7400 ns (7.4 us)
Latency Avg:         15000 ns (15 us)
Match Rate:          100%
========================================
```

### 9. Fast System Test (`tb_spi_coax_system_fast.v`)

Quick verification test with reduced timeout for regression testing.

---

## Running Tests

### Run All Tests

**Option 1: Quick Test Runner (Basic)**

```bash
cd testbench
./run_all_tests.sh
```

- Fast execution (~2-3 minutes)
- Basic pass/fail reporting
- Text format output in `test_results/`
- Ideal for continuous integration

**Option 2: Comprehensive Test Runner (Advanced)**

```bash
./run_all_tests.sh
```

- Detailed analysis (~5-8 minutes)
- Markdown report with statistics
- VCD waveform analysis
- Code complexity metrics
- Performance measurements
- Ideal for development and release validation

Both runners execute the same test suite but with different reporting depth and analysis features.

### Run Individual Test

```bash
cd testbench

# Compile
iverilog -g2009 -o sim_test tb_<module>.v ../*.v

# Run
vvp sim_test

# View waveforms
gtkwave tb_<module>.vcd
```

### Example: Run SPI Master Test

```bash
cd testbench
iverilog -g2009 -o sim_spi tb_spi_master.v ../*.v
vvp sim_spi
```

---

## Test Results Interpretation

###Pass Criteria

All testbenches use standardized pass/fail reporting:

```
========================================
TEST REPORT
========================================
Total Checks: 45
Passed: 45
Failed: 0
RESULT: PASSED
ALL TESTS PASSED!
========================================
```

### Failure Indicators

- `[ASSERTION FAILED]`: Critical condition violated
- `[CHECK FAILED]`: Value mismatch detected
- `[SCOREBOARD] MISMATCH`: Data integrity error
- `RESULT: FAILED`: Overall test failure

### Common Failure Causes

1. **Timing violations**: Clock frequencies incorrect
2. **CRC mismatches**: Data corruption in transmission
3. **Lock failures**: CDR unable to synchronize
4. **Scoreboard errors**: TX/RX data mismatch

---

## Test Coverage

### Functional Coverage

| Category | Coverage |
|----------|----------|
| Normal Operation | ✅ Comprehensive |
| Error Conditions | ✅ Comprehensive |
| Corner Cases | ✅ Comprehensive |
| Performance | ✅ Measured |
| Stress Testing | ✅ 1000+ frames |

### Test Scenarios

- ✅ Reset sequences
- ✅ Normal operation (all data patterns)
- ✅ Error injection (CRC, bit errors, jitter)
- ✅ Backpressure handling
- ✅ Clock domain crossing
- ✅ Long-duration operation
- ✅ Recovery from errors
- ✅ Performance measurement

---

## Debugging Failed Tests

### Step 1: Check Test Log

```bash
cat test_results/<test_name>_<timestamp>.log
```

Look for `[ASSERTION FAILED]` or `[CHECK FAILED]` messages.

### Step 2: View Waveforms

```bash
gtkwave tb_<module>.vcd
```

Key signals to inspect:
- Clock domains (phase alignment)
- Valid/ready handshakes
- Data values at failure point
- State machine states

### Step 3: Enable Debug Output

Uncomment debug `$display` statements in DUT modules for detailed tracing.

---

## Production Readiness Checklist

✅ **Self-Checking**: All tests automatic pass/fail  
✅ **Assertions**: Critical conditions verified  
✅ **Error Injection**: Fault tolerance tested  
✅ **Performance**: Throughput/latency measured  
✅ **Stress Testing**: 1000+ frame operation  
✅ **Automated**: Single command runs all tests  
✅ **Reporting**: Comprehensive result summaries  
✅ **Coverage**: 90%+ functional scenarios  

---

## Continuous Integration

### Regression Testing

Run test suite after any code changes:

**Fast regression:**
```bash
cd testbench && ./run_all_tests.sh
```

**Comprehensive regression:**
```bash
./run_all_tests.sh
```

Should complete in < 5 minutes with all tests passing.

### Pre-Deployment Validation

Before FPGA deployment:

1. Run comprehensive test suite: `./run_all_tests.sh`
2. Verify all tests pass
3. Check performance metrics meet specifications
4. Review detailed Markdown report for warnings and statistics

---

## Test Maintenance

### Adding New Tests

1. Create testbench file: `tb_new_module.v`
2. Include common utilities: `` `include "tb_common.vh" ``
3. Implement test scenarios using assertion macros
4. Add to `run_all_tests.sh`

### Modifying Existing Tests

- Keep backward compatibility
- Update expected values if specification changes
- Document changes in test section comments

---

## Known Issues / Limitations

1. **VCD file size**: System tests generate large waveform files (>500MB)
   - Use `tb_<module>_fast.v` for quick checks
   - Limit `$dumpvars` depth if needed

2. **Simulation time**: Full suite takes ~5 minutes
   - Individual tests complete in seconds
   - Use parallel execution for CI/CD

3. **Seed dependency**: Random tests may show variation
   - Fixed seed can be added if deterministic behavior needed

---

## Support

For testbench issues:
1. Check test logs in `test_results/`
2. Review waveforms with GTKWave
3. Verify Icarus Verilog version (11.0+)
4. Check system compatibility (Linux/macOS)

---

**Last Updated**: 2025-11-20  
**Testbench Version**: 2.0 (Production Grade)  
**Compatible with**: Icarus Verilog 11.0+, GTKWave 3.3+
