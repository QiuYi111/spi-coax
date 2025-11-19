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

### 2. Run Simulation
A system-level testbench is provided to verify the complete link (Encoder + Decoder).

```bash
# Compile and run using iverilog
cd testbench
iverilog -o sim_system tb_spi_coax_system.v ../*.v
vvp sim_system

# View waveforms
gtkwave dump.vcd
```

### 3. Build Project
Open the project in Quartus Prime and compile for your specific MAX 10 target device. Ensure timing constraints (SDC) are correctly applied, especially for the 200MHz CDR clock domain.

---

## 📂 Project Structure

```text
spi-coax/
├── assets/                 # Images and visual assets
├── docs/                   # Detailed documentation
├── testbench/              # Simulation testbenches
├── spi_master_rhs2116.v    # SPI Master Controller
├── rhs2116_link_encoder.v  # Transmit Top Level
├── rhs2116_link_decoder.v  # Receive Top Level
├── frame_packer_100m.v     # Frame Assembly & CRC
├── manchester_encoder_100m.v # Manchester Encoder
├── cdr_4x_oversampling.v   # Clock Data Recovery
├── frame_sync_100m.v       # Frame Synchronization
└── top.v                   # System Loopback Top
```

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
