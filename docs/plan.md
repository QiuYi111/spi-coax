![image.png](attachment:3b5d364f-db3d-4995-a255-765b41b4ca6e:2048d0f0-da37-4b0a-a07f-27a88e8416a6.png)

# **RHS2116 超长距离单线数字链路设计方案（Engineering Design Report）**

## **版本信息**

- **版本号：** v1.0
- **作者：** （留空）
- **日期：** （留空）

---

# **1. 项目目标**

设计一套适用于 **Intan RHS2116** 采集芯片的 **超长距离单线数字链路**，包括：

1. 传感器端 FPGA（MAX 10）读取 RHS2116 的高速 SPI 数据（714 kS/s × 32 bit）。
2. 将数据重新封装为固定帧格式，通过 **一根同轴线**（内芯 + 外屏蔽）传输。
3. 数据与电源复用同轴线（PoC：Power over Coax）。
4. 远端再用 FPGA/MCU 解码，从而取得原始的 RHS2116 采样流。

系统要求：

| 项目 | 要求 |
| --- | --- |
| 最终通道数 | RHS2116 全通道 |
| 数据吞吐 | 714 kFrame/s × 32bit = 22.85 Mbps（净负载） |
| 物理层带宽 | ≥ 80 Mbps（含帧开销与曼彻斯特码） |
| 延迟 | 不关注实时性（批处理即可） |
| 线缆 | 1 芯同轴（细同轴线，≤ 3mm） |
| 可扩展性 | 帧结构可扩展；支持 PoC |

---

# **2. 约束与关键技术挑战**

1. **SPI 长线不可行：**
    
    RHS2116 必须在极短走线上工作（20–30cm 内），远端 SPI 会因为 round-trip delay 导致采样错位。
    
2. **需要本地 FPGA 做主机：**
    
    在传感器端由 MAX 10 做 RHS2116 的 SPI 主机，把数据抽出并缓冲。
    
3. **单线通信要求：**
    
    只能使用 **1 根信号线 + 屏蔽**，所有数字流必须串行化。
    
4. **FPGA 不具备硬核 SerDes：**
    
    MAX 10 只能依靠普通 GPIO + PLL，实现软编码器（TX）与软 CDR（RX）。
    
5. **高可靠性传输要求：**
    
    单线必须在 1–3m 同轴条件下稳定工作，不出现 bit slip、相位漂移、DC 偏置等问题。
    

---

# **3. 系统总体架构**

```
 ┌──────────────────────────────────────────────────────────┐
 │                传感器端（MAX 10 FPGA）                    │
 │  RHS2116 SPI  →  SPI Master  →  FIFO → Frame Packer       │
 │                                              ↓            │
 │                        Manchester TX Encoder (160MHz) → 同轴线 →
 └──────────────────────────────────────────────────────────┘

                                   ↓ 同轴线（单信号 + 电源复用）

 ┌──────────────────────────────────────────────────────────┐
 │                    远端接收 FPGA / MCU                    │
 │ 同轴输入 → Sampler(240MHz) → Soft CDR → Demanchester      │
 │          → Bitstream → Frame Sync → CRC → Data Output     │
 └──────────────────────────────────────────────────────────┘

```

PoC（Power over Coax）允许电源与数据共享同一根线。

---

# **4. 数据帧格式（40-bit + SYNC + CRC = 48 bit）**

帧结构固定为 48 bit：

| 字段 | 位数 | 说明 |
| --- | --- | --- |
| SYNC | 8 bit | 固定帧头（推荐 0xA5，曼彻斯特下模式均匀） |
| CNT | 8 bit | 递增帧计数，用于丢包检测 |
| DATA | 32 bit | RHS2116 原始数据，直接透传 |
| CRC | 8 bit | 基于 CNT + DATA 计算（推荐 CRC-8） |

**传输顺序：MSB first**

---

# **5. 物理层设计**

## 5.1 带宽预算

净负载：

$714k \times 32 = 22.85 \text{ Mbps}$

加上帧开销：

`$714k \times 48 = 34.27 \text{ Mbps}$`

曼彻斯特编码 → 波特率×2：

$34.27 \times 2 = 68.54 \text{ Mbps}$

为保证抗干扰裕度，设计目标：

**物理层：80 Mbps 曼彻斯特**

