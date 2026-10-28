# DDR5 IP - Register Map (Part 7)

## 10. Register Map Framework

### 10.1 Address Space Overview

```
Base: 0x0000 (APB, 16-bit address)
Size: 64 KB (0x0000 ~ 0xFFFF)

Regions:
  0x0000~0x00FF: Global Control
  0x0100~0x01FF: Timing Parameters
  0x0200~0x02FF: Refresh Control
  0x0300~0x03FF: ECC Control & Status
  0x0400~0x04FF: Training Control
  0x0500~0x06FF: Training Results
  0x0700~0x07FF: Performance Counters
  0x0800~0x08FF: Interrupt Control
  0x0900~0x09FF: Debug & Test
```

### 10.2 Global Control Registers

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0000 | CTRL | R/W | [0]enable, [1]soft_reset, [2]low_power, [3]self_refresh, [4]train_start, [8:9]data_rate, [10:11]refresh_mode, [12]ecc_en, [13]crc_en, [14:15]scheduler_alg |
| 0x0004 | STATUS | RO | [0]ready, [1]train_complete, [2]train_error, [3]sr_active, [4]lp_active, [5:7]fsm_state, [8:9]cur_rate, [10:11]cur_ref_mode |
| 0x0008 | VERSION | RO | IP version (major[31:16].minor[15:0]) |
| 0x000C | CAPABILITY | RO | [0]ecc_sup, [1]crc_sup, [2]multi_rank, [3]dual_ch, [4:7]max_ranks, [8:11]max_rate, [12:15]data_width |

### 10.3 Timing Parameter Registers

| Offset | Name | Default (DDR5-4800) | Description |
|--------|------|---------------------|-------------|
| 0x0100 | TIMING_0 | 0x0022_0022 | tRCD[15:0], tRP[31:16] (tCK units) |
| 0x0104 | TIMING_1 | 0x004D_006F | tRAS[15:0], tRC[31:16] |
| 0x0108 | TIMING_2 | 0x02C5_0180 | tRFC[15:0], tRFCsb[31:16] |
| 0x010C | TIMING_3 | 0x249F_0028 | tREFI[15:0], tWR[31:16] |
| 0x0110 | TIMING_4 | 0x0012_0028 | tRTP[15:0], CL[31:16] |
| 0x0114 | TIMING_5 | 0x0027_0008 | CWL[15:0], tCCD_L[31:16] |
| 0x0118 | TIMING_6 | 0x0008_0004 | tCCD_S[15:0], tRRD_L[31:16] |
| 0x011C | TIMING_7 | 0x0010_0004 | tRRD_S[15:0], tFAW[31:16] |
| 0x0120 | TIMING_8 | 0x000A_000A | tXS[15:0], tXP[31:16] |
| 0x0124 | TIMING_9 | 0x0008_0008 | tZQCAL[15:0], tZQCS[31:16] |

### 10.4 Refresh Control Registers

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0200 | REFRESH_CTRL | R/W | [0]auto_ref_en, [1]manual_trigger, [2:3]mode(1x/2x/4x), [4]same_bank_en, [8:15]credit_threshold |
| 0x0204 | REFRESH_STATUS | RO | [0:7]credit_count, [8:15]pending_count, [16]in_progress, [17]overflow |
| 0x0208 | REFRESH_COUNT | RO | Total refresh count (clear on read) |

### 10.5 ECC Registers

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0300 | ECC_CTRL | R/W | [0]enable, [1]error_inject_en, [2:3]inject_bit_pos |
| 0x0304 | ECC_STATUS | RO | [0]sbe_detected, [1]dbe_detected, [2]overflow (sticky) |
| 0x0308 | ECC_ERR_ADDR | RO | Last error address |
| 0x030C | ECC_ERR_DATA | RO | Last error data (pre-correction) |
| 0x0310 | ECC_ERR_SYNDROME | RO | Last error syndrome |
| 0x0314 | ECC_SBE_COUNT | RO | Single-bit error count (clear on read) |
| 0x0318 | ECC_DBE_COUNT | RO | Double-bit error count (clear on read) |

### 10.6 Training Registers

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0400 | TRAIN_CTRL | R/W | [0]start, [1]abort, [2:7]step_select, [16:31]timeout_ms |
| 0x0404 | TRAIN_STATUS | RO | [0]in_progress, [1]complete, [2]error, [3:7]cur_step, [8:15]error_code |
| 0x0408 | TRAIN_PROGRESS | RO | Progress percentage (0~100) |
| 0x0500 | CA_DELAY | RO | CA training result [7:0] |
| 0x0504~0x0520 | WL_DELAY[0:7] | RO | Write leveling delay per byte lane |
| 0x0524~0x0540 | RGT_DELAY[0:7] | RO | Read gate delay per byte lane |
| 0x0544~0x05C0 | RDQ_DELAY[0:31] | RO | Read DQ delay per bit |
| 0x05C4~0x0640 | WDQ_DELAY[0:31] | RO | Write DQ delay per bit |
| 0x0644 | VREF_CODE | RO | Vref training result [6:0] |
| 0x0648~0x0654 | DFE_TAP[0:3] | RO | DFE tap coefficients |

### 10.7 Performance Counter Registers

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0700 | PERF_CTRL | R/W | [0]enable, [1]clear_all |
| 0x0704 | READ_COUNT | RO | Total read commands |
| 0x0708 | WRITE_COUNT | RO | Total write commands |
| 0x070C | ACT_COUNT | RO | Total activate commands |
| 0x0710 | PRE_COUNT | RO | Total precharge commands |
| 0x0714 | REF_COUNT | RO | Total refresh commands |
| 0x0718 | PAGE_HIT_COUNT | RO | Page hit count |
| 0x071C | PAGE_MISS_COUNT | RO | Page miss count |
| 0x0720 | PAGE_CONFLICT_COUNT | RO | Page conflict count |
| 0x0724 | IDLE_CYCLE_COUNT | RO | Idle cycle count |
| 0x0728 | BUSY_CYCLE_COUNT | RO | Busy cycle count |

### 10.8 Interrupt Control Registers

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0800 | IRQ_STATUS | R/W1C | [0]ecc_sbe, [1]ecc_dbe, [2]crc_err, [3]train_done, [4]train_err, [5]ref_overflow, [6]temp_alert, [7]illegal_cmd, [8]dfi_err, [9]phy_err, [10]deadlock (B-03) |
| 0x0804 | IRQ_ENABLE | R/W | Interrupt enable mask (1=enable) |
| 0x0808 | IRQ_RAW | RO | Raw interrupt status (before mask) |

### 10.9 Debug Registers

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0900 | DEBUG_CTRL | R/W | [0]force_page_conflict, [1]force_refresh, [2]disable_scheduler, [3]single_step_mode |
| 0x0904 | FSM_TRACE | RO | FSM state trace buffer |
| 0x0908 | CMD_TRACE | RO | Command trace buffer |
| 0x090C | DEADLOCK_STATUS | RO | [0]deadlock_detected (sticky), [31:16]stall_count (B-03) |
