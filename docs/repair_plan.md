# DDR5 IP Blocking Issues — 修复计划

> **生成日期**: 基于对 docs/ + src/ 全量代码审查  
> **问题来源**: docs/review_blocking.md (B-01 ~ B-08)  
> **修复策略**: 按严重度分 3 个 Phase，RTL 修复 + 文档修复 + 新建文件并行推进

---

## 总览：8 个问题的修复路径

| 编号 | 问题 | 严重度 | 修复类型 | 预计工时 | Phase |
|------|------|--------|----------|----------|-------|
| B-05 | 双通道地址映射缺失 | 🔴 Critical | RTL + 文档 | 2d | Phase 1 |
| B-02 | AXI4 Exclusive Access 未定义 | 🔴 Critical | RTL + 文档 | 2d | Phase 1 |
| B-01 | Gearbox 频率比错误 | 🟠 High | 文档 + RTL | 1d | Phase 1 |
| B-04 | DFI 5.1 phase 信号缺失 | 🟠 High | RTL + 文档 | 2d | Phase 2 |
| B-03 | 无死锁预防机制 | 🟡 Medium | RTL + 文档 | 2d | Phase 2 |
| B-06 | 无 RTL 编码规范 | 🟡 Medium | 新建文档 | 1d | Phase 3 |
| B-07 | 无软件驱动架构 | 🟡 Medium | 新建文档 | 2d | Phase 3 |
| B-08 | 无验证计划 (非 UVM) | 🟢 Low | 文档补全 | 2d | Phase 3 |

---

## Phase 1: 功能性缺陷修复（Critical/High）

### B-05: 双通道地址映射缺失 — 🔴 Critical

**问题根因**:  
`ddr5_addr_mapper.sv` 输出只有 row/bg/bank/col/rank，完全没有 sub-channel 选择信号。DDR5 双子通道每通道 32-bit 数据，需要地址中某一位决定访问 Sub-Channel A 还是 B，但当前设计完全缺失这一逻辑。

**修复方案**:

#### Step 1: 修改 `src/ddr5_defines.svh` — 新增子通道定义
```systemverilog
// --- Sub-Channel Parameters (新增) ---
`define DDR5_SUBCH_W        1       // Sub-channel select bit (0=A, 1=B)
`define DDR5_NUM_SUBCH      2       // Dual sub-channels
`define DDR5_DQ_PER_SUBCH   32      // Data bits per sub-channel
`define DDR5_ECC_PER_SUBCH  8       // ECC bits per sub-channel
```

