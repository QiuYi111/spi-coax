# RHS2116 Single-Wire Digital Link System

![Project Banner](assets/banner.jpg)

[English](README.md) | [中文](README_CN.md)

## 📖 Overview

This project provides a complete FPGA-based solution for transmitting RHS2116 SPI sensor data over a single coaxial cable. It utilizes Manchester encoding and supports Power-over-Coax (PoC), enabling reliable data transmission and power delivery over a single wire. The system is designed for high-speed, low-latency applications, achieving a payload data rate of 22.85 Mbps over 1-3 meters of coaxial cable.

---

## ✨ Key Features

| Feature | Specification | Description |
| :--- | :--- | :--- |
| **Payload Rate** | 22.85 Mbps | 714 kS/s × 32-bit |
| **Line Rate** | 50 Mbps (Manchester) | 100 MHz Symbol Rate |
| **Frame Format** | 56-bit | SYNC + CNT + DATA + CRC |
| **Distance** | 1-3 meters | Coaxial Cable |
| **Clocking** | Multi-domain | 64MHz SPI, 100MHz Sys, 200MHz CDR |
| **Power** | PoC Support | Power-over-Coax capable |

---

## 🏗️ System Architecture

![System Architecture](assets/arch.jpg)

### Transmit Side (Sensor End)
The transmitter interfaces with the RHS2116 sensor via SPI, buffers data through an asynchronous FIFO, packs it into frames with CRC protection, and applies Manchester encoding for transmission over the coaxial cable.

`RHS2116 → SPI Master (64MHz) → Async FIFO → Frame Packer (100MHz) → Manchester Encoder → Coax`

### Receive Side (Remote End)
The receiver recovers the clock and data from the incoming signal using a Soft CDR (Clock Data Recovery) module, synchronizes to the frame structure, validates data integrity via CRC, and outputs the decoded SPI data.

`Coax → CDR (200MHz) → Frame Sync (100MHz) → Async FIFO → Data Output`

---

## 🛠️ Development Environment

To build and simulate this project, you will need the following tools:

### FPGA Development
*   **IDE**: Intel Quartus Prime (Standard or Lite Edition)
*   **Target Device**: Intel MAX 10 FPGA
*   **Language**: Verilog HDL (IEEE 1364-2001)

