# SPI-Coax System Test Guide

This guide explains how to simulate and verify the RHS2116 single-wire digital link system.

## System Overview

The system consists of:
1.  **Encoder (`rhs2116_link_encoder`)**:
    *   Master SPI interface to RHS2116 sensor.
    *   Frame packer (adds SYNC, CRC, Frame Counter).
    *   Manchester Encoder (100MHz system clock -> 50Mbps line rate).
2.  **Decoder (`rhs2116_link_decoder`)**:
    *   CDR (4x oversampling at 200MHz).
    *   Frame Sync and CRC checker.
    *   Async FIFO for clock domain crossing.

## Simulation

### Prerequisites
*   A Verilog simulator (e.g., Icarus Verilog, Vivado, ModelSim).
*   Waveform viewer (e.g., GTKWave).

### Running the Testbench

The system testbench `testbench/tb_spi_coax_system.v` simulates the full chain with a simulated SPI slave.

#### Using Icarus Verilog

1.  **Compile:**
    ```bash
    iverilog -o tb_system \
      testbench/tb_spi_coax_system.v \
      top.v \
      rhs2116_link_encoder.v \
      rhs2116_link_decoder.v \
      spi_master_rhs2116.v \
      frame_packer_100m.v \
      manchester_encoder_100m.v \
      cdr_4x_oversampling.v \
      frame_sync_100m.v \
      async_fifo_generic.v
    ```

2.  **Run:**
    ```bash
    vvp tb_system
    ```

3.  **View Waveforms:**
    Open `tb_spi_coax_system.vcd` in your viewer.

### Expected Results

You should see the following sequence in the simulation log:
1.  **Link Enable**: The system comes out of reset.
2.  **CDR Lock**: The decoder locks onto the Manchester stream.
3.  **Data Reception**: Valid frames are received with incrementing data values (simulating the sensor).

```text
Enabling Link...
CDR Locked at time ...
RX Data: 00000001 (Time: ...)
RX Data: 00000002 (Time: ...)
...
Received 10 frames successfully.
```

## Module Hierarchy

*   **`top.v`** (System Wrapper)
    *   `rhs2116_link_encoder` (TX)
        *   `spi_master_rhs2116`
        *   `frame_packer_100m`
        *   `manchester_encoder_100m`
    *   `rhs2116_link_decoder` (RX)
        *   `cdr_4x_oversampling`
        *   `frame_sync_100m`
        *   `async_fifo_generic`
