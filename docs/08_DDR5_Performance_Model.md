# DDR5 IP - Performance Model & Bandwidth Analysis (Part 8)

## 11. Performance Model & Bandwidth Analysis

### 11.1 Theoretical Bandwidth Calculation

```
DDR5-4800 Configuration:
  Data Rate: 4800 MT/s (DDR, 2400 MHz clock)
  Data Width: 64-bit (32-bit × 2 sub-channels)
  Theoretical BW = 4800 × 64 / 8 = 38.4 GB/s

DDR5-5600 Configuration:
  Data Rate: 5600 MT/s
  Theoretical BW = 5600 × 64 / 8 = 44.8 GB/s

DDR5-6400 Configuration:
  Data Rate: 6400 MT/s
  Theoretical BW = 6400 × 64 / 8 = 51.2 GB/s
```

### 11.2 Bandwidth Overhead Breakdown

#### DDR5-4800 Overhead Analysis

```
Overhead Item              Percentage    Calculation
─────────────────────────────────────────────────────────────
Refresh Overhead           ~3.5%         tRFC=295ns, tREFI=3.9μs (FGR 2×)
                                         Overhead = tRFC / (2 × tREFI) = 295 / 7800 ≈ 3.8%
                                         With FGR 2×: 295 / (2 × 1950) ≈ 3.5%

Bank Conflict Overhead     ~5-8%         Depends on address distribution
                                         Worst case: all accesses to same BG
                                         Best case: uniform across all BGs
                                         Typical: 5-8% for random access

Page Miss Overhead         ~3-5%         Row miss requires PRE + ACT
                                         Overhead = (tRP + tRCD) / tRAS
                                         = (34 + 34) / 77 ≈ 88% per miss
                                         With 90% page hit rate: ~5%

Command Scheduling Bubbles ~2-3%         Scheduler pipeline stalls
                                         Due to timing constraints (tCCD, tRRD)
                                         Typical: 2-3% idle cycles

Training/Calibration       ~0.5%         Periodic re-training (temp drift)
                                         ZQ calibration every 100ms
                                         Negligible in steady state

ECC/CRC Overhead           ~0%           Parallel encoding/decoding
                                         No bandwidth penalty
─────────────────────────────────────────────────────────────
Total Overhead             ~15-20%
Effective Bandwidth        ~80-85%       (Optimized: 88-92%)
```

### 11.3 Latency Analysis

#### Single Read Latency Breakdown

```
DDR5-4800 Single Read Latency:
┌─────────────────────────────────────────────────────┐
│ Component                    Latency (ns)            │
├─────────────────────────────────────────────────────┤
│ AXI4 Interface               2.5 ns (1 cycle @400MHz)│
│ Command Queue                2.5 ns (1 cycle)        │
│ Scheduler Pipeline           10 ns (4 cycles @600MHz)│
│ DFI Interface                1.7 ns (2 cycles @1.2GHz)│
│ PHY Gearbox                  3.3 ns (4 cycles @1.2GHz)│
│ DDR5 tRCD                    14.16 ns (34 tCK)       │
│ DDR5 CL (CAS Latency)        16.67 ns (40 tCK)       │
│ PHY Read Path                3.3 ns (4 cycles)       │
│ DFI Read Return              1.7 ns (2 cycles)       │
│ Read FIFO                    2.5 ns (1 cycle)        │
│ AXI4 Response                2.5 ns (1 cycle)        │
├─────────────────────────────────────────────────────┤
│ Total Single Read Latency    ~60 ns                  │
└─────────────────────────────────────────────────────┘

Note: Page hit reads skip tRCD, reducing to ~46 ns
      Page conflict adds tRP (14.16 ns), increasing to ~74 ns
```

#### Single Write Latency Breakdown

```
DDR5-4800 Single Write Latency:
┌─────────────────────────────────────────────────────┐
│ Component                    Latency (ns)            │
├─────────────────────────────────────────────────────┤
│ AXI4 Interface               2.5 ns                  │
│ Command Queue                2.5 ns                  │
│ Scheduler Pipeline           10 ns                   │
│ DFI Interface                1.7 ns                  │
│ PHY Gearbox                  3.3 ns                  │
│ DDR5 tRCD                    14.16 ns                │
│ DDR5 CWL (CAS Write Latency) 16.25 ns (39 tCK)       │
│ PHY Write Path               3.3 ns                  │
│ Write Completion             2.5 ns                  │
├─────────────────────────────────────────────────────┤
│ Total Single Write Latency   ~56 ns                  │
└─────────────────────────────────────────────────────┘

Note: Write latency is slightly lower than read (no return path)
      Page hit writes skip tRCD, reducing to ~42 ns
```

#### Burst Transfer Latency

```
BL16 Burst Transfer Time:
  DDR5-4800: 16 beats × 0.416 ns = 6.67 ns
  DDR5-6400: 16 beats × 0.312 ns = 5.00 ns

Effective Burst Bandwidth:
  DDR5-4800: 512 bits / 6.67 ns = 76.8 Gbps = 9.6 GB/s (per sub-channel)
  DDR5-6400: 512 bits / 5.00 ns = 102.4 Gbps = 12.8 GB/s (per sub-channel)
```

### 11.4 Bandwidth Utilization Scenarios