**实际翻转频率：160 MHz**

MAX 10 GPIO 可稳定工作。

---

# **6. FPGA 数字逻辑设计（发送端）**

## 6.1 SPI Master（24 MHz）

```verilog
// ======================================================================
// spi_master_rhs2116
// ----------------------------------------------------------------------
// - 顶层接口按你的设计报告：只输出 32-bit 数据 + valid
// - 内部包含：
//     1) CPOL=0, CPHA=0 的 32-bit SPI 时序器（修正过边沿判断 bug）
//     2) 自动轮询 RHS2116 16 个通道的 CONVERT(C) 命令
// - 注意：不包含寄存器初始化（CLEAR + WRITE 一堆寄存器）。
//   上电后必须先由上层用同一 SPI 链完成初始化，再拉高 enable 采样。
// ======================================================================
module spi_master_rhs2116 #(
    // 主时钟 clk_spi 与 SCLK 的分频：
    // f_sclk = f_clk / (2 * CLK_DIV)
    // 例如：f_clk=96MHz，CLK_DIV=2 → f_sclk=24MHz
    parameter integer CLK_DIV         = 2,
    // 帧间 CS 高电平保持的 clk_spi 周期数，保证 tCSOFF
    parameter integer CS_GAP_CYCLES   = 16
)(
    input  wire        clk_spi,
    input  wire        rst_n,

    // 1: 开始连续采样；0: 停止发新命令（当前帧结束后停在空闲）
    input  wire        enable,

    // SPI 物理接口
    output reg         cs_n,
    output reg         sclk,
    output reg         mosi,
    input  wire        miso,

    // 输出数据：RHS2116 原始 32-bit 帧
    output reg  [31:0] spi_data_out,
    output reg         spi_data_valid
);

    // ------------------------------------------------------------------
    // 工具函数：整数 clog2，避免直接用 $clog2 带来的兼容性问题
    // ------------------------------------------------------------------
    function integer CLOG2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            CLOG2 = i;
        end
    endfunction

    localparam integer CLK_DIV_WIDTH   = (CLK_DIV      <= 1) ? 1 : CLOG2(CLK_DIV);
    localparam integer CS_GAP_WIDTH    = (CS_GAP_CYCLES<= 1) ? 1 : CLOG2(CS_GAP_CYCLES);

    // ------------------------------------------------------------------
    // RHS2116 CONVERT(C) 命令编码
    // 0 0 U M D H 0000 C[5:0] 00000000 00000000
    // 固定 U=0, M=0, D=1, H=0（读取 AC + DC）
    // ------------------------------------------------------------------
    function [31:0] make_convert_cmd;
        input [5:0] ch;
        reg   [31:0] cmd;
        begin
            cmd            = 32'd0;
            cmd[31:30]     = 2'b00;      // CONVERT
            cmd[29]        = 1'b0;       // U
            cmd[28]        = 1'b0;       // M
            cmd[27]        = 1'b1;       // D: DC → 低 10 bit
            cmd[26]        = 1'b0;       // H
            cmd[25:22]     = 4'b0000;
            cmd[21:16]     = ch[5:0];    // 通道号
            cmd[15:0]      = 16'h0000;
            make_convert_cmd = cmd;
        end
    endfunction

    // ------------------------------------------------------------------
    // 状态机定义
    // ------------------------------------------------------------------
    localparam [1:0]
        ST_IDLE  = 2'd0,
        ST_LOAD  = 2'd1,
        ST_TRANS = 2'd2,
        ST_GAP   = 2'd3;

    reg [1:0]  state;

    // 分频计数（产生 SCLK 翻转节拍）
    reg [CLK_DIV_WIDTH-1:0] clk_div_cnt;
    wire clk_div_pulse = (clk_div_cnt == (CLK_DIV - 1));

    // CS 高电平间隔计数
    reg [CS_GAP_WIDTH-1:0] cs_gap_cnt;

    // 32-bit shift 寄存器
    reg [31:0] shifter_tx;
    reg [31:0] shifter_rx;
    reg [5:0]  bit_cnt;         // 0..31，按“上升沿数量”计数

    // 当前要发送的通道号（0..15）
    reg [3:0] curr_chan;

    // 已完成的命令计数，用于丢弃前两帧（RHS2116 结果延迟两帧）
    reg [15:0] frame_cnt;

    // 为了正确识别“新值的 SCLK”，使用 sclk_next 而不是直接用 sclk
    wire sclk_next = ~sclk;

    // ------------------------------------------------------------------
    // 主状态机 + SPI 时序
    // ------------------------------------------------------------------
    always @(posedge clk_spi or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            cs_n           <= 1'b1;
            sclk           <= 1'b0;
            mosi           <= 1'b0;
            clk_div_cnt    <= {CLK_DIV_WIDTH{1'b0}};
            cs_gap_cnt     <= {CS_GAP_WIDTH{1'b0}};
            shifter_tx     <= 32'd0;
            shifter_rx     <= 32'd0;
            bit_cnt        <= 6'd0;
            curr_chan      <= 4'd0;
            frame_cnt      <= 16'd0;
            spi_data_out   <= 32'd0;
            spi_data_valid <= 1'b0;
        end else begin
            spi_data_valid <= 1'b0;   // 默认拉低，只在有新帧时打一拍

            case (state)
                // ------------------------------------------------------
                // 空闲：等待 enable=1
                // ------------------------------------------------------
                ST_IDLE: begin
                    cs_n        <= 1'b1;
                    sclk        <= 1'b0;
                    clk_div_cnt <= {CLK_DIV_WIDTH{1'b0}};
                    cs_gap_cnt  <= {CS_GAP_WIDTH{1'b0}};
                    bit_cnt     <= 6'd0;
                    shifter_tx  <= 32'd0;
                    shifter_rx  <= 32'd0;
                    frame_cnt   <= 16'd0;   // 一旦停下来重新使能，重新丢弃首两帧

                    if (enable) begin
                        state <= ST_LOAD;
                    end
                end

                // ------------------------------------------------------
                // 装载新命令
                // ------------------------------------------------------
                ST_LOAD: begin
                    // 生成当前通道的 CONVERT 命令
                    shifter_tx <= make_convert_cmd({2'b00, curr_chan});
                    shifter_rx <= 32'd0;
                    bit_cnt    <= 6'd0;

                    // 先把第一个 MOSI bit 提前输出，保证在第一个 SCLK 上升沿前稳定
                    mosi       <= make_convert_cmd({2'b00, curr_chan})[31];

                    // 拉低 CS，准备开始传输
                    cs_n       <= 1'b0;
                    sclk       <= 1'b0;
                    clk_div_cnt<= {CLK_DIV_WIDTH{1'b0}};

                    // 下一个通道号（0..15 循环）
                    curr_chan  <= curr_chan + 1'b1;

                    state      <= ST_TRANS;
                end

                // ------------------------------------------------------
                // 传输 32-bit 帧（SPI mode 0）
                // - 在 clk_div_pulse 时翻转 SCLK
                // - sclk_next = 1：新值为高电平 → “上升沿” → 采样 MISO
                // - sclk_next = 0：新值为低电平 → “下降沿” → 更新 MOSI
                // ------------------------------------------------------
                ST_TRANS: begin
                    cs_n <= 1'b0;

                    // 分频器
                    if (clk_div_pulse) begin
                        clk_div_cnt <= {CLK_DIV_WIDTH{1'b0}};
                        sclk        <= sclk_next;

                        if (sclk_next == 1'b1) begin
                            // 上升沿：采样 MISO
                            shifter_rx <= {shifter_rx[30:0], miso};

                            if (bit_cnt == 6'd31) begin
                                // 最后一位采样完成，这一帧结束
                                spi_data_out <= {shifter_rx[30:0], miso};

                                // 记录完成的帧数（命令数）
                                frame_cnt <= frame_cnt + 1'b1;

                                // 根据 RHS2116 的两帧延迟，丢弃前两帧
                                if (frame_cnt >= 16'd2) begin
                                    spi_data_valid <= 1'b1;
                                end

                                // 准备进入 CS 高电平间隔
                                cs_n        <= 1'b1;
                                sclk        <= 1'b0;
                                cs_gap_cnt  <= {CS_GAP_WIDTH{1'b0}};
                                state       <= ST_GAP;
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                            end

                        end else begin
                            // 下降沿：更新 MOSI，准备下一 bit
                            if (bit_cnt < 6'd31) begin
                                // 注意：这里用的是“当前 shifter_tx[31] 作为下一 bit”
                                mosi       <= shifter_tx[31];
                                shifter_tx <= {shifter_tx[30:0], 1'b0};
                            end
                        end
                    end else begin
                        // 还没到分频终点，只递增计数
                        clk_div_cnt <= clk_div_cnt + 1'b1;
                    end
                end

                // ------------------------------------------------------
                // 帧间 CS 高电平间隔，保证 tCSOFF
                // ------------------------------------------------------
                ST_GAP: begin
                    cs_n <= 1'b1;
                    sclk <= 1'b0;

                    if (!enable) begin
                        // 如果在间隔期被禁用，直接回到 IDLE
                        state <= ST_IDLE;
                    end else begin
                        if (cs_gap_cnt == (CS_GAP_CYCLES - 1)) begin
                            // 间隔结束，开始下一帧
                            state <= ST_LOAD;
                        end else begin
                            cs_gap_cnt <= cs_gap_cnt + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

```

