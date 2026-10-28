# DDR5 IP - PHY Digital Logic Design (Part 3)

## 5. PHY Digital Logic Module Design

### 5.1 DLL Clock Calibration Unit

#### Digital DLL Architecture

```
Digital DLL Structure:
┌─────────────────────────────────────────┐
│ Reference Clock (ref_clk)                │
│         ↓                                │
│ Phase Detector ← Feedback Clock         │
│         ↓                                │
│ Digital Loop Filter (PI Controller)      │
│         ↓                                │
│ Delay Control Register (8-bit)           │
│         ↓                                │
│ Variable Delay Line (256 steps)          │
│         ↓                                │
│ Output Clock (delayed_clk)               │
│         ↓                                │
│ 360° Phase Scan Capability               │
└─────────────────────────────────────────┘
```

#### DLL Specifications

| Parameter | Value | Description |
|-----------|-------|-------------|
| Phase resolution | 1.4° (360°/256) | 8-bit control, 256 delay steps |
| Lock time | < 10 μs | Initial lock from reset |
| Tracking accuracy | ≤ 5° phase error | Steady-state jitter |
| Update rate | 1 MHz | Continuous tracking |
| Operating frequency | 1.6~3.2 GHz | DDR5-3200 to DDR5-6400 |

#### DLL Control Algorithm

```
DLL Lock Sequence:
1. Coarse Lock: Binary search for 180° phase (128 steps)
2. Fine Lock: Linear scan ±16 steps around coarse point
3. Lock Detect: Phase error < 5° for 100 consecutive cycles
4. Tracking Mode: PI controller continuously adjusts for drift

Pseudo-code:
function dll_lock():
    // Coarse lock
    delay_code = 128  // Start at midpoint
    for i in range(7):  // 7-bit binary search
        phase_error = measure_phase(delay_code)
        if phase_error > 0:
            delay_code += (1 << (6-i))
        else:
            delay_code -= (1 << (6-i))
    
    // Fine lock
    best_code = delay_code
    best_error = abs(measure_phase(delay_code))
    for offset in range(-16, 17):
        test_code = delay_code + offset
        error = abs(measure_phase(test_code))
        if error < best_error:
            best_error = error
            best_code = test_code
    
    // Lock detect
    lock_count = 0
    while lock_count < 100:
        if abs(measure_phase(best_code)) < 5°:
            lock_count++
        else:
            lock_count = 0
    
    return best_code  // DLL locked
```

### 5.2 Training Engine

#### DDR5 Training Sequence

```
DDR5 Initialization & Training Flow:
┌──────────────────────────────────────────────────┐
│ 1. Power-On Reset & Clock Stabilization          │
│    - Wait for PLL lock (100 μs)                  │
│    - Wait for voltage rails stable (500 μs)      │
│                                                   │
│ 2. DDR5 Initialization Sequence                  │
│    - Assert RESET_n low (100 μs min)             │
│    - Deassert RESET_n, wait 2 ms                 │
│    - Assert CKE high                             │
│    - Wait tXPR (tRFC + 10ns)                     │
│                                                   │
│ 3. Mode Register Configuration                   │
│    - Write MR0~MR7 (timing, features)            │
│    - Write MR31 (On-die ECC enable)              │
│                                                   │
│ 4. CA Training (DDR5 Unique)                      │
│    - Sweep CA delay (0~255)                       │
│    - Find valid window for CA[6:0]               │
│    - Set CA delay to window center               │
│    - Duration: ~5 ms                             │
│                                                   │
│ 5. Write Leveling                                 │
│    - Sweep DQS write delay per byte lane         │
│    - Align DQS edge to CK edge                   │
│    - Duration: ~10 ms                            │
│                                                   │
│ 6. Read Gate Training                            │
│    - Find DQS read enable window                 │
│    - Detect preamble timing                        │
│    - Duration: ~5 ms                             │
│                                                   │
│ 7. Read DQ Training                              │
│    - Sweep DQ read delay per bit                 │
│    - Find valid sampling window                  │
│    - Set DQ delay to window center               │
│    - Duration: ~15 ms                            │
│                                                   │
│ 8. Write DQ Training                             │
│    - Sweep DQ write delay per bit                │
│    - Align DQ to DQS write edge                  │
│    - Duration: ~10 ms                            │
│                                                   │
│ 9. Vref Training (DDR5 Unique)                   │
│    - Sweep Vref(DQ) level (0~127)                │
│    - Find optimal receiver threshold             │
│    - Duration: ~5 ms                             │
│                                                   │
│ 10. DFE Training (DDR5 Unique)                   │
│     - Enable Decision Feedback Equalization      │
│     - Tune DFE tap coefficients                  │
│     - Duration: ~5 ms                            │
│                                                   │
│ Total Training Time: ~60 ms (typical)            │
└──────────────────────────────────────────────────┘
```

