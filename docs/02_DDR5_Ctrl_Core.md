# DDR5 IP - Controller Core Design (Part 2)

## 4. DDR Controller Core Module Design

### 4.1 Command Scheduler

#### Algorithm: FR-FCFS + Bank Group Interleave

Priority (High to Low):
1. Refresh (REF/SREF) - highest, prevent data loss
2. ZQ Calibration - periodic impedance calibration
3. Page Hit - already activated Row, zero extra overhead
4. Page Empty - needs ACT, overhead = tRCD
5. Page Conflict - needs PRE+ACT, overhead = tRP+tRCD

Same-priority sorting:
- Cross Bank Group first (use tCCD_S short delay)
- Read before Write (reduce read latency)
- Within same BG: FCFS order
- Write queue >= 75%: switch to Write Batching

#### 4-Stage Pipeline

```
S1: Candidate Selection (Bank state filter)
S2: Timing Check (tCCD/tRRD/tFAW)
S3: Priority Arbitration (FR-FCFS)
S4: Command Issue (to DFI)
```

Throughput: 1 cmd/cycle (single-issue) or 2 cmd/cycle (dual-issue, dual sub-channel)

### 4.2 Protocol FSM

States: RESET -> INIT -> IDLE -> ACT -> RD/WR -> PRE -> IDLE
Special: IDLE -> REF -> IDLE, IDLE -> SREF -> IDLE, IDLE -> ZQCAL -> IDLE

All transitions strictly follow JEDEC timing parameters.
Dual sub-channel: independent FSM per channel.

### 4.3 Bank Manager

DDR5 Bank Topology (per Rank, per Sub-Channel):
- 4 Bank Groups x 8 Banks/Group = 32 Banks
- vs DDR4: 2 BG x 8 Bank = 16 Banks

Per-Bank State Register:
- state: 3-bit (IDLE/ACTIVE/PRECHARGING/REFRESHING)
- open_row: 18-bit (current active row address)
- row_open: 1-bit (page open flag)
- last_cmd: 4-bit (last issued command type)
- last_cmd_time: 16-bit (timestamp for timing check)

Key Timing Constraints:
- tCCD_L (same BG): 8-10 tCK
- tCCD_S (cross BG): 4 tCK
- tRRD_L (same BG): 8 tCK
- tRRD_S (cross BG): 4 tCK
- tFAW (global): 16 tCK

### 4.4 Refresh Controller

DDR5 Refresh Modes:
- All-Bank Refresh (REFab): tRFC ~295ns @DDR5-4800
- Same-Bank Refresh (REFsb): tRFC_SB ~160ns (DDR5 unique)
- Fine Granularity FGR 2x: half refresh per cycle (recommended default)
- Fine Granularity FGR 4x: quarter refresh per cycle
- Self-Refresh: low-power mode

Refresh Credit Mechanism:
- Accumulate 1 credit per tREFI (3.9us @1x, 1.95us @2x)
- Max 8 credits buffered
- Credit > 0 and bus idle: insert refresh
- Credit = 8: force refresh (prevent data loss)
- Default: FGR 2x, overhead ~3.5% (meets <=5% target)

### 4.5 Timing Parameter Engine

All JEDEC DDR5 timing parameters are register-configurable.

DDR5-4800 typical values:
- tCK=416ps, tRCD=14.16ns(34tCK), tRP=14.16ns(34tCK)
- tRAS=32ns(77tCK), tRC=46.16ns(111tCK)
- tRFC=295ns(709tCK), tRFCsb=160ns(384tCK)
- tREFI=3.9us(9375tCK), CL=40, CWL=39
- tWR=30ns(72tCK), tRTP=7.5ns(18tCK)
- tCCD_L=8tCK, tCCD_S=4tCK
- tRRD_L=8tCK, tRRD_S=4tCK, tFAW=16tCK

DDR5-6400 typical values:
- tCK=312ps, tRCD=14.06ns(45tCK), tRP=14.06ns(45tCK)
- tRAS=32ns(102tCK), tRC=46.06ns(147tCK)
- tRFC=295ns(946tCK), tRFCsb=160ns(512tCK)
- tREFI=3.9us(12500tCK), CL=52, CWL=51
- tWR=30ns(96tCK), tRTP=7.5ns(24tCK)
- tCCD_L=10tCK, tCCD_S=4tCK
- tRRD_L=8tCK, tRRD_S=4tCK, tFAW=16tCK

Implementation: Per-bank countdown timers, decremented every cycle.
Command issue requires all related timers to reach zero.

### 4.6 ECC Engine

DDR5 ECC Architecture (3 layers):
- Layer 1: On-die ECC (built-in, transparent to controller)
- Layer 2: Link-level ECC (this design) - SEC-DED per 32-bit sub-channel
- Layer 3: CRC-8 (optional) - write data CRC for DQ link error detection

ECC Specs:
- Data width: 32-bit per sub-channel
- ECC width: 8-bit (Hsiao code, optimized XOR gates)
- Correction: 1-bit correct + 2-bit detect
- Latency: Encode 1 cycle, Decode 2 cycles
- Error reporting: Interrupt + status register

### 4.7 Deadlock Prevention Mechanism (B-03)

The scheduler priority order (Refresh > ZQ > Page Hit > Page Empty > Page
Conflict) is a *scheduling policy*, not a deadlock guarantee. To actually
prevent/pre-empt a hang, the core instantiates a hardware watchdog
(`ddr5_deadlock_monitor`) that observes the critical handshakes:

| Watched event | Condition | Timeout | Recovery action |
|---------------|-----------|---------|-----------------|
| UI→core command | `cmd_in_valid && !cmd_in_ready` | 1000 cyc | raise `deadlock_detected` |
| scheduler→FSM | `sched_valid && !sched_ready` | 1000 cyc | raise `deadlock_detected` |
| refresh | `ref_req && !ref_ack` | 500 cyc | pulse `force_refresh` |

Behavior:
- **Detection**: a stall counter saturates at its timeout and sets a sticky
  `deadlock_detected` flag.
- **Recovery**: a stalled refresh injects a forced-refresh pulse so the
  refresh credit cannot starve the command path.
- **Clearing**: once traffic resumes and the protocol FSM returns to IDLE,
  the sticky flag self-clears.
- **Reporting**: `deadlock_detected` is exported through `ddr5_ctrl_core` to
  `ddr5_controller`, where it is OR-ed into the top-level `irq`.

Status visibility: `deadlock_stall_count[15:0]` exposes the worst observed
stall for software diagnostics (see Part 14 driver API).
