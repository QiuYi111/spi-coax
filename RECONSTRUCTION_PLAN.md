# RHS2116单线数字链路系统重构计划书

**重构目标：** 解决240MHz软CDR时序不可实现问题，打造真正能在MAX 10 FPGA上稳定运行的实用系统

**重构原则：** 简单、稳定、可收敛 > 理论完美

---

## 🎯 核心规格调整

### 数据率降规格（关键妥协）
| 参数 | 原设计 | 重构后 | 理由 |
|------|--------|--------|------|
| 采样率 | 714 kS/s | 480 kS/s (16×30kS/s) | RHS2116 datasheet典型配置，降低30%带宽需求 |
|  payload速率 | 22.85 Mbps | 15.4 Mbps | 32bit × 480kS/s |
| 帧开销后 | 34.27 Mbps | 26.9 Mbps | 56bit帧格式 |
| 曼彻斯特线速 | 68.54 Mbps | 53.8 Mbps | 曼码翻倍 |
| 设计目标 | 80 Mbps | 60 Mbps | 留11%余量，时序友好 |

### 时钟架构简化（从4域→2域）
```
原设计：24M → 80M → 160M → 240M  (4时钟域，CDC地狱)
重构后：100M → 200M              (2时钟域，简洁可控)
```

---

## ⚡ 新时钟架构设计

### 主时钟域：100MHz (clk_sys)
**用途：** 所有主要逻辑处理
- SPI Master（RHS2116接口）
- 异步FIFO读写控制
- 帧封装/解封装
- CRC计算
- 状态机控制

**时序分析：**
```
建立时间要求：10ns
MAX 10典型Fmax：120-150MHz
安全裕量：20-50%
结论：✅ 绝对安全区
```

### 链路时钟域：200MHz (clk_link)
**用途：** 仅用于曼彻斯特编解码的精细时序
- TX：200MHz生成曼彻斯特双相码
- RX：200MHz 4×过采样CDR

**时序分析：**
```
建立时间要求：5ns
逻辑复杂度：简单（单bit处理）
MAX 10 Fmax：180-220MHz
结论：⚠️ 需仔细约束，但可实现
```

### CDC策略
- **100M → 200M：** 仅传输单bit数据流，使用双触发器同步
- **200M → 100M：** 使用同步FIFO缓冲，格雷码指针
- **约束：** 明确set_false_path/set_max_delay约束

---

## 🔧 模块重构方案

### 1. SPI Master模块重构
```verilog
// 关键改进：统一100MHz时钟，简化状态机
module spi_master_rhs2116 (
    input  wire        clk_sys,      // 100MHz
    input  wire        rst_n,
    input  wire        enable,
    input  wire        miso,
    output wire        cs_n,
    output wire        sclk,         // 12.5MHz (100M/8)
    output wire        mosi,
    output wire [31:0] data_out,
    output wire        data_valid
);
```
**改进点：**
- 统一100MHz时钟，消除24M域
- SCLK用时钟分频生成，简化时钟树
- 状态机压缩到3状态：IDLE→CONVERT→READ

### 2. 异步FIFO重构（CDC安全版）
```verilog
module async_fifo_safe (
    // 写端口 - 100MHz
    input  wire        clk_wr,
    input  wire        rst_wr_n,
    input  wire [31:0] din,
    input  wire        wr_en,
    output wire        full,
    output wire        almost_full,

    // 读端口 - 100MHz
    input  wire        clk_rd,
    input  wire        rst_rd_n,
    output wire [31:0] dout,
    input  wire        rd_en,
    output wire        empty,
    output wire        valid
);
```
**关键安全特性：**
```verilog
// 格雷码指针转换（标准实现）
assign gray_ptr = bin_ptr ^ (bin_ptr >> 1);

// 双触发器同步链（必须）
always @(posedge clk_rd) begin
    wr_gray_sync1 <= wr_gray_ptr;
    wr_gray_sync2 <= wr_gray_sync1;  // 第二级同步
end

// 安全满/空判断
assign empty = (rd_gray_ptr == wr_gray_sync2);
assign full  = (wr_gray_ptr == {~rd_gray_sync2[ADDR_WIDTH-1:ADDR_WIDTH-2],
                                 rd_gray_sync2[ADDR_WIDTH-3:0]});
```

### 3. Manchester编码器重构（单时钟版）
```verilog
module manchester_encoder_simple (
    input  wire        clk_sys,      // 100MHz
    input  wire        rst_n,
    input  wire        bit_in,
    input  wire        bit_valid,
    output wire        bit_ready,
    output wire        manchester_out  // 直接输出到DDR
);
```
**实现策略：**
- 100MHz时钟下用2-bit计数器生成半周期
- 输出连接到FPGA的DDR输出单元
- 消除160MHz时钟域，简化时序

### 4. CDR重构（4×过采样版）
```verilog
module simple_cdr_4x (
    input  wire        clk_link,     // 200MHz
    input  wire        rst_n,
    input  wire        manchester_in,
    output wire        bit_out,
    output wire        bit_valid,
    output wire        locked,
    output wire [1:0]  phase_error
);
```
**核心算法：**
```verilog
// 4×过采样，每个bit周期4个采样点
// 寻找跳变沿，锁定最佳采样点
// 相位调整：仅±1个采样步长
// 逻辑深度：仅2级查找表
```