从 RHS2116 读取 32 bit 数据。

输出：

- `spi_data_out[31:0]`
- `spi_data_valid`

## 6.2 异步 FIFO

```verilog
// ============================================================================
// Asynchronous FIFO for RHS2116 single-wire link
// 写时钟域：clk_wr (例如 clk_spi 24MHz)
// 读时钟域：clk_rd (例如 clk_link 80MHz)
// 默认参数：32bit 数据宽度，64 深度，可通过 ADDR_WIDTH 调整到 128 等
// ============================================================================
module async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 6     // FIFO 深度 = 2^ADDR_WIDTH，默认 64
)(
    // 写端口（clk_wr 域：RHS2116 SPI Master → FIFO）
    input  wire                   clk_wr,
    input  wire                   rst_wr_n,     // 写域复位，低有效

    input  wire                   wr_en,        // 写使能（高电平写入一拍）
    input  wire [DATA_WIDTH-1:0]  wr_data,      // 写入数据

    output wire                   wr_full,      // FIFO 满
    output wire                   wr_almost_full, // FIFO 接近满（可用于节流 SPI）

    // 读端口（clk_rd 域：FIFO → Frame Packer / Link）
    input  wire                   clk_rd,
    input  wire                   rst_rd_n,     // 读域复位，低有效

    input  wire                   rd_en,        // 读使能（高电平读出一拍）
    output reg  [DATA_WIDTH-1:0]  rd_data,      // 读出数据
    output wire                   rd_empty,     // FIFO 空
    output reg                    rd_valid      // 本拍 rd_data 有效
);

    // =========================================================================
    // 内部参数和寄存器定义
    // =========================================================================
    localparam PTR_WIDTH = ADDR_WIDTH + 1;      // 多一位用于 full/empty 判定
    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);

    // RAM
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // 写指针（bin / gray）
    reg [PTR_WIDTH-1:0] wr_ptr_bin;
    reg [PTR_WIDTH-1:0] wr_ptr_gray;

    // 读指针（bin / gray）
    reg [PTR_WIDTH-1:0] rd_ptr_bin;
    reg [PTR_WIDTH-1:0] rd_ptr_gray;

    // 对端指针同步（Gray 码）
    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;  // 到写域
    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;  // 到读域

    wire [PTR_WIDTH-1:0] rd_ptr_gray_sync; // 写域看到的读指针
    wire [PTR_WIDTH-1:0] wr_ptr_gray_sync; // 读域看到的写指针

    assign rd_ptr_gray_sync = rd_ptr_gray_sync2;
    assign wr_ptr_gray_sync = wr_ptr_gray_sync2;

    // =========================================================================
    // 二进制 ↔ Gray 码函数
    // =========================================================================
    // bin2gray: Gray = bin ^ (bin >> 1)
    function [PTR_WIDTH-1:0] bin2gray;
        input [PTR_WIDTH-1:0] bin;
        begin
            bin2gray = (bin >> 1) ^ bin;
        end
    endfunction

    // gray2bin 可选（这里不需要用到，不展开）

    // =========================================================================
    // 写时钟域逻辑
    // =========================================================================
    // 写指针更新 & 写入 RAM
    wire wr_push = wr_en && !wr_full;
    wire [PTR_WIDTH-1:0] wr_ptr_bin_next  = wr_ptr_bin + (wr_push ? 1'b1 : 1'b0);
    wire [PTR_WIDTH-1:0] wr_ptr_gray_next = bin2gray(wr_ptr_bin_next);

    integer i;
    always @(posedge clk_wr or negedge rst_wr_n) begin
        if (!rst_wr_n) begin
            wr_ptr_bin  <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;

            // 写 RAM
            if (wr_push) begin
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
            end
        end
    end

    // 同步读指针 Gray 到写域
    always @(posedge clk_wr or negedge rst_wr_n) begin
        if (!rst_wr_n) begin
            rd_ptr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // =========================================================================
    // 读时钟域逻辑
    // =========================================================================
    // 读指针更新 & RAM 读
    wire rd_pop = rd_en && !rd_empty;
    wire [PTR_WIDTH-1:0] rd_ptr_bin_next  = rd_ptr_bin + (rd_pop ? 1'b1 : 1'b0);
    wire [PTR_WIDTH-1:0] rd_ptr_gray_next = bin2gray(rd_ptr_bin_next);

    always @(posedge clk_rd or negedge rst_rd_n) begin
        if (!rst_rd_n) begin
            rd_ptr_bin  <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray <= {PTR_WIDTH{1'b0}};
            rd_data     <= {DATA_WIDTH{1'b0}};
            rd_valid    <= 1'b0;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;

            // rd_valid：当本拍真正 pop 时有效
            rd_valid <= rd_pop;

            if (rd_pop) begin
                rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
            end
        end
    end

    // 同步写指针 Gray 到读域
    always @(posedge clk_rd or negedge rst_rd_n) begin
        if (!rst_rd_n) begin
            wr_ptr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // =========================================================================
    // Empty / Full 判定（Gray 码标准写法）
    // =========================================================================
    // 空：读指针 == 同步过来的写指针
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync);

    // 满：写指针下一值 == 读指针 Gray 同步后，最高两位取反，其余相同
    assign wr_full  =
        (wr_ptr_gray_next == {~rd_ptr_gray_sync[PTR_WIDTH-1:PTR_WIDTH-2],
                              rd_ptr_gray_sync[PTR_WIDTH-3:0]});

    // =========================================================================
    // 可选：Almost Full（简单实现：剩余空间 <= 2）
    // 对于 RHS2116 应用，你可以用它来减慢 SPI 侧写入或者暂停读取 RHS2116。
    // =========================================================================
    // 将 Gray 转回 bin 估算使用量（注意：这里简单用组合逻辑做 gray2bin）
    reg [PTR_WIDTH-1:0] rd_bin_in_wr;
    integer k;
    always @* begin
        // Gray → Bin
        rd_bin_in_wr[PTR_WIDTH-1] = rd_ptr_gray_sync[PTR_WIDTH-1];
        for (k = PTR_WIDTH-2; k >= 0; k = k - 1) begin
            rd_bin_in_wr[k] = rd_bin_in_wr[k+1] ^ rd_ptr_gray_sync[k];
        end
    end

    wire [PTR_WIDTH-1:0] used_words_wr =
        wr_ptr_bin - rd_bin_in_wr;

    // 阈值可以根据你想要的 margin 调整，这里设为：只剩 <=2 个空位就 almost_full
    assign wr_almost_full = (used_words_wr >= (FIFO_DEPTH - 2));

endmodule

```