#### Scenario 1: Sequential Read (Best Case)

```
Access Pattern: Sequential addresses across all Bank Groups
Address Mapping: Row-BG-Bank-Col (default)

Behavior:
  - All accesses are page hits (same row)
  - Cross Bank Group interleaving (tCCD_S = 4 tCK)
  - No refresh conflicts (scheduled during idle)
  - Minimal scheduling bubbles

Bandwidth Utilization: ~92-95%
Effective BW (DDR5-4800): 35.3 ~ 36.5 GB/s
```

#### Scenario 2: Random Read (Worst Case)

```
Access Pattern: Random addresses, frequent row conflicts
Address Distribution: Uniform across all banks

Behavior:
  - 50% page hits, 30% page empty, 20% page conflicts
  - Average overhead per access: ~20 tCK
  - Refresh conflicts: ~3.5%
  - Scheduling bubbles: ~5%

Bandwidth Utilization: ~65-70%
Effective BW (DDR5-4800): 25.0 ~ 26.9 GB/s
```

#### Scenario 3: Mixed Read/Write (Typical)

```
Access Pattern: 70% read, 30% write, mixed sequential/random
Address Distribution: 80% page hits, 20% page misses

Behavior:
  - Read/write batching reduces bus turnaround
  - Write queue buffering smooths write traffic
  - Average page hit rate: 80%

Bandwidth Utilization: ~80-85%
Effective BW (DDR5-4800): 30.7 ~ 32.6 GB/s
```

### 11.5 Performance Optimization Techniques

#### 11.5.1 Bank Group Interleaving

```
Without BG Interleaving:
  Access Bank 0, 1, 2, 3 (all in BG 0)
  Timing: tCCD_L = 8 tCK between accesses
  Throughput: 1 access / 8 tCK

With BG Interleaving:
  Access Bank 0 (BG0), Bank 8 (BG1), Bank 16 (BG2), Bank 24 (BG3)
  Timing: tCCD_S = 4 tCK between accesses
  Throughput: 1 access / 4 tCK

Improvement: 2× throughput for sequential access
```

#### 11.5.2 Read/Write Batching

```
Without Batching (frequent turnaround):
  RD, RD, WR, WR, RD, RD, WR, WR
  Turnaround penalty: tWTR = 7.5 ns per switch
  Overhead: 4 switches × 7.5 ns = 30 ns

With Batching (group reads and writes):
  RD, RD, RD, RD, WR, WR, WR, WR
  Turnaround penalty: 1 switch × 7.5 ns = 7.5 ns
  Overhead reduction: 75%

Trade-off: Increased write latency (buffered longer)
```

#### 11.5.3 Open Page Policy vs Closed Page Policy

```
Open Page Policy (default):
  - Keep row open after access
  - Next access to same row: page hit (0 overhead)
  - Next access to different row: page conflict (tRP + tRCD overhead)
  - Best for: Sequential access, high locality

Closed Page Policy:
  - Auto-precharge after every access
  - Every access: page empty (tRCD overhead)
  - No page conflicts
  - Best for: Random access, low locality

Adaptive Policy (recommended):
  - Track page hit rate per bank
  - If hit rate > 70%: open page
  - If hit rate < 30%: closed page
  - Dynamic adjustment per bank
```

#### 11.5.4 Refresh Optimization

```
Naive Refresh (All-Bank Refresh):
  - Refresh all 32 banks at once
  - Blocking time: tRFC = 295 ns
  - Frequency: every 3.9 μs
  - Overhead: 295 / 3900 = 7.6%

Fine Granularity Refresh (FGR 2×):
  - Refresh 16 banks at a time
  - Blocking time: tRFC/2 = 147.5 ns
  - Frequency: every 1.95 μs
  - Overhead: 147.5 / 1950 = 7.6% (same total, but less blocking)

Same-Bank Refresh (REFsb):
  - Refresh 1 bank per BG (4 banks total)
  - Blocking time: tRFCsb = 160 ns
  - Other BGs can continue access
  - Overhead: 160 / 1950 = 8.2% (slightly higher, but non-blocking)

Best Strategy: FGR 2× + REFsb when possible
  - Use REFsb when other BGs are busy
  - Use FGR 2× when bus is idle
  - Total overhead: ~3.5%
```

### 11.6 Performance Monitoring

#### Key Performance Metrics

```
Bandwidth Utilization:
  BW_util = (READ_COUNT + WRITE_COUNT) × BL16 × 64 / (BUSY_CYCLE_COUNT × tCK)
  Target: ≥ 85%

Page Hit Rate:
  PHR = PAGE_HIT_COUNT / (PAGE_HIT_COUNT + PAGE_MISS_COUNT + PAGE_CONFLICT_COUNT)
  Target: ≥ 80%

Refresh Overhead:
  REF_overhead = REF_COUNT × tRFC / (BUSY_CYCLE_COUNT × tCK)
  Target: ≤ 5%

Average Read Latency:
  Avg_RD_lat = Total_RD_latency / READ_COUNT
  Target: ≤ 100 ns (including queueing)

Average Write Latency:
  Avg_WR_lat = Total_WR_latency / WRITE_COUNT
  Target: ≤ 80 ns (including queueing)
```
