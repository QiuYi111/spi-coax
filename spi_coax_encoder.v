// ============================================================================
// SPI-Coax Encoder Top Level
// RHS2116 SPI to Single-Wire Manchester Encoder
// ============================================================================
// 功能：将RHS2116的SPI数据转换为单线曼彻斯特编码信号
// 时钟：
//   - clk_spi: 24MHz (SPI时钟)
//   - clk_link: 80MHz (链路时钟)
//   - clk_manch: 160MHz (曼彻斯特编码时钟)
// ============================================================================
module spi_coax_encoder #(
    parameter CLK_DIV_SPI       = 2,    // SPI时钟分频 (96MHz/2/2 = 24MHz)
    parameter CS_GAP_CYCLES     = 16,   // CS间隔周期
    parameter FIFO_ADDR_WIDTH   = 6,    // FIFO深度: 64 (2^6)
    parameter SYNC_BYTE         = 8'hA5,
    parameter CRC_POLY          = 8'h07,
    parameter CRC_INIT          = 8'h00,
    parameter IDLE_LEVEL        = 1'b0
)(
    // 时钟和复位
    input  wire clk_spi,        // 24MHz SPI时钟
    input  wire clk_link,       // 80MHz 链路时钟
    input  wire clk_manch,      // 160MHz 曼彻斯特编码时钟
    input  wire rst_n,          // 全局复位 (低有效)

    // 控制信号
    input  wire enable,         // 1: 开始编码，0: 停止

    // RHS2116 SPI接口
    output wire cs_n,
    output wire sclk,
    output wire mosi,
    input  wire miso,

    // 单线输出 (曼彻斯特编码)
    output wire coax_out,

    // 状态输出
    output wire fifo_full,
    output wire fifo_empty,
    output wire [7:0] frame_count,
    output wire link_active
);

    // 内部信号
    wire [31:0] spi_data;
    wire        spi_data_valid;
    wire        spi_data_ready;

    wire [31:0] fifo_dout;
    wire        fifo_rd_en;
    wire        fifo_wr_en;
    wire        fifo_almost_full;

    wire        tx_bit;
    wire        tx_bit_valid;
    wire        tx_bit_ready;

    wire [55:0] frame_data;
    wire        frame_valid;

    wire        manch_out;

    // SPI Master 实例
    spi_master_rhs2116 #(
        .CLK_DIV(CLK_DIV_SPI),
        .CS_GAP_CYCLES(CS_GAP_CYCLES)
    ) u_spi_master (
        .clk_spi(clk_spi),
        .rst_n(rst_n),
        .enable(enable),
        .cs_n(cs_n),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .spi_data_out(spi_data),
        .spi_data_valid(spi_data_valid)
    );

    // 异步FIFO 实例
    async_fifo #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_async_fifo (
        // 写端口 (SPI域)
        .clk_wr(clk_spi),
        .rst_wr_n(rst_n),
        .wr_en(spi_data_valid),
        .wr_data(spi_data),
        .wr_full(fifo_full),
        .wr_almost_full(fifo_almost_full),

        // 读端口 (链路域)
        .clk_rd(clk_link),
        .rst_rd_n(rst_n),
        .rd_en(fifo_rd_en),
        .rd_data(fifo_dout),
        .rd_empty(fifo_empty),
        .rd_valid()  // 内部使用
    );

    // Frame Packer 实例
    frame_packer_80m #(
        .SYNC_BYTE(SYNC_BYTE),
        .CRC_POLY(CRC_POLY),
        .CRC_INIT(CRC_INIT)
    ) u_frame_packer (
        .clk(clk_link),
        .rst_n(rst_n),
        .fifo_dout(fifo_dout),
        .fifo_empty(fifo_empty),
        .fifo_rd_en(fifo_rd_en),
        .frame_data(frame_data),
        .frame_valid(frame_valid),
        .tx_bit(tx_bit),
        .tx_bit_valid(tx_bit_valid),
        .tx_bit_ready(tx_bit_ready)
    );

    // Manchester Encoder 实例
    manchester_encoder_serial #(
        .IDLE_LEVEL(IDLE_LEVEL)
    ) u_manch_encoder (
        .clk_160m(clk_manch),
        .rst_n(rst_n),
        .bit_in(tx_bit),
        .bit_valid(tx_bit_valid),
        .bit_ready(tx_bit_ready),
        .manch_out(manch_out)
    );

    // 输出驱动
    assign coax_out = manch_out;

    // 状态输出
    assign link_active = enable;
    assign frame_count = frame_data[47:40];  // Extract frame counter from frame

endmodule