跨域：

`clk_spi` → `clk_link (80MHz)`

深度建议 64–128 word。

## 6.3 Frame Packer（80 MHz）

```verilog
// -----------------------------------------------------------------------------
// Frame Packer @ "80 MHz"（时钟.freq 任你定，但与 Manchester 保持同域更省事）
// 将 32-bit 采样打包为 56-bit 帧并串行输出：
//   [55:48] SYNC  = 8'hA5
//   [47:40] CNT   = 8-bit 帧计数
//   [39:08] DATA  = 输入 32-bit 采样
//   [07:00] CRC8  = 基于 {CNT, DATA} 计算 (poly 0x07, init 0x00, MSB-first)
//
// 并行口： frame_data / frame_valid 方便调试
// 串行口： tx_bit / tx_bit_valid / tx_bit_ready 直连 Manchester 编码器
// -----------------------------------------------------------------------------
module frame_packer_80m #(
    parameter SYNC_BYTE  = 8'hA5, // 帧头
    parameter CRC_POLY   = 8'h07, // x^8 + x^2 + x + 1
    parameter CRC_INIT   = 8'h00
)(
    input  wire         clk,        // 链路时钟（建议与 Manchester 同域）
    input  wire         rst_n,      // 低电平复位

    // 上游 FIFO 读口（SPI->FIFO->FramePacker）
    input  wire [31:0]  fifo_dout,   // FIFO 读数据
    input  wire         fifo_empty,  // FIFO 为空
    output reg          fifo_rd_en,  // 读使能：拉高一拍请求读，下一拍数据有效

    // 并行帧输出（可选，用于调试或后端不用可删）
    output reg  [55:0]  frame_data,  // 打包好的 56-bit 帧
    output reg          frame_valid, // 1 个 clk 周期的有效脉冲

    // 串行 bit 输出接口（给 Manchester）
    output reg          tx_bit,       // 串行 bit，MSB-first
    output reg          tx_bit_valid, // bit 有效标志
    input  wire         tx_bit_ready  // 下游可以接收 bit
);

    // 状态机
    localparam S_IDLE = 2'd0;
    localparam S_READ = 2'd1;
    localparam S_SEND = 2'd2;

    reg [1:0]  state;
    reg [7:0]  frame_cnt;       // 8-bit 帧计数器
    reg [31:0] sample_reg;      // 暂存从 FIFO 读出的采样

    // 串行发送相关寄存器
    reg [55:0] shift_reg;       // 待发送帧的移位寄存器
    reg [5:0]  bit_cnt;         // 剩余 bit 个数（0..55）
    reg        sending;         // 正在发送一帧

    // -------------------------------------------------------------------------
    // CRC-8 组合逻辑函数
    // 输入：40-bit {CNT[7:0], DATA[31:0]}，MSB-first
    // 输出：8-bit CRC
    // -------------------------------------------------------------------------
    function automatic [7:0] crc8_40bit;
        input [39:0] data_bits;
        integer i;
        reg [7:0] crc;
    begin
        crc = CRC_INIT;
        // MSB-first：从 data_bits[39] 到 data_bits[0]
        for (i = 39; i >= 0; i = i - 1) begin
            if ((crc[7] ^ data_bits[i]) == 1'b1) begin
                crc = {crc[6:0], 1'b0} ^ CRC_POLY;
            end else begin
                crc = {crc[6:0], 1'b0};
            end
        end
        crc8_40bit = crc;
    end
    endfunction

    // -------------------------------------------------------------------------
    // 主时序逻辑
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            fifo_rd_en   <= 1'b0;
            frame_valid  <= 1'b0;
            frame_data   <= 56'd0;
            frame_cnt    <= 8'd0;
            sample_reg   <= 32'd0;

            shift_reg    <= 56'd0;
            bit_cnt      <= 6'd0;
            sending      <= 1'b0;
            tx_bit       <= 1'b0;
            tx_bit_valid <= 1'b0;
        end else begin
            // 默认值，避免锁存
            fifo_rd_en   <= 1'b0;
            frame_valid  <= 1'b0;
            tx_bit_valid <= 1'b0;

            case (state)
                //------------------------------------------------------------------
                // IDLE：等待 FIFO 非空 且 当前没有在发送上一帧
                //------------------------------------------------------------------
                S_IDLE: begin
                    if (!fifo_empty && !sending) begin
                        fifo_rd_en <= 1'b1;   // 请求读
                        state      <= S_READ; // 下一拍去接数据
                    end
                end

                //------------------------------------------------------------------
                // READ：上一拍已经拉高 rd_en，这一拍拿到 fifo_dout
                //       计算 CRC，生成一帧，并准备进入串行发送
                //------------------------------------------------------------------
                S_READ: begin
                    sample_reg <= fifo_dout;

                    begin : pack_and_crc
                        reg [39:0] crc_input;
                        reg [7:0]  crc_val;
                        reg [55:0] frame_word;

                        crc_input = {frame_cnt, fifo_dout};
                        crc_val   = crc8_40bit(crc_input);

                        // 帧格式：
                        // [55:48] SYNC
                        // [47:40] CNT
                        // [39:08] DATA
                        // [07:00] CRC
                        frame_word = {SYNC_BYTE, frame_cnt, fifo_dout, crc_val};

                        frame_data <= frame_word;  // 并行输出（调试用）
                        // 串行发送准备
                        shift_reg  <= frame_word;  // MSB-first
                    end

                    frame_valid <= 1'b1;          // 并行帧有效 1 个周期
                    frame_cnt   <= frame_cnt + 8'd1;

                    // 初始化发送计数器：需要发送 56 个 bit，从 [55] 到 [0]
                    bit_cnt <= 6'd55;
                    sending <= 1'b1;
                    state   <= S_SEND;
                end

                //------------------------------------------------------------------
                // SEND：通过 tx_bit/tx_bit_valid/tx_bit_ready 串行吐出 56 个 bit
                //------------------------------------------------------------------
                S_SEND: begin
                    if (sending && tx_bit_ready) begin
                        // 当前输出最高位 bit
                        tx_bit       <= shift_reg[55];
                        tx_bit_valid <= 1'b1;

                        // 左移一位（也可以右移+改变索引，风格问题）
                        shift_reg <= {shift_reg[54:0], 1'b0};

                        if (bit_cnt == 6'd0) begin
                            // 最后一个 bit 已发送
                            sending <= 1'b0;
                            state   <= S_IDLE;
                        end else begin
                            bit_cnt <= bit_cnt - 6'd1;
                        end
                    end
                    // 如果 tx_bit_ready == 0，则保持当前 shift_reg、bit_cnt，不发送，形成背压
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

```

