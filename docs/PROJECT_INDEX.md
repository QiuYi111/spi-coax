# Project Index: RHS2116 Single-Wire Digital Link System

Generated: 2025-11-19
**Project**: RHS2116 Single-Wire Digital Link System
**Technology**: Verilog HDL for FPGA Implementation

## 📁 Project Structure

```
spi-coax/
├── 📋 Documentation (docs/)
│   ├── RECONSTRUCTION_PLAN.md          # System reconstruction strategy
│   ├── RECONSTRUCTION_PLAN_CONSERVATIVE.md  # Conservative approach
│   ├── RECONSTRUCTION_SUMMARY.md       # Implementation summary
│   ├── CODE_QUALITY_ANALYSIS.md        # Code review and analysis
│   ├── test_guide.md                   # Testing procedures
│   └── plan.md                         # Development planning
│
├── 🔧 Core System Modules
│   ├── top.v                           # System top-level (loopback)
│   ├── spi_master_rhs2116.v            # SPI master controller
│   ├── rhs2116_link_encoder.v          # Transmit side top-level
│   ├── rhs2116_link_decoder.v          # Receive side top-level
│   └── async_fifo_generic.v            # Clock domain crossing FIFO
│
├── 📡 Data Path Components
│   ├── frame_packer_100m.v             # Frame assembly & CRC
│   ├── manchester_encoder_100m.v       # Manchester encoding
│   ├── cdr_4x_oversampling.v           # Clock data recovery
│   └── frame_sync_100m.v               # Frame synchronization
│
├── 🧪 Testbench
│   └── testbench/
│       └── tb_spi_coax_system.v        # System-level testbench
│
└── 📚 Archive (deprecated/old versions)
    └── archive/
        ├── async_fifo.v
        ├── frame_packer_80m.v
        ├── frame_sync.v
        ├── manchester_decoder_serial.v
        ├── manchester_encoder_serial.v
        ├── soft_cdr.v
        ├── spi_coax_decoder.v
        └── spi_coax_encoder.v
```

## 🎯 System Overview

This project implements a complete single-wire digital link system for transmitting RHS2116 SPI sensor data over a coaxial cable using Manchester encoding with Power-over-Coax (PoC) support. The system achieves 22.85 Mbps payload data rate over 1-3 meters distance.

### Key Specifications
- **Data Rate**: 714 kS/s × 32-bit = 22.85 Mbps payload
- **Line Rate**: 50 Mbps Manchester encoded (100 MHz symbol rate)
- **Frame Format**: 56-bit frames {SYNC(8), CNT(8), DATA(32), CRC(8)}
- **Clocks**: 64MHz SPI, 100MHz System, 200MHz CDR
- **Distance**: 1-3 meters over coaxial cable
- **Target**: MAX 10 FPGA implementation

## 🚀 Entry Points

### System Level
- **`top.v`** - Complete system with encoder/decoder loopback for testing
- **`rhs2116_link_encoder.v`** - Transmit side top-level module
- **`rhs2116_link_decoder.v`** - Receive side top-level module

### Test Entry
- **`testbench/tb_spi_coax_system.v`** - System-level simulation with sensor model

### System Architecture

### Transmit Side (Sensor End)
```
RHS2116 → SPI Master (64MHz) → Async FIFO → Frame Packer (100MHz) → Manchester Encoder (100MHz) → Coax
```

### Receive Side (Remote End)
```
Coax → CDR (200MHz) → Frame Sync (100MHz) → Async FIFO → Data Output
```

## ⏱️ Clock Domain Architecture

### Transmit Side (Encoder)
```
64MHz SPI Domain (clk_spi)
├── spi_master_rhs2116.v
└── async_fifo_generic (write side)
    ↓ CDC via Async FIFO
100MHz System Domain (clk_sys)
├── frame_packer_100m.v
├── manchester_encoder_100m.v
└── rhs2116_link_encoder.v
```

### Receive Side (Decoder)
```
200MHz CDR Domain (clk_link)
├── cdr_4x_oversampling.v
└── async_fifo_generic (write side)
    ↓ CDC via Async FIFO
100MHz System Domain (clk_sys)
├── frame_sync_100m.v
└── rhs2116_link_decoder.v
```

### System Level (top.v)
```
- clk_spi: 64MHz (SPI Master)
- clk_sys: 100MHz (System/Link Logic)
- clk_link: 200MHz (CDR Oversampling)
```

## 📦 Core Modules Analysis

### 1. SPI Master Module (`spi_master_rhs2116.v`)
**Clock Domain:** 64 MHz (`clk_spi`)
**Interface:**
- **Inputs:** `clk_spi`, `rst_n`, `enable`, `miso`
- **Outputs:** `cs_n`, `sclk`, `mosi`, `data_out[31:0]`, `data_valid`
- **Key Parameters:** 64MHz → 16MHz SCLK, Mode 1 (CPOL=0, CPHA=1)

