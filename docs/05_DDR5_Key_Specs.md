# DDR5 IP - Key Specifications Summary (Part 5)

## 8. Key Specification Parameters

### 8.1 System-Level Performance Specifications

| Parameter | DDR5-4800 | DDR5-5600 | DDR5-6400 | Unit | Notes |
|-----------|-----------|-----------|-----------|------|-------|
| **Data Rate** | 4800 | 5600 | 6400 | MT/s | DDR (Double Data Rate) |
| **Clock Frequency** | 2400 | 2800 | 3200 | MHz | DDR CK frequency |
| **Theoretical Bandwidth** | 38.4 | 44.8 | 51.2 | GB/s | 64-bit dual sub-channel |
| **Effective Bandwidth** | ≥32.6 | ≥38.1 | ≥43.5 | GB/s | ≥85% utilization target |
| **CAS Latency (CL)** | 40 | 46 | 52 | tCK | Read latency |
| **CAS Write Latency (CWL)** | 39 | 45 | 51 | tCK | Write latency |
| **Read Latency (single)** | ~18 | ~18 | ~18 | ns | CL + tRCD + controller overhead |
| **Write Latency (single)** | ~17 | ~17 | ~17 | ns | CWL + tRCD + controller overhead |
| **Burst Length** | 16 | 16 | 16 | beats | BL16 (DDR5 default) |
| **Timing Margin** | ≥10% | ≥10% | ≥10% | tCK | Setup + Hold |

### 8.2 Interface Specifications

| Interface | Width | Frequency | Protocol | Direction |
|-----------|-------|-----------|----------|-----------|
| **AXI4 User Interface** | 256-bit data | 400 MHz | AXI4 | Bidirectional |
| **APB Configuration** | 32-bit data | 100 MHz | APB v2.0 | Bidirectional |
| **DFI 5.1 (Controller↔PHY)** | 64-bit × 2 | 1.2~1.6 GHz | DFI 5.1 | Bidirectional |
| **DDR5 Physical (PHY↔DRAM)** | 32+8 bit × 2 | 2.4~3.2 GHz | DDR5 | Bidirectional |

### 8.3 Capacity Specifications

| Parameter | Min | Max | Unit | Notes |
|-----------|-----|-----|------|-------|
| **Address Width** | 28 | 34 | bits | 256 MB ~ 16 GB |
| **Ranks** | 1 | 16 | ranks | Per channel |
| **Bank Groups** | 1 | 8 | groups | DDR5: 4 BG typical |
| **Banks per Group** | 1 | 8 | banks | DDR5: 8 banks/BG |
| **Rows per Bank** | 1K | 256K | rows | 10~18 bit row address |
| **Columns per Row** | 512 | 4K | columns | 9~12 bit column address |
| **Total Capacity** | 256 MB | 16 GB | bytes | Per IP instance |

### 8.4 Resource Utilization (FPGA Target)

| Resource | Controller | PHY Digital | Total | Unit |
|----------|-----------|-------------|-------|------|
| **LUTs** | ≤15,000 | ≤5,000 | ≤20,000 | LUT4/5/6 |
| **Flip-Flops** | ≤20,000 | ≤8,000 | ≤28,000 | FFs |
| **Block RAM** | ≤32 | ≤16 | ≤48 | BRAM36 |
| **DSP Slices** | 0 | 0 | 0 | — |
| **PLL/MMCM** | 0 | 2~4 | 2~4 | Clock generation |

### 8.5 Resource Utilization (ASIC Target @7nm)

| Resource | Controller | PHY Digital | Total | Unit |
|----------|-----------|-------------|-------|------|
| **Gate Count** | ≤500K | ≤200K | ≤700K | gates |
| **Area** | ≤1.5 | ≤0.5 | ≤2.0 | mm² |
| **Power (active)** | ≤40 | ≤10 | ≤50 | mW @1GHz |
| **Power (idle)** | ≤5 | ≤2 | ≤7 | mW |
| **Leakage** | ≤2 | ≤1 | ≤3 | mW |

### 8.6 Quality of Service (QoS) Specifications

| QoS Parameter | Port 0 (CPU) | Port 1 (DMA) | Port 2 (Accel) | Port 3 (Debug) |
|---------------|--------------|--------------|----------------|----------------|
| **Priority** | Strict High | Medium | Medium | Low |
| **Arbitration** | Priority | WRR (w=4) | WRR (w=8) | WRR (w=1) |
| **Max Latency** | 100 ns | 500 ns | 1 μs | 10 μs |
| **Min Bandwidth** | 8 GB/s | 8 GB/s | 16 GB/s | 1 GB/s |
| **Guaranteed** | Yes | Yes | Yes | Best-effort |

### 8.7 Reliability & Robustness Specifications

| Parameter | Specification | Notes |
|-----------|--------------|-------|
| **ECC Coverage** | SEC-DED per 32-bit | Single-bit correct, double-bit detect |
| **CRC Coverage** | CRC-8 per write burst | Optional, detect DQ link errors |
| **Error Reporting** | Interrupt + status register | Real-time error notification |
| **Training Success Rate** | ≥99.9% | First-attempt success rate |
| **Timing Closure** | 100% paths met | All PVT corners |
| **Deadlock Prevention** | Hardware monitor | Cmd/Ref stall timeout + forced-refresh recovery + IRQ (B-03) |
| **Illegal Command Handling** | Graceful degradation | Error interrupt, no crash |

### 8.8 Configurability Specifications

| Parameter | Range | Default | Notes |
|-----------|-------|---------|-------|
| **Data Rate** | 3200~6400 MT/s | 4800 | Runtime configurable |
| **User Data Width** | 128/256/512 bit | 256 | Synthesis-time parameter |
| **AXI ID Width** | 4~16 bit | 8 | Synthesis-time parameter |
| **Address Width** | 28~34 bit | 34 | Synthesis-time parameter |
| **Refresh Mode** | 1×/2×/4× FGR | 2× | Runtime configurable |
| **Scheduler Algorithm** | FR-FCFS / PAR-BS | FR-FCFS | Runtime configurable |
| **ECC Enable** | On/Off | On | Runtime configurable |
| **CRC Enable** | On/Off | Off | Runtime configurable |