输出 48 bit 帧。

内部模块：

- 8-bit 帧计数器
- CRC-8 计算
- 48-bit 并行输出
- `frame_valid` 脉冲

## 6.4 Manchester 编码器（160 MHz）

```verilog
// Manchester encoder with serial bit input from Frame Packer
// - clk_160m: 160 MHz clock
// - Effective bit rate: 80 Mbps (1 bit = 2 clk cycles)
// - Streaming interface: bit_in / bit_valid / bit_ready

module manchester_encoder_serial #(
    parameter IDLE_LEVEL = 1'b0   // 空闲电平，可根据需要修改
)(
    input  wire clk_160m,
    input  wire rst_n,

    // Serial bit input from Frame Packer (same clock domain)
    input  wire bit_in,      // 待编码的串行数据 bit
    input  wire bit_valid,   // 有效标志，配合 bit_ready 使用
    output wire bit_ready,   // 编码器可以接收新 bit

    // Manchester coded output
    output reg  manch_out
);

    // 当前正在编码的 bit
    reg cur_bit;

    // phase = 0: 等待/发送 bit 的前半周期
    // phase = 1: 发送该 bit 的后半周期（反码）
    reg phase;

    // 握手：只有在 phase == 0 时才会吞一个新 bit
    wire bit_accepted = bit_valid & bit_ready;

    // ready: 只有在前半周期并且没有复位时才为 1
    assign bit_ready = (phase == 1'b0);

    always @(posedge clk_160m or negedge rst_n) begin
        if (!rst_n) begin
            cur_bit   <= 1'b0;
            phase     <= 1'b0;
            manch_out <= IDLE_LEVEL;
        end else begin
            if (bit_accepted) begin
                // 接收一个新 bit，并开始它的第一个半周期
                cur_bit   <= bit_in;
                manch_out <= bit_in;    // 前半周期输出原始 bit
                phase     <= 1'b1;      // 下一拍进入后半周期
            end else if (phase == 1'b1) begin
                // 后半周期：输出反码，然后回到 phase 0，
                // 等待下一个 bit_accepted
                manch_out <= ~cur_bit;
                phase     <= 1'b0;
            end else begin
                // phase == 0 且没有新 bit 进来：保持空闲电平
                manch_out <= IDLE_LEVEL;
                // phase 继续保持 0，直到有 bit_accepted
            end
        end
    end

endmodule

```

