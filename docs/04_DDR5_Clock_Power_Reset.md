# DDR5 IP - Clock/Power Domain & Reset Architecture (Part 4)

## 6. Clock Domain & Power Domain Planning

### 6.1 Clock Domain Architecture

```
Clock Domain Partitioning:
┌─────────────────────────────────────────────────────┐
│ User Clock Domain (uclk): 200~400 MHz               │
│   ├── AXI4 interface clock                          │
│   ├── Configuration register clock                  │
│   └── FIFO read/write side (direction-dependent)    │
├─────────────────────────────────────────────────────┤
│ Controller Clock Domain (cclk): DDR CK / 2          │
│   (1.2 GHz @DDR5-4800, 1.6 GHz @DDR5-6400)         │
│   ├── Protocol FSM, Scheduler, Bank Manager        │
│   ├── Refresh Controller                            │
│   └── FIFO opposite side                            │
├─────────────────────────────────────────────────────┤
│ PHY High-Speed Clock Domain (pclk): DDR CK full rate│
│   (2.4 GHz @DDR5-4800, 3.2 GHz @DDR5-6400)         │
│   ├── DLL, DDR I/O flip-flops                       │
│   ├── Training engine sampling logic                │
│   └── DFI interface physical side                   │
├─────────────────────────────────────────────────────┤
│ Configuration Clock Domain (cfgclk): 50~100 MHz     │
│   └── APB/AXI4-Lite register configuration          │
└─────────────────────────────────────────────────────┘
```

### 6.2 Cross-Clock-Domain Synchronization Strategy

| CDC Path | Synchronization Method | Latency | Notes |
|----------|----------------------|---------|-------|
| uclk ↔ cclk | Async FIFO (Gray code pointers) | 2-3 cycles | Data path only |
| cclk ↔ pclk | DFI standard sync (1:2/1:4 ratio) | 1 cycle | Phase-aligned |
| cfgclk → others | Handshake sync (2-stage + ACK) | 4-6 cycles | Config only |
| Reset signals | Async assert, sync deassert | 2 cycles | All domains |

### 6.3 Clock Frequency Relationships

```
DDR5-4800 Configuration:
  DDR CK:     2400 MHz (DDR data rate = 4800 MT/s)
  DFI Clock:  1200 MHz (1:2 ratio)
  Ctrl Clock: 600 MHz  (1:4 ratio)
  User Clock: 400 MHz  (external, configurable)

DDR5-6400 Configuration:
  DDR CK:     3200 MHz (DDR data rate = 6400 MT/s)
  DFI Clock:  1600 MHz (1:2 ratio)
  Ctrl Clock: 800 MHz  (1:4 ratio)
  User Clock: 400 MHz  (external, configurable)
```

### 6.4 Power Domain Planning

```
Power Domain Partitioning (ASIC):
┌─────────────────────────────────────────────────────┐
│ PD_Always_On (AON):                                 │
│   ├── Reset controller                              │
│   ├── Wake-up logic                                 │
│   └── Always-on registers (retention)               │
│   Voltage: 0.75V (always on)                        │
├─────────────────────────────────────────────────────┤
│ PD_Controller:                                      │
│   ├── Controller core logic                         │
│   ├── Scheduler, FSM, Bank Manager                  │
│   └── ECC engine                                    │
│   Voltage: 0.75V (switchable)                       │
├─────────────────────────────────────────────────────┤
│ PD_PHY_Digital:                                     │
│   ├── PHY digital logic                             │
│   ├── DLL, Training engine                          │
│   └── Gearbox                                       │
│   Voltage: 0.75V (switchable)                       │
├─────────────────────────────────────────────────────┤
│ PD_PHY_Analog (provided by PHY vendor):             │
│   ├── I/O drivers, receivers                        │
│   ├── PLL, analog DLL                               │
│   └── Impedance calibration                         │
│   Voltage: 1.1V VDDQ (DDR5 I/O voltage)            │
└─────────────────────────────────────────────────────┘

DDR5 SDRAM Power Rails (external):
  VDD:    1.1V (core)
  VDDQ:   1.1V (I/O)
  VPP:    1.8V (wordline pump)
  PMIC:   On-DIMM power management (DDR5 unique)
```