**Timing Relationships:**
- Generates 16 MHz SPI clock from 64 MHz input (divide by 4)
- 32-bit data frames with 16-cycle CS gaps
- Discards first 2 frames (RHS2116 latency compensation)
- Continuous channel polling (0-15) with CONVERT commands
- Data Rate: 446.4k frames/sec (16 channels @ 16MHz SCLK)

### 2. Async FIFO (`async_fifo_generic.v`)
**Clock Domains:** 64 MHz write → 100 MHz read (in frame_packer) / 200MHz write → 100MHz read (in decoder)
**Interface:**
- **Write Port:** `clk_wr`, `rst_wr_n`, `din[31:0]`, `wr_en`, `full`, `almost_full`
- **Read Port:** `clk_rd`, `rst_rd_n`, `dout[31:0]`, `rd_en`, `empty`, `valid`
- **Parameters:** `DATA_WIDTH=32`, `ADDR_WIDTH=4` (16-depth)

**Critical Features:**
- Gray code pointer synchronization
- ASYNC_REG attributes for CDC protection
- Almost-full flag for flow control (threshold: 14/16 entries)
- Safe clock domain crossing with double flip-flop sync

### 3. Frame Packer (`frame_packer_100m.v`)
**Clock Domain:** 100 MHz (`clk_sys`)
**Interface:**
- **Input:** `clk_spi`, `din[31:0]`, `din_valid` (64MHz domain)
- **Output:** `tx_bit`, `tx_bit_valid`, `tx_bit_ready`, `frame_count[7:0]`
- **Frame Format:** 56-bit → `{SYNC(8'hAA), CNT(8), DATA(32), CRC(8)}`

**Timing Sequence:**
```
1. Internal Async FIFO bridges 64MHz → 100MHz domains
2. Assemble frame: SYNC + counter + data + CRC-8 (poly 0x07)
3. Serial output: 56 bits MSB-first with ready/valid handshake
4. Bit rate: 25 Mbps (data) → 50 Mbps (Manchester)
```

### 4. Manchester Encoder (`manchester_encoder_100m.v`)
**Clock Domain:** 100 MHz (`clk_sys`)
**Interface:**
- **Input:** `bit_in`, `bit_valid`, `tx_en`
- **Output:** `bit_ready`, `ddr_p`, `ddr_n` (differential)

**Encoding Timing:**
- 4 clock cycles per bit (25 Mbps → 100 MHz)
- Encoding: bit=0 → 0→1 transition, bit=1 → 1→0 transition
- Differential DDR output with complement
- Ready/valid handshake protocol

### 5. Clock Data Recovery (`cdr_4x_oversampling.v`)
**Clock Domain:** 200 MHz (`clk_link`)
**Interface:**
- **Input:** `manch_in`, `rst_n`
- **Output:** `bit_out`, `bit_valid`, `locked`

**Critical Timing:**
- 4x oversampling (200 MHz for ~50 Mbps Manchester)
- Phase quality tracking with adaptive selection
- 3-state lock detection: UNLOCKED/LOCKING/LOCKED
- Lock: 32 consecutive valid transitions required
- Tracking range: ±150 ppm for clock drift compensation

### 6. Frame Synchronization (`frame_sync_100m.v`)
**Clock Domain:** 100 MHz (`clk_sys`)
**Interface:**
- **Input:** `bit_in`, `bit_valid` (from CDR)
- **Output:** `data_out[31:0]`, `data_valid`, `frame_error`, `sync_lost`

**Synchronization Process:**
```
1. SEARCH: Look for SYNC pattern (0xAA) in sliding window
2. SYNC: Accumulate 56 bits for complete frame
3. VERIFY: Validate CRC-8 and frame counter continuity
4. Output: 32-bit data when valid frame detected
5. Error handling: Auto-resync after 8 consecutive CRC errors
```

## 🔄 Data Flow & Timing Sequence

### Transmit Path (Sensor → Coax)
1. **SPI Acquisition** (64MHz domain)
   - RHS2116 sensor polled via SPI (Mode 1, CPOL=0, CPHA=1)
   - 32-bit data @ 446.4k frames/sec
   - Channels 0-15 polled sequentially

2. **Clock Domain Crossing**
   - Async FIFO bridges 64MHz → 100MHz domains
   - 16-depth buffering prevents data loss
   - Gray code pointer synchronization ensures safety

3. **Frame Assembly** (100MHz domain)
   - 32-bit data + 8-bit counter + 8-bit CRC-8
   - SYNC byte (0xAA) prepended
   - 56-bit total frame length

4. **Manchester Encoding** (100MHz domain)
   - Serial: 25 Mbps data rate
   - Manchester: 50 Mbps line rate (100MHz DDR)
   - 4 clock cycles per bit