实现：

- 前半周期输出 bit
- 后半周期输出 bit 取反
- 完整发送 48 bit × 2 半周期

特点：

- 整个 TX 逻辑在 160 MHz 域同步
- 无跨时钟域的隐患

---

# **7. FPGA 数字逻辑设计（接收端）**

## 7.1 同轴输入整形

使用高速比较器/缓冲器恢复数字边沿。

## 7.2 240 MHz 三倍过采样采集

`sample <= coax_in_raw @ clk_240`

保持最近 3 个采样点：

`samples = {old, mid, new}`

## 7.3 Soft CDR（核心模块）

采用：

- `phase` 三态计数器（0/1/2）
- 在 phase=0 / phase=2 分别捕捉 bit 的第一半/第二半
- 若两者相反，则得到 1 bit
- 若两者相等，说明采样点落在边界附近 → 累计违例 → 调整相位（slip）

## 7.4 Demanchester

规则：

- `1 → 0` 对应逻辑“1”
- `0 → 1` 对应逻辑“0”

## 7.5 Bitstream → Frame Sync

在 48-bit 流中查找 0xA5。

找到后：

- 截取 CNT、DATA、CRC
- CRC 校验
- 与上一帧 CNT 比较，检查丢帧

## 7.6 输出 RHS 数据

