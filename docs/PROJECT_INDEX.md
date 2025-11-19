# Project Index: RHS2116 Single-Wire Digital Link System

Generated: 2025-11-19 15:30:00

## 📁 Project Structure

```
/Users/jingyi/spi-coax/
├── spi_master_rhs2116.v          # SPI master for RHS2116 chip
├── async_fifo_generic.v          # Clock domain crossing FIFO
├── frame_packer_80m.v            # Frame formatting with CRC
├── manchester_encoder_100m.v     # Manchester line encoding
├── soft_cdr.v                    # Clock and data recovery
├── manchester_decoder_serial.v   # Manchester line decoding
├── frame_sync.v                  # Frame synchronization and CRC check
├── spi_coax_encoder.v            # Complete transmit side (top level)
├── spi_coax_decoder.v            # Complete receive side (top level)
├── README.md                     # Technical documentation
├── plan.md                       # Engineering design report (Chinese)
└── PROJECT_INDEX.md              # This file
```

## 🚀 System Architecture

### Transmit Side (Sensor End)
```
RHS2116 → SPI Master (24MHz) → Async FIFO → Frame Packer (80MHz) → Manchester Encoder (160MHz) → Coax
```

### Receive Side (Remote End)
```
Coax → Soft CDR (240MHz) → Manchester Decoder → Frame Sync (80MHz) → Data Output
```

## 📦 Core Modules Analysis

### 1. SPI Master Module (`spi_master_rhs2116.v`)
**Clock Domain:** 24 MHz (`clk_spi`)
**Interface:**
- **Inputs:** `clk_spi`, `rst_n`, `enable`, `miso`
- **Outputs:** `cs_n`, `sclk`, `mosi`, `spi_data_out[31:0]`, `spi_data_valid`
- **Key Parameters:** `CLK_DIV=2`, `CS_GAP_CYCLES=16`

**Timing Relationships:**
- Generates 24 MHz SPI clock from 48-96 MHz input
- 32-bit data frames with 16-cycle CS gaps
- Discards first 2 frames (RHS2116 latency compensation)
- Continuous channel polling (0-15) with CONVERT commands

### 2. Async FIFO (`async_fifo.v`)
**Clock Domains:** 24 MHz write → 80 MHz read
**Interface:**
- **Write Port:** `clk_wr`, `wr_en`, `wr_data[31:0]`, `wr_full`, `wr_almost_full`
- **Read Port:** `clk_rd`, `rd_en`, `rd_data[31:0]`, `rd_empty`, `rd_valid`
- **Parameters:** `DATA_WIDTH=32`, `ADDR_WIDTH=6` (64-depth)

**Critical Features:**
- Gray code pointer synchronization
- Clock domain crossing safety
- Almost-full flag for SPI throttling
- 2-clock cycle synchronization delay

### 3. Frame Packer (`frame_packer_80m.v`)
**Clock Domain:** 80 MHz (`clk_link`)
**Interface:**
- **Input:** `fifo_dout[31:0]`, `fifo_empty`
- **Output:** `fifo_rd_en`, `tx_bit`, `tx_bit_valid`, `tx_bit_ready`
- **Frame Format:** 56-bit → `{SYNC(8), CNT(8), DATA(32), CRC(8)}`

**Timing Sequence:**
```
1. Assert `fifo_rd_en` when `!fifo_empty && !sending`
2. Read data on next cycle, calculate CRC
3. Shift out 56 bits MSB-first with ready/valid handshake
4. Update 8-bit frame counter
```

### 4. Manchester Encoder (`manchester_encoder_serial.v`)
**Clock Domain:** 160 MHz (`clk_160m`)
**Interface:**
- **Input:** `bit_in`, `bit_valid`
- **Output:** `bit_ready`, `manch_out`

**Encoding Timing:**
- 2 clock cycles per bit (80 Mbps → 160 MHz)
- Phase 0: Output original bit
- Phase 1: Output inverted bit
- Ready only during phase 0

### 5. Soft CDR (`soft_cdr.v`)
**Clock Domain:** 240 MHz (`clk_240m`)
**Interface:**
- **Input:** `manch_in`
- **Output:** `data_out`, `data_valid`, `phase_locked`, `phase_error_cnt[1:0]`

**Critical Timing:**
- 3x oversampling (240 MHz for 80 Mbps data)
- Phase tracking with 0-2 state machine
- Edge detection using 3-sample history
- Phase adjustment after 4 consecutive errors

### 6. Frame Sync (`frame_sync.v`)
**Clock Domain:** 80 MHz (`clk_link`)
**Interface:**
- **Input:** `bit_in`, `bit_valid`
- **Output:** `data_out[31:0]`, `data_valid`, `frame_error`, `sync_lost`

**Synchronization Process:**
```
1. Search for SYNC pattern (0xA5) in 48-bit shift register
2. Validate with CRC check
3. Track frame counter continuity
4. Output 32-bit data with valid flag
5. Error handling: lose sync after 8 consecutive CRC errors
```

## 🔧 Top-Level Integration

### Encoder (`spi_coax_encoder.v`)
**Clock Requirements:** 24 MHz, 80 MHz, 160 MHz (phase-aligned)
**Data Flow:**
```
RHS2116_SPI → async_fifo → frame_packer → manchester_encoder → coax_out
```
**Status Signals:** `fifo_full`, `fifo_empty`, `frame_count[7:0]`, `link_active`

### Decoder (`spi_coax_decoder.v`)
**Clock Requirements:** 240 MHz, 80 MHz
**Data Flow:**
```
coax_in → soft_cdr → manchester_decoder → frame_sync → data_out[31:0]
```
**Status Signals:** `cdr_locked`, `frame_error`, `sync_lost`, `phase_error_cnt[1:0]`

## ⚡ Critical Timing Relationships

### Clock Domain Boundaries
1. **24 MHz → 80 MHz:** Async FIFO (SPI to Link)
2. **80 MHz → 160 MHz:** Direct handshake (Frame Packer to Manchester)
3. **240 MHz → 80 MHz:** Synchronizer registers (CDR to Frame Sync)

### Data Rate Calculations
- **Payload:** 714 kS/s × 32-bit = 22.85 Mbps
- **With Overhead:** 714 kS/s × 48-bit = 34.27 Mbps
- **Manchester Rate:** 34.27 Mbps × 2 = 68.54 Mbps
- **Design Target:** 80 Mbps (16% margin)

### Timing Critical Paths
1. **240 MHz CDR:** Phase detection logic (most critical)
2. **160 MHz Encoder:** Bit phase switching
3. **80 MHz Frame Processing:** CRC calculation and bit shifting

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