### Simulation
*   **Simulator**: [Icarus Verilog (iverilog)](http://iverilog.icarus.com/)
*   **Waveform Viewer**: [GTKWave](http://gtkwave.sourceforge.net/)
*   **Testbench**: Located in `testbench/` directory.

### Recommended Setup
```bash

# Install on Ubuntu/Debian
sudo apt-get install iverilog gtkwave
```

---

## 🔩 Hardware & BOM

> **Note**: A complete PCB design and detailed BOM will be added in future updates.

### Core Components
1.  **FPGA**: Intel MAX 10 Series (e.g., 10M08 or 10M16)
    *   Selected for its instant-on capability and integrated ADC/Flash.
2.  **Sensor**: Intan RHS2116
    *   Digital electrophysiology stimulation/recording chip.
3.  **Interface**: SMA or BNC Connectors
    *   For robust coaxial cable connection.
4.  **Cable**: 50Ω Coaxial Cable (RG174 or similar)
    *   Impedance matching is critical for signal integrity.

---

## 🚀 Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/your-repo/spi-coax.git
cd spi-coax
```

### 2. Run Production-Grade Tests

This project includes a **comprehensive production-grade testbench suite** with self-checking assertions, error injection, and automated validation.

#### Quick Test (Recommended)
```bash
# Run all tests with automated pass/fail reporting
cd testbench
./run_all_tests.sh
```

This executes all module and system tests, generating detailed reports in `testbench/test_results/`.

#### Run Individual Tests
```bash
cd testbench

# Module tests (unit testing)
iverilog -g2009 -o sim_test tb_spi_master.v ../*.v && vvp sim_test
iverilog -g2009 -o sim_test tb_frame_packer.v ../*.v && vvp sim_test
iverilog -g2009 -o sim_test tb_manchester_encoder.v ../*.v && vvp sim_test
iverilog -g2009 -o sim_test tb_cdr.v ../*.v && vvp sim_test
iverilog -g2009 -o sim_test tb_frame_sync.v ../*.v && vvp sim_test

# System test (end-to-end with scoreboard verification)
iverilog -g2009 -o sim_system tb_spi_coax_system_enhanced.v ../*.v && vvp sim_system

# View waveforms
gtkwave tb_*.vcd
```

#### Test Features
- ✅ **Self-Checking**: Automatic pass/fail with assertions
- ✅ **Error Injection**: Bit errors, jitter, CRC corruption
- ✅ **Performance Measurement**: Throughput, latency, BER
- ✅ **Stress Testing**: 1000+ frame long-duration tests
- ✅ **Coverage**: ~90% functional scenarios

See [`testbench/README.md`](testbench/README.md) for detailed testing documentation.

### 3. Build Project
Open the project in Quartus Prime and compile for your specific MAX 10 target device. Ensure timing constraints (SDC) are correctly applied, especially for the 200MHz CDR clock domain.

---

## 🧪 Testing & Verification

### Production-Grade Testbench Suite

The project includes comprehensive testbenches ready for production validation:

| Test Level | Testbenches | Features |
|------------|-------------|----------|
| **Module** | SPI Master, Frame Packer, Manchester Encoder, CDR, Frame Sync | Self-checking, timing verification, data patterns, performance metrics |
| **Integration** | Encoder, Decoder | End-to-end chain validation |
| **System** | Enhanced System Test | Scoreboard verification, 1000+ frames, stress testing, latency tracking |

### Test Infrastructure

- **`tb_common.vh`**: Assertion macros, CRC calculation, error injection utilities
- **`scoreboard.vh`**: Transaction-level verification with automatic data checking
- **`run_all_tests.sh`**: Automated test execution and reporting

### Test Coverage

- ✅ Normal operation (all data patterns)
- ✅ Error conditions (CRC errors, bit errors, sync loss)
- ✅ Corner cases (jitter, backpressure, reset recovery)
- ✅ Performance validation (throughput, latency, lock time)
- ✅ Long-duration stress (1000+ frames)

### Expected Test Results

All tests should report `RESULT: PASSED` with performance metrics within specifications:

```
========================================
PERFORMANCE METRICS
========================================
Data Throughput:     22.85 Mbps
Frame Rate:          714000 frames/sec
CDR Lock Time:       < 20ms
Match Rate:          100%
========================================
```

---

## 📂 Project Structure

```text
spi-coax/
├── assets/                      # Images and visual assets
├── docs/                        # Detailed documentation
│   ├── PROJECT_INDEX.md         # Complete system documentation
│   └── ...
├── testbench/                   # Production-grade testbenches
│   ├── tb_common.vh             # Common test utilities
│   ├── scoreboard.vh            # Transaction verification
│   ├── run_all_tests.sh         # Automated test runner
│   ├── README.md                # Testing documentation
│   ├── tb_spi_master.v          # SPI Master tests
│   ├── tb_frame_packer.v        # Frame Packer tests
│   ├── tb_manchester_encoder.v  # Manchester Encoder tests
│   ├── tb_cdr.v                 # CDR tests
│   ├── tb_frame_sync.v          # Frame Sync tests
│   ├── tb_encoder.v             # Encoder integration tests
│   ├── tb_decoder.v             # Decoder integration tests
│   └── tb_spi_coax_system_enhanced.v # System tests
├── spi_master_rhs2116.v         # SPI Master Controller
├── rhs2116_link_encoder.v       # Transmit Top Level
├── rhs2116_link_decoder.v       # Receive Top Level
├── frame_packer_100m.v          # Frame Assembly & CRC
├── manchester_encoder_100m.v    # Manchester Encoder
├── cdr_4x_oversampling.v        # Clock Data Recovery
├── frame_sync_100m.v            # Frame Synchronization
├── async_fifo_generic.v         # Async FIFO for CDC
└── top.v                        # System Loopback Top
```

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

