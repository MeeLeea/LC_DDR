# DDR5 IP - Data Flow Timing Diagrams (Part 9)

## 12. Data Flow and Timing Diagrams

### 12.1 Read Data Flow (Single Read, Page Hit)

```
Step  Component                  Latency
1     AXI4 AR handshake          2.5 ns (1 cycle @400MHz)
2     Command Decode + Addr Map  2.5 ns
3     Command Queue Insert       2.5 ns
4     Scheduler Pipeline (S1-S4) 6.67 ns (4 cycles @600MHz)
5     DFI Command Transfer       1.67 ns (2 cycles @1.2GHz)
6     PHY Gearbox Pack           1.67 ns (2 cycles @1.2GHz)  [B-01: 2:1 width]
7     DDR5 CL (CAS Latency)      16.67 ns (40 tCK @2.4GHz)
8     DDR5 BL16 Data Transfer    6.67 ns (16 beats)
9     PHY Read Path + DLL        3.33 ns
10    DFI Read Return            1.67 ns
11    ECC Decode                 3.33 ns (2 cycles @600MHz)
12    Read FIFO (CDC)            5.0 ns (2-3 cycles)
13    AXI4 R Response            2.5 ns
Total (Page Hit):                ~50 ns
Total (Page Miss, +tRCD):        ~64 ns
Total (Page Conflict, +tRP):     ~78 ns
```

### 12.2 Write Data Flow (Single Write, Page Hit)

```
Step  Component                  Latency
1     AXI4 AW+W handshake        2.5 ns
2     Command Decode + Addr Map  2.5 ns
3     Write Data FIFO (CDC)      5.0 ns
4     Scheduler Pipeline         6.67 ns
5     DFI Command Transfer       1.67 ns
6     PHY Gearbox Pack           1.67 ns  [B-01: 2 cycles @1.2GHz]
7     DDR5 CWL                   16.25 ns (39 tCK)
8     DDR5 BL16 Data Transfer    6.67 ns
9     AXI4 B Response            2.5 ns
Total (Page Hit):                ~45 ns
Total (Page Miss, +tRCD):        ~59 ns
```

### 12.3 Bank Group Interleaving Example

```
Sequential Access (Row-BG-Bank-Col mapping):
  Addr 0x0000 -> Row0, BG0, B0, Col0
  Addr 0x0040 -> Row0, BG1, B0, Col0
  Addr 0x0080 -> Row0, BG2, B0, Col0
  Addr 0x00C0 -> Row0, BG3, B0, Col0

Command Sequence:
  t0: RD B0(BG0)  --
  t1: RD B8(BG1)  tCCD_S=4tCK OK
  t2: RD B16(BG2) tCCD_S=4tCK OK
  t3: RD B24(BG3) tCCD_S=4tCK OK
  t4: RD B1(BG0)  tCCD_S=4tCK OK

Result: 1 read / 4 tCK = 100% pipeline utilization
vs Without BG Interleave: 1 read / 8 tCK (tCCD_L) = 50% utilization
Improvement: 2x throughput
```

### 12.4 Refresh Timing

```
FGR 2x Mode (DDR5-4800):
  tREFI = 1.95us (half period)
  Credit accumulation: 1 credit per 1.95us
  Max credits: 8

  Time:    0     1.95us  3.9us   5.85us  7.8us
  Credit:  0  -> 1    -> 2    -> 3    -> 4
  Bus:     BUSY  IDLE    BUSY    IDLE    BUSY
  Refresh:       REFsb   REFsb           REFsb
                 (BG0)   (BG1)           (BG2)

  Blocking per REFsb: tRFCsb = 160ns
  Other BGs continue access during REFsb
  Total overhead: ~3.5%
```

### 12.5 Training Sequence Timing

```
Total Training Time: ~62ms

Phase              Duration    Description
1  Power-On        0~100us     PLL lock, voltage stable
2  DDR5 Init       100us~2.2ms RESET_n sequence, MR writes
3  CA Training     2.2~7.2ms   Sweep CA delay, find window
4  Write Leveling  7.2~17.2ms  Align DQS to CK per byte lane
5  Read Gate       17.2~22.2ms Find DQS read enable window
6  Read DQ         22.2~37.2ms Sweep DQ read delay per bit
7  Write DQ        37.2~47.2ms Align DQ to DQS write edge
8  Vref Training   47.2~52.2ms Sweep Vref(DQ) level
9  DFE Training    52.2~57.2ms Tune DFE tap coefficients
10 Complete        ~62ms       Store results, enter IDLE
```

### 12.6 Cross-Clock-Domain Transfer

```
Async FIFO (User 400MHz -> Controller 600MHz):
  Write side: 400MHz, 256-bit data
  Read side:  600MHz, 256-bit data
  Depth: 64 entries
  Sync: Gray code pointers, 2-stage synchronizer
  Latency: 2-3 cycles (5~7.5ns)
  Safety: Full/Empty flags with 4-entry margin
```
