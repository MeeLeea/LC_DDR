# DDR5 IP - Configurable Parameters (Part 12)

## 15. Configurability Parameters

### 15.1 Synthesis-Time Parameters (RTL)

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| USER_DATA_WIDTH | 128/256/512 | 256 | User interface data width |
| DFI_DATA_WIDTH | 32/64 | 64 | DFI data width per sub-channel |
| NUM_SUB_CHANNELS | 1/2 | 2 | Number of sub-channels |
| ADDR_WIDTH | 28~34 | 34 | Address width (256MB~16GB) |
| ROW_BITS | 12~18 | 18 | Row address bits |
| COL_BITS | 9~12 | 10 | Column address bits |
| BANK_BITS | 3 | 3 | Bank bits per group (8 banks) |
| BG_BITS | 0~2 | 2 | Bank group bits (1~4 groups) |
| RANK_BITS | 0~2 | 2 | Rank bits (1~4 ranks) |
| AXI_ID_WIDTH | 4~16 | 8 | AXI ID width |
| AXI_DATA_WIDTH | 128/256/512 | 256 | AXI data width |
| NUM_AXI_PORTS | 1~8 | 4 | Number of AXI slave ports |
| CMD_FIFO_DEPTH | 8/16/32/64 | 16 | Command FIFO depth |
| WR_FIFO_DEPTH | 32/64/128 | 64 | Write data FIFO depth |
| RD_FIFO_DEPTH | 32/64/128 | 64 | Read data FIFO depth |
| NUM_BANKS | 16/32 | 32 | Total banks (DDR4=16, DDR5=32) |
| NUM_BANK_GROUPS | 1/2/4 | 4 | Bank groups |
| SCHEDULER_TYPE | 0/1/2 | 0 | 0=FR-FCFS, 1=ATLAS, 2=PAR-BS |
| MAX_OUTSTANDING_CMDS | 8~32 | 16 | Max outstanding commands |
| ECC_ENABLE | 0/1 | 1 | Enable ECC |
| CRC_ENABLE | 0/1 | 0 | Enable CRC |
| ECC_WIDTH | 7/8 | 8 | ECC bits per 32-bit data |
| PERF_COUNTERS_ENABLE | 0/1 | 1 | Enable performance counters |
| DEBUG_ENABLE | 0/1 | 1 | Enable debug features |
| TRACE_DEPTH | 64/128/256/512 | 256 | Trace buffer depth |
| DFI_FREQ_RATIO | 2/4 | 2 | DFI frequency ratio (1:2 or 1:4) |
| USER_CLK_DIV | 3/4/6/8 | 6 | User clock divider |
| CTRL_CLK_DIV | 2/4 | 2 | Controller clock divider |

### 15.2 Runtime Parameters (Register-Controlled)

| Register | Offset | Key Fields | Default |
|----------|--------|------------|---------|
| CTRL | 0x0000 | enable, soft_reset, low_power, self_refresh, train_start, data_rate[8:9], refresh_mode[10:11], ecc_en, crc_en, scheduler_alg[14:15] | 0x0000_0000 |
| TIMING_0~9 | 0x0100~0x0124 | tRCD, tRP, tRAS, tRC, tRFC, tRFCsb, tREFI, tWR, tRTP, CL, CWL, tCCD_L/S, tRRD_L/S, tFAW, tXS, tXP, tZQCAL | DDR5-4800 values |
| REFRESH_CTRL | 0x0200 | auto_ref_en, manual_trigger, mode[2:3], same_bank_en, credit_threshold[8:15] | 0x0000_0001 |
| ECC_CTRL | 0x0300 | enable, error_inject_en, inject_bit_pos[2:3] | 0x0000_0001 |
| TRAIN_CTRL | 0x0400 | start, abort, step_select[2:7], timeout_ms[16:31] | 0x0000_0000 |
| PERF_CTRL | 0x0700 | enable, clear_all | 0x0000_0000 |
| IRQ_ENABLE | 0x0804 | enable_mask[0:9] | 0x0000_0000 |
| DEBUG_CTRL | 0x0900 | force_page_conflict, force_refresh, disable_scheduler, single_step | 0x0000_0000 |

### 15.3 Parameter Validation Rules

```
Runtime parameter change rules:
1. Timing parameters: Only change when IP is in IDLE state
2. Data rate: Requires re-training after change
3. Refresh mode: Can change anytime, takes effect on next refresh
4. ECC/CRC: Can enable/disable anytime
5. Scheduler algorithm: Can change anytime, takes effect on next scheduling cycle
6. Training: Only start when IP is in INIT or IDLE state
```