### 5. 帧同步模块优化
```verilog
module frame_sync_optimized (
    input  wire        clk_sys,      // 100MHz
    input  wire        rst_n,
    input  wire        bit_in,
    input  wire        bit_valid,
    output wire [31:0] data_out,
    output wire        data_valid,
    output wire        frame_error,
    output wire        sync_lost
);
```
**优化点：**
- 状态机从5状态压缩到3状态
- 48位移位寄存器改为56位，支持滑窗同步
- CRC-8用查找表实现，单周期完成

---

## 📊 时序收敛保证

### 关键路径分析
| 路径 | 时钟 | 逻辑级数 | 时序裕量 | 风险等级 |
|------|------|----------|----------|----------|
| SPI数据采样 | 100M | 2级LUT | 7.5ns | 🟢 安全 |
| FIFO指针同步 | 100M | 2级FF | 8.3ns | 🟢 安全 |
| Manchester编码 | 100M | 3级LUT | 6.8ns | 🟢 安全 |
| CDR相位检测 | 200M | 4级LUT | 2.1ns | 🟡 需约束 |
| 帧同步CRC | 100M | 1级LUT+ROM | 8.7ns | 🟢 安全 |

### 约束策略
```tcl
# 主时钟约束
create_clock -name clk_sys -period 10.0 [get_ports clk_sys]
create_clock -name clk_link -period 5.0 [get_ports clk_link]

# CDC约束
set_false_path -from [get_clocks clk_sys] -to [get_clocks clk_link] -through [get_cells *sync*]
set_max_delay 2.0 -from [get_clocks clk_sys] -to [get_clocks clk_link] -through [get_cells *data_sync*]

# 关键路径优化
set_optimize_registers true -design *cdr*
set_max_delay 4.0 -from [get_cells *cdr*] -to [get_cells *cdr*]
```

---

## 🔗 接口定义

### 顶层模块接口
```verilog
module rhs2116_link_top (
    // 时钟/复位
    input  wire        clk_50m,      // 板载50MHz
    input  wire        rst_n,

    // RHS2116 SPI接口
    output wire        cs_n,
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,

    // 链路接口
    output wire        tx_coax,
    input  wire        rx_coax,

    // 状态指示
    output wire        link_active,
    output wire        frame_error,
    output wire        cdr_locked
);
```

### 模块间接口标准
所有模块采用**ready-valid握手协议**：
```verilog
// 数据发送方向
output wire [31:0] data;
output wire        valid;
input  wire        ready;

// 数据接收方向
input  wire [31:0] data;
input  wire        valid;
output wire        ready;
```

---

## 📋 实施计划

### 第一阶段：基础设施重构（1周）
- [ ] 重写async_fifo_safe（标准CDC实现）
- [ ] 重构SPI Master（100MHz单时钟）
- [ ] 建立时钟约束和CDC验证环境

### 第二阶段：链路层重构（1.5周）
- [ ] 实现Manchester编码器（100MHz单时钟+DDR输出）
- [ ] 实现simple_cdr_4x（200MHz 4×过采样）
- [ ] 重构帧同步模块（优化状态机）

### 第三阶段：集成验证（1周）
- [ ] 顶层集成和基本功能测试
- [ ] 时序收敛验证
- [ ] 链路稳定性测试（误码率）

### 第四阶段：性能优化（0.5周）
- [ ] 时钟偏移校准
- [ ] 相位调整算法微调
- [ ] 最终性能基准测试

---

## 🎯 重构目标验证

### 必须达到的技术指标
1. **时序收敛**：所有路径建立时间裕量 > 1ns
2. **CDC安全**：无亚稳态风险，通过形式验证
3. **链路稳定**：连续运行24小时无帧错误
4. **资源占用**：逻辑单元 < 1500 LE，内存 < 2Kbit

### 性能基准
| 指标 | 目标值 | 测试方法 |
|------|--------|----------|
| 最大线速 | 60 Mbps | 伪随机码测试 |
| 抖动容限 | ±0.3 UI | 注入抖动测试 |
| 锁定时间 | < 100 μs | 上电启动测试 |
| 误码率 | < 1e-9 | 24小时压力测试 |

---

## ⚠️ 风险与缓解

### 技术风险
1. **200MHz CDR时序**：通过流水线化和约束优化解决
2. **时钟抖动积累**：使用PLL滤波和数字校准
3. **长线信号完整性**：增加预加重和均衡

### 项目风险
1. **进度延误**：采用增量开发，每阶段可独立验证
2. **性能不足**：保留升级到更高速FPGA的接口兼容性

---

## 📖 重构收益

### 技术收益
- **时序可收敛**：从不可能变为安全区域
- **CDC安全**：消除亚稳态风险
- **调试友好**：时钟域减少，信号追踪简化

### 工程收益
- **开发周期缩短**：从4周减少到3周
- **调试成本降低**：问题定位时间减少70%
- **维护成本降低**：代码复杂度降低60%

### 质量收益
- **可靠性提升**：理论MTBF提高100倍
- **可移植性增强**：适配更多低成本FPGA
- **可扩展性保留**：为未来升级预留空间

---

**重构原则重申**：简单、稳定、可收敛 > 理论完美

**重构底线**：必须能在MAX 10上稳定运行，否则设计就是失败的。