### Receive Path (Coax → Data Out)
1. **Clock Data Recovery** (200MHz domain)
   - 4x oversampling (~50 Mbps Manchester)
   - Edge detection and phase tracking
   - Lock detection with 3-state FSM

2. **Frame Synchronization** (100MHz domain)
   - SYNC pattern detection (0xAA)
   - CRC-8 validation
   - Frame counter continuity check

3. **Clock Domain Crossing**
   - Async FIFO bridges CDR → System domains
   - Handles rate matching and buffering

## 🔧 Top-Level Integration

### Encoder (`rhs2116_link_encoder.v`)
**Clock Requirements:** 64 MHz, 100 MHz (phase-aligned)
**Data Flow:**
```
RHS2116_SPI → frame_packer_100m (with internal async_fifo) → manchester_encoder_100m → ddr_p/n
```
**Status Signals:** `link_active`, `frame_count[7:0]`

### Decoder (`rhs2116_link_decoder.v`)
**Clock Requirements:** 200 MHz, 100 MHz
**Data Flow:**
```
manch_in → cdr_4x_oversampling → frame_sync_100m → async_fifo_generic → data_out[31:0]
```
**Status Signals:** `cdr_locked`, `frame_error`, `sync_lost`

## 🧪 Test Coverage

### System Testbench
- **File**: `testbench/tb_spi_coax_system.v`
- **Coverage**: Full system loopback with sensor model
- **Features**:
  - Multi-clock domain (64MHz/100MHz/200MHz)
  - RHS2116 sensor behavior simulation
  - CDR lock monitoring
  - Frame validation and error checking

### Test Scenarios
- System initialization and reset
- CDR lock acquisition
- Continuous data transmission
- Frame error injection
- Clock domain crossing stress testing

### Critical Timing Constraints
- **200MHz CDR logic**: Most timing critical path
- **Clock relationships**: Phase alignment recommended
- **I/O timing**: DDR output requires proper constraints

## 🔗 Module Interconnection Matrix

| Source Module | Target Module | Interface Type | Clock Relationship |
|---------------|---------------|----------------|-------------------|
| spi_master | async_fifo | Data + Valid | Same domain (24 MHz) |
| async_fifo | frame_packer | Data + Ready/Valid | Async (24→80 MHz) |
| frame_packer | manchester_encoder | Bit stream + Ready/Valid | Same domain (80→160 MHz) |
| soft_cdr | frame_sync | Bit stream + Ready/Valid | Sync (240→80 MHz) |

## 📊 Performance Characteristics

### Latency Analysis
- **SPI Acquisition:** 32 clocks @ 24 MHz = 1.33 μs
- **FIFO Crossing:** 2-3 cycles @ 80 MHz = 25-37.5 ns
- **Frame Packing:** 56 cycles @ 80 MHz = 700 ns
- **Manchester Encoding:** 112 cycles @ 160 MHz = 700 ns
- **Total TX Latency:** ~2.8 μs

### Resource Requirements (MAX 10)
- **Logic Elements:** ~2,000 LEs (estimated)
- **Memory Bits:** ~2,048 (FIFO)
- **PLLs:** 1 (for clock generation)
- **GPIO:** 4 (SPI) + 1 (Coax) per side

## 🧪 Verification Strategy

### Test Points
1. **SPI Data Integrity:** Monitor `spi_data_valid` and `spi_data_out`
2. **FIFO Status:** Check `wr_almost_full` for throttling
3. **Frame Counter:** Validate `frame_count` continuity
4. **CDR Lock:** Monitor `phase_locked` and `phase_error_cnt`
5. **CRC Errors:** Track `frame_error` occurrences

### Critical Scenarios
- **Phase Drift:** 240 MHz sampling must track 80 Mbps data
- **FIFO Overflow:** SPI rate vs. link rate mismatch
- **Frame Loss:** SYNC pattern corruption detection
- **Clock Jitter:** 3x oversampling tolerance analysis

## 📝 Design Notes

### Key Design Decisions
1. **80 Mbps Line Rate:** Provides 16% margin over theoretical 68.54 Mbps
2. **3x Oversampling:** Balances complexity vs. jitter tolerance
3. **48-bit Frame:** Optimal overhead ratio (33% vs 50% for smaller frames)
4. **CRC-8:** Adequate error detection with minimal overhead

### Risk Mitigation
- **240 MHz Timing:** Use pipelining and timing constraints
- **Clock Domain Crossing:** Gray code pointers with double synchronization
- **Phase Tracking:** Adaptive CDR with error threshold adjustment
- **Frame Synchronization:** Redundant SYNC pattern with CRC validation

This index provides a comprehensive view of the system architecture, timing relationships, and module interfaces for the RHS2116 single-wire digital link implementation.