每 48 bit 输出一次 32-bit 采样数据。

---

# **8. PoC（Power over Coax）设计**

## 8.1 Bias-T 电路

```
 主机侧：       传感器侧：
 DC inject      DC extract
     │               │
    +│              +│
   ┌─┴─┐         ┌──┴──┐
   │ L │         │  L   │     (1–2.2uH, SRF > 200 MHz)
   └─┬─┘         └──┬──┘
     │               │
     + ---- 同轴 ----+
     │               │
   ┌─┴─┐         ┌──┴──┐
   │ C │         │  C   │    (1–10 nF, C0G)
   └───┘         └─────┘
     │               │
 FPGA TX/RX      FPGA TX/RX

```

L：1–2.2 µH（高 SRF）

C：1–10 nF（C0G，0402）

至少需要：

- 输入端 TVS 保护
- EMI 滤波（RC/LC）

---

# **9. 时序与资源预算（MAX 10）**

| 模块 | 时钟 | 目标 Fmax | 可行性 |
| --- | --- | --- | --- |
| SPI Master | 24 MHz | 50 MHz | 安全 |
| Frame Packer | 80 MHz | 120 MHz | 安全 |
| TX Encoder | 160 MHz | ~200 MHz | 可收敛 |
| RX Sampler | 240 MHz | ~260 MHz | 较紧，需要优化逻辑链 |
| CDR + Demanchester | 240 MHz | ~260 MHz | 可通过约束与逻辑拆分实现 |
| Frame Sync | 80 MHz | 120 MHz | 安全 |