#### Step 2: 修改 `src/ui/ddr5_addr_mapper.sv` — 新增 sub_channel 输出
```systemverilog
module ddr5_addr_mapper (
    input  logic [`AXI_ADDR_W-1:0]  axi_addr,
    output logic [`DDR5_ROW_W-1:0]  row_addr,
    output logic [`DDR5_BG_W-1:0]   bg_addr,
    output logic [`DDR5_BA_W-1:0]   bank_addr,
    output logic [`DDR5_COL_W-1:0]  col_addr,
    output logic [`DDR5_RANK_W-1:0] rank_addr,
    output logic                     sub_channel,  // 新增: 0=A, 1=B
    input  logic [1:0]               map_mode
);
    // Mode 0: Row-BG-Bank-Col-SubCH
    // 子通道选择 = 地址最低字节的 bit[3] (64B cache line 内的子通道切换)
    assign sub_channel = axi_addr[3];  // 每 8 字节切换子通道
    // ... 其余映射逻辑不变
```

#### Step 3: 修改 `src/ctrl/ddr5_cmd_scheduler.sv` — 传递子通道信息
- `cmd_entry_t` 结构体新增 `sub_ch` 字段
- `cmd_out` 新增 `cmd_out_sub_ch` 输出
- 地址解码时提取子通道位

#### Step 4: 修改 `src/ctrl/ddr5_protocol_fsm.sv` — 根据 sub_channel 驱动 dfi_cs_n
```systemverilog
// 当前: dfi_cs_n = 2'b00 (总是选两个通道)
// 修复后:
dfi_cs_n = sub_ch_r ? 2'b10 : 2'b01;  // 选择单个子通道
// 广播模式 (两个通道同时): dfi_cs_n = 2'b00
```

#### Step 5: 修改 `src/top/ddr5_controller.sv` — 连线 sub_channel
- UI → Ctrl Core → DFI Bridge 全链路新增 sub_channel 信号

#### Step 6: 修改 `docs/01_DDR5_IP_Arch_Overview.md` — 地址映射方案
```
用户线性地址 [33:0] (34-bit, 最大 16GB)
┌───────────────────────────────────────────────────┐
│ [33:32] Rank         (2 bit, 4 Ranks)             │
│ [31:14] Row          (18 bit, 256K rows/bank)     │
│ [13:11] Bank Group   (3 bit, 4 Bank Groups)        │
│ [10:8]  Bank         (3 bit, 8 Banks/Group)        │
│ [7:4]   Column       (4 bit, BL16 aligned)          │
│ [3]     Sub-Channel  (1 bit, 0=A, 1=B)  ← 新增     │
│ [2:0]   Byte Offset  (3 bit, 8-byte word)          │
└───────────────────────────────────────────────────┘
```

#### Step 7: 新增测试 `test/tb_ddr5_addr_mapper_subch.sv`
- 验证连续地址在子通道 A/B 间交替
- 验证子通道选择信号与 dfi_cs_n 的对应关系

**涉及文件**: `ddr5_defines.svh`, `ddr5_addr_mapper.sv`, `ddr5_cmd_scheduler.sv`, `ddr5_protocol_fsm.sv`, `ddr5_controller.sv`, `docs/01_DDR5_IP_Arch_Overview.md`

---

### B-02: AXI4 Exclusive Access 未定义 — 🔴 Critical

**问题根因**:  
`ddr5_axi4_wr_slave.sv` 和 `ddr5_axi4_rd_slave.sv` 的端口列表中完全没有 `awlock`/`arlock` 输入，`bresp` 永远输出 OKAY，无独占监视器模块。

**修复方案**:

#### Step 1: 新建 `src/ui/ddr5_exclusive_monitor.sv` — 独占访问监视器
```systemverilog
module ddr5_exclusive_monitor #(
    parameter int ID_W   = `AXI_ID_W,
    parameter int ADDR_W = `AXI_ADDR_W
)(
    input  logic              clk,
    input  logic              rst_n,
    // 写地址通道
    input  logic [ID_W-1:0]   awid,
    input  logic [ADDR_W-1:0] awaddr,
    input  logic              awlock,    // 1=exclusive
    input  logic              awvalid,
    input  logic              awready,
    // 读地址通道
    input  logic [ID_W-1:0]   arid,
    input  logic [ADDR_W-1:0] araddr,
    input  logic              arlock,    // 1=exclusive
    input  logic              arvalid,
    input  logic              arready,
    // 写响应
    output logic [1:0]        bresp,     // EXOKAY if exclusive OK
    // 状态
    output logic              exclusive_active
);
    // 独占访问哈希表 (ID + Addr 匹配)
    // 1. AW lock=1 → 记录 (ID, Addr) 为 exclusive pending
    // 2. AR lock=1 → 检查 (ID, Addr) 是否 pending
    //    是 → 返回 EXOKAY, 清除 pending
    //    否 → 返回 OKAY (normal)
    // 3. 非 exclusive 访问同一 addr → 清除 pending (被抢占)
endmodule
```

#### Step 2: 修改 `src/ui/ddr5_axi4_wr_slave.sv` — 新增 awlock 端口
```systemverilog
// 端口新增:
input  logic              awlock,     // 新增
// 在 IDLE 状态捕获 awlock:
//   if (awlock) → 标记为 exclusive write
// 在 RESP 状态:
//   if (exclusive_write && exclusive_ok) → bresp = AXI_RESP_EXOKAY
//   else → bresp = AXI_RESP_OKAY
```

#### Step 3: 修改 `src/ui/ddr5_axi4_rd_slave.sv` — 新增 arlock 端口
```systemverilog
// 端口新增:
input  logic              arlock,     // 新增
// 在 IDLE 状态捕获 arlock:
//   if (arlock) → 标记为 exclusive read
// 在 DATA 状态:
//   if (exclusive_read && exclusive_ok) → rresp = AXI_RESP_EXOKAY
//   else → rresp = AXI_RESP_OKAY
```

#### Step 4: 修改 `src/ui/ddr5_ui_axi4.sv` — 集成独占监视器
- 实例化 `ddr5_exclusive_monitor`
- 将 awlock/arlock 连接到监视器
- 从监视器获取 bresp/rresp

#### Step 5: 修改 `src/top/ddr5_controller.sv` — 顶层新增 awlock/arlock 端口
```systemverilog
// AXI4 Slave 端口新增:
input  logic [NUM_PORTS-1:0]  s_axi_awlock,  // 新增
input  logic [NUM_PORTS-1:0]  s_axi_arlock,  // 新增
```

#### Step 6: 新增测试 `test/tb_ddr5_exclusive_monitor.sv`
- 正常独占访问 → EXOKAY
- 被中间写抢占 → OKAY (失败)
- 非 exclusive 访问 → OKAY

**涉及文件**: `ddr5_exclusive_monitor.sv`(新建), `ddr5_axi4_wr_slave.sv`, `ddr5_axi4_rd_slave.sv`, `ddr5_ui_axi4.sv`, `ddr5_controller.sv`, `docs/06_DDR5_Interface_Definitions.md`

---

### B-01: Gearbox 频率比错误 — 🟠 High

**问题根因**:  
`docs/03_DDR5_PHY_Digital.md` 写着 "Frequency ratio 1:6 (400 MHz : 2.4 GHz)"，但 DFI Clock 是 1200 MHz（1:2 ratio），User Clock 400 MHz vs DFI Clock 1200 MHz = **1:3**，不是 1:6。1:6 是 User Clock vs DDR CK 的比率，不是 Gearbox 的频率比。

同时 RTL `ddr5_gearbox.sv` 实现的是 256→2×128 的两相拆分，与文档描述的 "4 DFI cycles per 1 AXI cycle" 不一致。

**修复方案**:

#### Step 1: 修改 `docs/03_DDR5_PHY_Digital.md` — 修正频率比
```diff
- Gearbox Ratio: 256:128 = 2:1 (frequency ratio 1:6)
+ Gearbox Ratio: 256:128 = 2:1 (data width ratio)
+ Frequency ratio: 1:3 (User 400 MHz : DFI 1200 MHz)
+ 
+ Note: 1:6 is the User Clock vs DDR CK ratio, NOT the Gearbox ratio.
+ The Gearbox operates between User Clock (400 MHz) and DFI Clock (1200 MHz).
+ At 1:3 frequency ratio, 1 AXI cycle = 3 DFI cycles.
+ However, data width ratio is 256:128 = 2:1, so only 2 DFI cycles 
+ are needed to transfer 256-bit (2 × 128-bit).

- Frequency ratio | 1:6 (400 MHz : 2.4 GHz) | User clock : DDR clock |
+ Frequency ratio | 1:3 (400 MHz : 1200 MHz) | User clock : DFI clock |
```

#### Step 2: 修改 `docs/03_DDR5_PHY_Digital.md` — 修正 Write/Read Path 描述
```
Write Path (Pack):
  1 AXI cycle (400 MHz) → 2 DFI cycles (1200 MHz)
  Phase 0: DFI DQ[127:0] = USER_DATA[127:0]
  Phase 1: DFI DQ[127:0] = USER_DATA[255:128]
  → 2 DFI cycles per 1 AXI cycle (data width ratio 2:1)

Read Path (Unpack):
  2 DFI cycles (1200 MHz) → 1 AXI cycle (400 MHz)
  DFI Phase 0: USER_DATA[127:0]   = DFI DQ[127:0]
  DFI Phase 1: USER_DATA[255:128] = DFI DQ[127:0]
  → Valid after 2 DFI cycles
```

#### Step 3: 修改 `docs/09_DDR5_DataFlow_Timing.md` — 修正延迟参数
```
Step 6: PHY Gearbox Pack  → 1.67 ns (2 cycles @1.2GHz)  ← 原 3.33 ns (4 cycles)
```

#### Step 4: 确认 RTL `ddr5_gearbox.sv` 已正确实现
- 当前 RTL 实现的是 256→2×128 的两相拆分 ✅ 正确
- 无需修改 RTL，只需修正文档

**涉及文件**: `docs/03_DDR5_PHY_Digital.md`, `docs/09_DDR5_DataFlow_Timing.md`

---

## Phase 2: 协议/可靠性补全（High/Medium）

### B-04: DFI 5.1 phase 信号缺失 — 🟠 High

**问题根因**:  
DFI 5.1 标准要求的关键信号 `dfi_phycsel`、`dfi_par_cfg`、`dfi_dram_clk_disable`、`dfi_freq_ratio` 等在文档和 RTL 中均未定义。

**修复方案**:

#### Step 1: 修改 `docs/06_DDR5_Interface_Definitions.md` — 新增 DFI 5.1 缺失信号
```markdown
#### DFI PHY Configuration Interface (新增)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| dfi_phycsel | 1 | Output | PHY chip select (select PHY instance) |
| dfi_par_cfg | 1 | Output | Parity configuration enable |
| dfi_dram_clk_disable | 2 | Output | DRAM clock disable per sub-channel |
| dfi_freq_ratio | 2 | Output | Frequency ratio indication (2=1:2, 4=1:4) |
| dfi_rddata_dnv | 2 | Input | Read data not valid (per sub-channel) — 已有但需确认 |
| dfi_parity_in | 1 | Output | Command/address parity — 已有但需确认 |
```

#### Step 2: 修改 `src/ddr5_defines.svh` — 新增 DFI 信号定义
```systemverilog
// --- DFI 5.1 Additional Signals (新增) ---
`define DFI_PHYCSEL_W      1
`define DFI_PAR_CFG_W       1
`define DFI_DRAM_CLK_DIS_W 2
`define DFI_FREQ_RATIO_SIG_W 2
```

#### Step 3: 修改 `src/dfi/ddr5_dfi_bridge.sv` — 新增端口和驱动
```systemverilog
// 新增端口:
output logic        dfi_phycsel,         // PHY chip select
output logic        dfi_par_cfg,          // Parity config
output logic [1:0]  dfi_dram_clk_disable, // DRAM clock disable
output logic [1:0]  dfi_freq_ratio_sig,   // Frequency ratio

// 驱动逻辑:
assign dfi_phycsel = 1'b0;           // 单 PHY 实例
assign dfi_par_cfg = 1'b0;           // 禁用 parity (初始)
assign dfi_dram_clk_disable = 2'b00; // 时钟使能
assign dfi_freq_ratio_sig = cfg_freq_ratio; // 从配置获取
```

#### Step 4: 修改 `src/top/ddr5_controller.sv` — 连线新信号
#### Step 5: 新增测试 `test/tb_ddr5_dfi_signals.sv`

**涉及文件**: `ddr5_defines.svh`, `ddr5_dfi_bridge.sv`, `ddr5_controller.sv`, `docs/06_DDR5_Interface_Definitions.md`

---

### B-03: 无死锁预防机制 — 🟡 Medium

**问题根因**:  
`docs/05_DDR5_Key_Specs.md` 声称 "Deadlock Immunity: Guaranteed"，但无任何实现机制。调度器有优先级排序但不是死锁预防。

**修复方案**:

#### Step 1: 新建 `src/ctrl/ddr5_deadlock_monitor.sv` — 死锁监视器
```systemverilog
module ddr5_deadlock_monitor #(
    parameter int TIMEOUT_CYCLES = 1000  // 命令最大等待周期
)(
    input  logic        clk,
    input  logic        rst_n,
    // 监控命令队列
    input  logic        cmd_valid,
    input  logic        cmd_ready,
    input  logic [3:0]  cmd_type,
    // 监控刷新
    input  logic        ref_req,
    input  logic        ref_ack,
    // 输出
    output logic        deadlock_detected,
    output logic [15:0] stall_count,
    output logic        force_refresh  // 强制刷新以解除死锁
);
    // 1. 命令停滞计数: cmd_valid && !cmd_ready 超过 TIMEOUT_CYCLES → 死锁
    // 2. 刷新停滞计数: ref_req && !ref_ack 超过 TIMEOUT_CYCLES → 死锁
    // 3. 死锁恢复: 强制排空低优先级队列, 插入强制刷新
    // 4. 上报中断 (irq)
endmodule
```

#### Step 2: 修改 `src/ctrl/ddr5_ctrl_core.sv` — 集成死锁监视器
- 实例化 `ddr5_deadlock_monitor`
- 连接调度器输出和刷新接口
- 死锁检测时触发中断

#### Step 3: 修改 `src/ddr5_defines.svh` — 新增中断位
```systemverilog
// IRQ 新增 bit 10: Deadlock detected
`define IRQ_DEADLOCK_BIT  10
```

#### Step 4: 修改 `docs/05_DDR5_Key_Specs.md` — 修正描述
```diff
- | Deadlock Immunity | Guaranteed | No circular dependencies |
+ | Deadlock Prevention | Hardware Monitor | Cmd/Ref stall timeout + force recovery |
```

#### Step 5: 修改 `docs/02_DDR5_Ctrl_Core.md` — 新增死锁预防章节
```markdown
### 4.7 Deadlock Prevention Mechanism

Mechanism: Hardware stall monitor with timeout recovery
- Command stall timeout: 1000 cycles → force queue flush
- Refresh stall timeout: 500 cycles → force refresh insertion
- Recovery action: Flush low-priority commands, insert forced refresh
- Reporting: IRQ bit 10, status register deadlock_count
```

#### Step 6: 新增测试 `test/tb_ddr5_deadlock_monitor.sv`

**涉及文件**: `ddr5_deadlock_monitor.sv`(新建), `ddr5_ctrl_core.sv`, `ddr5_defines.svh`, `docs/05_DDR5_Key_Specs.md`, `docs/02_DDR5_Ctrl_Core.md`

---

## Phase 3: 文档/流程补全（Medium/Low）

### B-06: 无 RTL 编码规范 — 🟡 Medium

**修复方案**: 新建 `docs/13_DDR5_RTL_Coding_Guidelines.md`

**文档大纲**:
```markdown
# DDR5 IP - RTL Coding Guidelines (Part 13)

## 1. Naming Conventions
### 1.1 Module Naming
- Prefix: ddr5_
- Snake_case
- Example: ddr5_cmd_scheduler, ddr5_cdc_fifo

### 1.2 Signal Naming
- Active-low: suffix _n (e.g., rst_n, cs_n)
- Clock: suffix _clk (e.g., uclk, cclk, dfi_clk)
- Bus: [high:0] convention
- Internal wires: descriptive prefix (e.g., ui_cmd_valid)

### 1.3 Parameter Naming
- UPPERCASE
- Prefix by domain (e.g., AXI_, DDR5_, DFI_)

## 2. CDC Coding Rules
### 2.1 Mandatory CDC Cells
- 2-stage synchronizer for control signals
- Async FIFO (Gray code pointers) for data signals
- Handshake protocol for configuration

### 2.2 Forbidden Patterns
- No direct cross-domain assignment
- No logic in clock path
- No async reset in data path

## 3. Reset Coding Rules
### 3.1 Reset Style
- Async assert, sync deassert (2-flop synchronizer)
- Single reset per clock domain
- Reset deassertion sequence: Global → Ctrl → PHY → Training

## 4. Clock Coding Rules
### 4.1 Clock Naming
- uclk (user), cclk (controller), dfi_clk (DFI), phy_clk (PHY)

### 4.2 Clock Gating
- Use latch-based glitch-free clock gate
- test_en bypass for scan

## 5. Synthesis Rules
### 5.1 Target
- FPGA: Xilinx UltraScale+ (Vivado 2025.2)
- ASIC: TSMC 7nm (DC + ICC2)

### 5.2 Constraints
- CDC paths: set_false_path / set_max_delay
- Reset paths: async, no timing check on assert
```

**涉及文件**: `docs/13_DDR5_RTL_Coding_Guidelines.md`(新建)

---

### B-07: 无软件驱动架构 — 🟡 Medium

**修复方案**: 新建 `docs/14_DDR5_Software_Driver_Architecture.md`

**文档大纲**:
```markdown
# DDR5 IP - Software Driver Architecture (Part 14)

## 1. Driver Layer Architecture
┌─────────────────────────────────┐
│ Application / OS               │
├─────────────────────────────────┤
│ HAL (Hardware Abstraction)     │
│  - ddr5_hal_init()             │
│  - ddr5_hal_read()             │
│  - ddr5_hal_write()            │
├─────────────────────────────────┤
│ Driver Layer                    │
│  - ddr5_drv_config()           │
│  - ddr5_drv_train()            │
│  - ddr5_drv_self_test()        │
│  - ddr5_drv_isr()              │
├─────────────────────────────────┤
│ Register Access (APB)           │
│  - reg_read(offset)            │
│  - reg_write(offset, value)    │
└─────────────────────────────────┘

## 2. Initialization Flow
1. Power on → wait POR deassert
2. Read VERSION register → check IP version
3. Read CAPABILITY → check features
4. Configure TIMING registers → DDR5-4800 defaults
5. Configure REFRESH_CTRL → FGR 2x mode
6. Enable ECC → ECC_CTRL[0]=1
7. Start training → TRAIN_CTRL[0]=1
8. Poll TRAIN_STATUS → wait complete
9. Set data rate → CTRL[8:9]
10. Enable controller → CTRL[0]=1
11. Wait STATUS[0] (ready) = 1
12. IP ready for traffic

## 3. API Reference
### 3.1 Initialization
- int ddr5_init(struct ddr5_config *cfg)
- int ddr5_deinit(void)

### 3.2 Data Transfer
- int ddr5_read(uint64_t addr, void *buf, size_t len)
- int ddr5_write(uint64_t addr, const void *buf, size_t len)

### 3.3 Configuration
- int ddr5_set_data_rate(enum ddr5_rate rate)
- int ddr5_set_refresh_mode(enum ddr5_refresh mode)
- int ddr5_set_ecc(bool enable)

### 3.4 Training
- int ddr5_start_training(uint8_t step_mask)
- int ddr5_get_training_result(struct ddr5_train_result *res)

### 3.5 Interrupt Handling
- void ddr5_isr(void)  // Interrupt Service Routine
  - Check IRQ_STATUS
  - Handle ECC errors
  - Handle training complete/error
  - Handle refresh overflow
  - Clear interrupt

### 3.6 Diagnostics
- int ddr5_get_status(struct ddr5_status *st)
- int ddr5_get_perf_counters(struct ddr5_perf *perf)
- int ddr5_self_test(void)
```

**涉及文件**: `docs/14_DDR5_Software_Driver_Architecture.md`(新建)

---

### B-08: 无验证计划 (非 UVM) — 🟢 Low

**修复方案**: 升级 `doc/verification_report.md` → 新建 `docs/15_DDR5_Verification_Plan.md`

**文档大纲**:
```markdown
# DDR5 IP - Verification Plan (Part 15)

## 1. Verification Methodology
### 1.1 Current: Directed Testbench + Coverage + Assertions
### 1.2 Target: UVM-based with constrained random

## 2. Coverage Targets (扩展)
| Module | Functional Coverage | Code Coverage | Assertion Coverage |
|--------|--------------------|---------------|--------------------|
| ddr5_reset_sync | 100% | 100% | 100% |
| ddr5_cdc_fifo | 95% | 95% | 100% |
| ddr5_clk_gate | 100% | 100% | 100% |
| ddr5_addr_mapper | 95% | 90% | 90% |
| ddr5_cmd_arbiter | 95% | 95% | 100% |
| ddr5_axi4_wr_slave | 95% | 90% | 95% |
| ddr5_axi4_rd_slave | 95% | 90% | 95% |
| ddr5_cmd_scheduler | 90% | 85% | 90% |
| ddr5_protocol_fsm | 95% | 90% | 95% |
| ddr5_bank_manager | 90% | 85% | 90% |
| ddr5_refresh_ctrl | 90% | 85% | 90% |
| ddr5_timing_engine | 90% | 85% | 90% |
| ddr5_ecc_engine | 95% | 90% | 95% |
| ddr5_dfi_bridge | 90% | 85% | 90% |
| ddr5_gearbox | 95% | 90% | 95% |
| ddr5_dll_ctrl | 85% | 80% | 85% |
| ddr5_training_engine | 80% | 75% | 80% |

## 3. Test Scenarios (扩展到全模块)
### 3.1 UI Layer (已有)
### 3.2 Controller Core (新增)
- Protocol FSM: all state transitions
- Scheduler: page hit/miss/conflict, starvation, queue full
- Bank Manager: 32-bank state tracking, boundary
- Refresh: FGR 1x/2x/4x, credit overflow, same-bank
- Timing: all parameters, boundary conditions
- ECC: single-bit inject, double-bit inject, no error

### 3.3 DFI Bridge (新增)
- Command FIFO CDC
- Data FIFO CDC
- Training handshake

### 3.4 PHY Digital (新增)
- DLL lock sequence
- Training step sequence
- Gearbox pack/unpack

## 4. Regression Plan
- Nightly: all directed tests (~30 min)
- Weekly: full regression + coverage merge (~4 hours)
- Pre-tapeout: constrained random + formal (~24 hours)

## 5. Formal Verification Plan
- Protocol FSM: prove all state transitions
- CDC: prove FIFO safety (no overflow/underflow)
- Arbitrer: prove no starvation (liveness)
```

**涉及文件**: `docs/15_DDR5_Verification_Plan.md`(新建)

---

## 执行顺序与依赖关系

```
Phase 1 (并行):
  B-05 (addr_mapper + sub_channel) ──┐
  B-02 (exclusive monitor) ──────────┤── Phase 2 依赖
  B-01 (doc fix only) ──────────────┘
  
Phase 2 (B-05/B-02 完成后):
  B-04 (DFI signals, 依赖 ddr5_dfi_bridge 已稳定)
  B-03 (deadlock monitor, 依赖 ctrl_core 已稳定)

Phase 3 (独立, 可与 Phase 2 并行):
  B-06 (coding guidelines doc)
  B-07 (driver architecture doc)
  B-08 (verification plan doc)
```

---

## 修复后 review_blocking.md 更新模板

每个 issue 修复后，在 `docs/review_blocking.md` 中更新状态：

```markdown
## B-XX: [问题标题]
**Status**: ✅ RESOLVED / ⚠️ PARTIALLY RESOLVED
**Resolution**: [修复内容摘要]
**Files Changed**: [文件列表]
**Verification**: [测试文件 + 结果]
**Date**: [修复日期]
```

---

## 风险评估

| 修复项 | 风险 | 缓解措施 |
|--------|------|----------|
| B-05 addr_mapper 改动 | 可能影响现有地址映射测试 | 先跑 tb_ddr5_addr_mapper 确认回归 |
| B-02 exclusive monitor | 增加 UI 层复杂度 | 独立模块, 可配置 bypass |
| B-04 DFI 新增信号 | 可能影响 DFI bridge 仿真 | 先更新 PHY behavioral model |
| B-03 deadlock monitor | 可能误报 | 设置合理 timeout (1000 cycles) |
| B-01 文档修正 | 无风险 | 纯文档修改 |