#### Training Engine State Machine

```
Training FSM States:
  IDLE → CA_TRAIN → WL_TRAIN → RGT_TRAIN → RDQ_TRAIN → WDQ_TRAIN → VREF_TRAIN → DFE_TRAIN → DONE

Each training step:
  - Issue training commands (MRS, ACT, RD/WR patterns)
  - Sweep delay/voltage parameter
  - Capture pass/fail results
  - Find valid window (min/max boundaries)
  - Set parameter to window center
  - Store results in training result registers
```

#### Training Result Registers

| Register | Bits | Description |
|----------|------|-------------|
| CA_DELAY[7:0] | 8 | CA training result (optimal delay code) |
| WL_DELAY[7:0] × 8 | 64 | Write leveling delay per byte lane |
| RGT_DELAY[7:0] × 8 | 64 | Read gate delay per byte lane |
| RDQ_DELAY[7:0] × 32 | 256 | Read DQ delay per bit |
| WDQ_DELAY[7:0] × 32 | 256 | Write DQ delay per bit |
| VREF_CODE[6:0] | 7 | Vref training result |
| DFE_TAP[7:0] × 4 | 32 | DFE tap coefficients |
| TRAIN_STATUS | 8 | Training status (pass/fail/error code) |

### 5.3 Bitwidth Gearbox

#### Gearbox Architecture

```
User Side (AXI): 256-bit @ 400 MHz
         ↓ (Write: pack, Read: unpack)
DFI Side: 128-bit @ 1.2 GHz (DDR5-4800, DFI 1:2 mode)

Gearbox data-width ratio : 256:128 = 2:1
Gearbox frequency ratio  : 1:3 (User 400 MHz : DFI 1200 MHz)

NOTE: 1:6 (400 MHz : 2.4 GHz) is the User-clock : DDR-CK ratio, NOT the
Gearbox ratio. The Gearbox sits between the User clock (400 MHz) and the
DFI clock (1200 MHz). Because the data-width ratio is 2:1, only 2 DFI
cycles are needed to transfer one 256-bit AXI beat (matches the RTL
WR_PHASE_0 / WR_PHASE_1 two-phase split in ddr5_gearbox.sv).

Write Path (Pack):
  Phase 0: DFI_DQ[127:0] = USER_DATA[127:0]
  Phase 1: DFI_DQ[127:0] = USER_DATA[255:128]
  → 2 DFI cycles per 1 AXI cycle

Read Path (Unpack):
  Phase 0: USER_DATA[127:0]   = DFI_DQ[127:0]
  Phase 1: USER_DATA[255:128] = DFI_DQ[127:0]
  → Valid after 2 DFI cycles
```

#### Gearbox Specifications

| Parameter | Value | Description |
|-----------|-------|-------------|
| User data width | 256-bit | AXI4 WDATA/RDATA |
| DFI data width | 128-bit (64-bit × 2 sub-channels) | Dual sub-channel |
| Frequency ratio | 1:3 (400 MHz : 1200 MHz) | User clock : DFI clock |
| Data-width ratio | 2:1 (256 : 128) | User : DFI |
| Latency | 2 DFI cycles | Pack/unpack delay |
| Burst length | BL16 | DDR5 default |
| ECC support | 8-bit per 32-bit | Integrated with ECC engine |

### 5.4 Clock Divider & Gate Control

#### Clock Domain Generation

```
Clock Tree:
┌─────────────────────────────────────────────────┐
│ Input Reference Clock: 100 MHz (external)        │
│         ↓                                        │
│ PLL: ×24 (for DDR5-4800) or ×32 (for DDR5-6400) │
│         ↓                                        │
│ DDR Clock (ddr_ck): 2.4 GHz or 3.2 GHz          │
│         ↓                                        │
│ DFI Clock (dfi_clk): 1.2 GHz or 1.6 GHz (÷2)    │
│         ↓                                        │
│ Controller Clock (ctrl_clk): 600 MHz or 800 MHz (÷4)│
│         ↓                                        │
│ User Clock (user_clk): 400 MHz (÷6) or external │
│                                                  │
│ Gate Control:                                    │
│   - Idle detection: no pending commands for 1 μs │
│   - Gate ctrl_clk and user_clk when idle         │
│   - Wake-up latency: 10 cycles                   │
│   - Power saving: ~30% in idle mode              │
└─────────────────────────────────────────────────┘
```

#### Clock Gating Strategy

| Clock Domain | Gate Condition | Wake-up Latency |
|--------------|----------------|-----------------|
| user_clk | No AXI transactions for 1 μs | 5 cycles |
| ctrl_clk | Command queue empty + no refresh pending | 10 cycles |
| dfi_clk | Self-refresh mode entered | 100 cycles (tXS) |
| ddr_ck | Self-refresh mode (PHY internal) | 100 cycles (tXS) |
