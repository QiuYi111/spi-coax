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
    reg [5:0]  bit_cnt;         // 0..31，按"上升沿数量"计数

    // 当前要发送的通道号（0..15）
    reg [3:0] curr_chan;

    // 已完成的命令计数，用于丢弃前两帧（RHS2116 结果延迟两帧）
    reg [15:0] frame_cnt;

    // 为了正确识别"新值的 SCLK"，使用 sclk_next 而不是直接用 sclk
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
                // - sclk_next = 1：新值为高电平 → "上升沿" → 采样 MISO
                // - sclk_next = 0：新值为低电平 → "下降沿" → 更新 MOSI
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
                                // 注意：这里用的是"当前 shifter_tx[31] 作为下一 bit"
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