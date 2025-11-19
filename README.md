# RHS2116 Single-Wire Digital Link System

## Overview
This is a complete FPGA-based solution for transmitting RHS2116 SPI data over a single coaxial cable using Manchester encoding with Power-over-Coax (PoC) support.

## System Architecture

### Transmit Side (Sensor End)
```
RHS2116 → SPI Master → Async FIFO → Frame Packer → Manchester Encoder → Coax
```

### Receive Side (Remote End)
```
Coax → Soft CDR → Manchester Decoder → Frame Sync → Data Output
```

## Key Features
- **Data Rate**: 714 kS/s × 32-bit = 22.85 Mbps payload
- **Line Rate**: 80 Mbps Manchester encoded (160 MHz symbol rate)
- **Frame Format**: 48-bit frames (8-bit SYNC + 8-bit CNT + 32-bit DATA + 8-bit CRC)
- **Clocks**: 24 MHz SPI, 80 MHz link, 160/240 MHz Manchester
- **Distance**: 1-3 meters over coaxial cable
- **PoC**: Power and data sharing same cable

## File Structure

### Core Modules
- `spi_master_rhs2116.v` - SPI master for RHS2116 chip
- `async_fifo.v` - Clock domain crossing FIFO
- `frame_packer_80m.v` - Frame formatting with CRC
- `manchester_encoder_serial.v` - Manchester encoding
- `soft_cdr.v` - Clock and data recovery
- `manchester_decoder_serial.v` - Manchester decoding
- `frame_sync.v` - Frame synchronization and CRC check

### Top Level
- `spi_coax_encoder.v` - Complete transmit side
- `spi_coax_decoder.v` - Complete receive side

## Usage

### Encoder (Transmit Side)
```verilog
spi_coax_encoder u_encoder (
    .clk_spi(clk_24m),
    .clk_link(clk_80m),
    .clk_manch(clk_160m),
    .rst_n(reset_n),
    .enable(tx_enable),
    // RHS2116 SPI
    .cs_n(rhs_cs_n),
    .sclk(rhs_sclk),
    .mosi(rhs_mosi),
    .miso(rhs_miso),
    // Output
    .coax_out(tx_coax)
);
```

### Decoder (Receive Side)
```verilog
spi_coax_decoder u_decoder (
    .clk_240m(clk_240m),
    .clk_link(clk_80m),
    .rst_n(reset_n),
    .coax_in(rx_coax),
    // Output data
    .data_out(recv_data),
    .data_valid(recv_valid),
    .data_ready(recv_ready),
    // Status
    .cdr_locked(locked),
    .frame_error(frame_err),
    .sync_lost(lost_sync)
);
```

## Clock Requirements
- **Encoder**: 24 MHz, 80 MHz, 160 MHz
- **Decoder**: 80 MHz, 240 MHz
- All clocks should be phase-aligned for best performance

## Critical Timing Notes
- 240 MHz receiver clock is timing critical
- Use proper timing constraints
- Consider pipelining for 240 MHz logic
- Input buffering recommended for receiver

## Status Signals
### Encoder
- `fifo_full` - FIFO is full (throttle SPI)
- `fifo_empty` - FIFO is empty
- `frame_count` - Current frame counter
- `link_active` - Encoder is active

### Decoder
- `cdr_locked` - CDR has achieved lock
- `frame_error` - CRC error detected
- `sync_lost` - Frame synchronization lost
- `phase_error_cnt` - CDR phase error counter

## Design Notes
This implementation follows the original design report architecture while adding:
- Proper clock domain crossing
- Status monitoring
- Timing optimization suggestions
- Clean module interfaces

The system is designed for MAX 10 FPGA implementation with careful attention to timing closure at 240 MHz.