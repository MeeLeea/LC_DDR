# DDR5 IP - Scheduler and FSM Details (Part 2a)

## 4.1 Command Scheduler Implementation

### FR-FCFS Algorithm

```
Selection Priority (High to Low):
1. Refresh commands (time-critical)
2. ZQ calibration commands
3. Page hit commands (read > write)
4. Page empty commands (read > write)
5. Page conflict commands (read > write)

Tie-breaking rules:
- Cross-Bank-Group before same-BG (tCCD_S vs tCCD_L)
- Older commands before newer (FCFS)
- Read before write (reduce latency)
```

### Bank Group Interleaving Benefit

```
DDR5: 4 BG × 8 Banks = 32 Banks

Sequential access with Row-BG-Bank-Col mapping:
  Addr 0x0000 -> BG0, B0
  Addr 0x0040 -> BG1, B0  (cross BG: tCCD_S = 4 tCK)
  Addr 0x0080 -> BG2, B0  (cross BG: tCCD_S = 4 tCK)
  Addr 0x00C0 -> BG3, B0  (cross BG: tCCD_S = 4 tCK)

Result: 4 accesses in 16 tCK (100% utilization)
vs Same BG: 4 accesses in 32~40 tCK (50% utilization)
Improvement: 2~2.5× throughput
```

## 4.2 Protocol State Machine

### State Transitions

```
RESET ──(por_rst_n=1)──> INIT
INIT ──(init_complete)──> IDLE
IDLE ──(page_miss)──> ACT
IDLE ──(refresh_timer)──> REF
IDLE ──(low_power_req)──> SREF
IDLE ──(zq_timer)──> ZQCAL
ACT ──(tRCD_met, read)──> RD
ACT ──(tRCD_met, write)──> WR
ACT ──(page_conflict)──> PRE
RD ──(same_row)──> RD
RD ──(complete)──> IDLE
RD ──(conflict)──> PRE
WR ──(same_row)──> WR
WR ──(complete)──> IDLE
WR ──(conflict)──> PRE
PRE ──(tRP_met)──> IDLE
REF ──(tRFC_met)──> IDLE
SREF ──(wake_up)──> IDLE
ZQCAL ──(tZQCAL_met)──> IDLE
```

### DDR5 Command Set

| Command | Code | State Transition | Description |
|---------|------|------------------|-------------|
| ACT | 0x0 | IDLE→ACT | Activate row |
| RD | 0x1 | ACT→RD | Read (BL16) |
| RDA | 0x2 | ACT→RD→PRE | Read with auto-precharge |
| WR | 0x3 | ACT→WR | Write (BL16) |
| WRA | 0x4 | ACT→WR→PRE | Write with auto-precharge |
| PRE | 0x5 | ACT→PRE→IDLE | Precharge |
| PREA | 0x6 | *→PRE→IDLE | Precharge all |
| REFab | 0x7 | IDLE→REF→IDLE | All-bank refresh |
| REFsb | 0x8 | IDLE→REF→IDLE | Same-bank refresh (DDR5) |
| SREF | 0x9 | IDLE→SREF | Enter self-refresh |
| SREFX | 0xA | SREF→IDLE | Exit self-refresh |
| ZQCAL | 0xB | IDLE→ZQCAL→IDLE | ZQ calibration |
| MRW | 0xC | INIT/IDLE | Mode register write |
| MRR | 0xD | INIT/IDLE | Mode register read |
| NOP | 0xF | — | No operation |