### 6.5 Low Power Modes

| Mode | Description | Entry Latency | Exit Latency | Power Saving |
|------|-------------|---------------|--------------|--------------|
| Clock Gating | Gate idle clocks | Immediate | 5-10 cycles | ~30% |
| Power Down (PD) | CKE low, DLL off | 10 cycles | tXP (~6ns) | ~50% |
| Self-Refresh (SR) | CKE low, internal refresh | 100 cycles | tXS (~300ns) | ~80% |
| Deep Power Down | All rails off (not DDR5 standard) | N/A | Full re-init | ~95% |

---

## 7. Reset Architecture Design

### 7.1 Multi-Stage Reset Sequence

```
Reset Release Sequence:
  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
  │ Global   │────→│Controller│────→│PHY Digital│────→│Training  │
  │ Reset    │     │Reset     │     │Reset     │     │Engine    │
  │(por_rst) │     │Release   │     │Release   │     │Release   │
  └──────────┘     └──────────┘     └──────────┘     └──────────┘
       │                │                │                │
       │ Async assert   │ Sync release   │ Wait PLL lock  │ Wait training
       │ Sync release   │ FSM init       │ DLL lock       │ complete
       │ (2-flop)       │ Register clear │ IO init        │ Enter normal
       │                │                │                │ operation
       │                │                │                │
       ▼                ▼                ▼                ▼
   t=0              t=T1             t=T2             t=T3
                  (~100μs)         (~1ms)           (~60ms)
```

### 7.2 Reset Signal List

| Signal | Domain | Type | Description |
|--------|--------|------|-------------|
| por_rst_n | Global | Async | Power-on reset (active low) |
| ctrl_rst_n | cclk | Sync | Controller logic reset |
| ui_rst_n | uclk | Sync | User interface reset |
| phy_rst_n | pclk | Sync | PHY digital reset |
| train_rst_n | pclk | Sync | Training engine reset |
| cfg_rst_n | cfgclk | Sync | Configuration register reset |
| ddr_reset_n | External | Async | DDR5 device RESET_n pin |

### 7.3 Reset Synchronization

```
Reset Synchronizer (per clock domain):
  ┌─────────────────────────────────────────┐
  │ Async Reset Input (por_rst_n)            │
  │         ↓                                │
  │ FF1 (async preset, sync clear)          │
  │         ↓                                │
  │ FF2 (sync clear)                         │
  │         ↓                                │
  │ Synchronized Reset Output (domain_rst_n) │
  └─────────────────────────────────────────┘

Reset Release Sequence (detailed):
1. por_rst_n deasserted (external)
2. After 2 cycles: all synchronized resets deassert
3. Controller FSM enters RESET state
4. Wait 100 μs for DDR5 device power stabilization
5. Assert ddr_reset_n low for 100 μs (DDR5 spec requirement)
6. Deassert ddr_reset_n, wait 2 ms
7. Controller FSM transitions to INIT state
8. Begin Mode Register writes
9. Wait for PLL lock (100 μs)
10. Release PHY reset
11. Begin training sequence (~60 ms)
12. Training complete → FSM transitions to IDLE
13. IP ready for normal operation
```

### 7.4 Reset Timing Diagram

```
Time:  0      100μs    200μs    2.2ms    2.3ms    ~62ms
       │       │        │        │        │        │
por_rst_n:  ───┘
ctrl_rst_n: ───────┘
ddr_reset_n: ──────┘────┘
phy_rst_n:  ────────────────┘
train_rst_n: ──────────────────┘
FSM State:  RESET───────INIT──────────IDLE
Training:   ──────────────────────CA─WL─RGT─RDQ─WDQ─Vref─DFE─DONE
```