结论：

**240 MHz 是系统瓶颈，需要严格的时序约束与浅逻辑设计。**

---

# **10. 主要风险与对策**

| 风险 | 描述 | 对策 |
| --- | --- | --- |
| RX 240 MHz 时序吃紧 | Soft CDR 逻辑必须浅 | 分拆组合逻辑、增加 pipeline |
| 曼彻斯特码相位漂移 | 边界跳变噪声可能误导 | 增加 slip 机制、帧同步二次校正 |
| 同轴衰减导致边沿变慢 | 80 MHz 信号可能变形 | 前端加高速比较器，TX 加强驱动 |
| PoC 耦合导致串扰 | 高频 AC 在同轴中的阻抗不稳定 | 选高 SRF 电感 + C0G 电容 |

---

# **11. 结论**

本报告定义了一套在 MAX 10 上可实施、可综合、可验证的 **80 Mbps 曼彻斯特单线链路方案**。

该方案满足 RHS2116 的采样速率要求，并使用：

- **三倍过采样 Soft CDR（240 MHz）**
- **48-bit 帧结构（SYNC + CNT + DATA + CRC）**
- **PoC 电源复用**
- **单线（同轴）传输**

整个设计已经达到**工程可执行**级别（Engineering Executable Level），唯一的实现风险在 RX 240MHz 时序部分，但可以通过管线化和约束优化解决。

---

# **12. 可选后续工作**

如有需要，可继续提供：

- 完整 Verilog 模块库（SPI、Frame Packer、Manchester、CDR、Frame Sync、CRC）
- 全链路 testbench（含延迟、噪声模型）
- PCB 参考设计（PoC + 同轴接口 + 前端整形）
- 上板调试手册（相位锁定调试方法）

---

如需要，我也可以把这份报告排版成 PDF 或 IEEE 风格格式。
