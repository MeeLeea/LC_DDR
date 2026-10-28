# DDR5 IP - Interface Definitions (Part 6)

## 9. Interface Definitions

### 9.1 AXI4 User Interface

#### AXI4 Write Address Channel (AW)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| awid | 8 | Input | Write address ID |
| awaddr | 34 | Input | Write address |
| awlen | 8 | Input | Burst length (0~255) |
| awsize | 3 | Input | Burst size (0~7, 2^n bytes) |
| awburst | 2 | Input | Burst type (00=FIXED, 01=INCR, 10=WRAP) |
| awlock | 1 | Input | Lock type (0=normal, 1=exclusive) |
| awcache | 4 | Input | Cache type |
| awprot | 3 | Input | Protection type |
| awqos | 4 | Input | QoS priority (optional) |
| awvalid | 1 | Input | Write address valid |
| awready | 1 | Output | Write address ready |

#### AXI4 Write Data Channel (W)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| wdata | 256 | Input | Write data |
| wstrb | 32 | Input | Write strobes (byte enables) |
| wlast | 1 | Input | Write last (burst end) |
| wvalid | 1 | Input | Write data valid |
| wready | 1 | Output | Write data ready |

#### AXI4 Write Response Channel (B)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| bid | 8 | Output | Write response ID |
| bresp | 2 | Output | Write response (00=OKAY, 01=EXOKAY, 10=SLVERR, 11=DECERR) |
| bvalid | 1 | Output | Write response valid |
| bready | 1 | Input | Write response ready |

#### AXI4 Read Address Channel (AR)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| arid | 8 | Input | Read address ID |
| araddr | 34 | Input | Read address |
| arlen | 8 | Input | Burst length (0~255) |
| arsize | 3 | Input | Burst size (0~7, 2^n bytes) |
| arburst | 2 | Input | Burst type |
| arlock | 1 | Input | Lock type |
| arcache | 4 | Input | Cache type |
| arprot | 3 | Input | Protection type |
| arqos | 4 | Input | QoS priority (optional) |
| arvalid | 1 | Input | Read address valid |
| arready | 1 | Output | Read address ready |

#### AXI4 Read Data Channel (R)

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| rid | 8 | Output | Read data ID |
| rdata | 256 | Output | Read data |
| rresp | 2 | Output | Read response |
| rlast | 1 | Output | Read last (burst end) |
| rvalid | 1 | Output | Read data valid |
| rready | 1 | Input | Read data ready |

### 9.2 APB Configuration Interface

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| paddr | 16 | Input | APB address |
| pwdata | 32 | Input | APB write data |
| prdata | 32 | Output | APB read data |
| psel | 1 | Input | APB select |
| penable | 1 | Input | APB enable |
| pwrite | 1 | Input | APB write enable |
| pready | 1 | Output | APB ready |
| pslverr | 1 | Output | APB slave error |

### 9.3 DFI 5.1 Interface (Controller ↔ PHY)

#### DFI Control Interface

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| dfi_address | 18 | Output | Row/Column address |
| dfi_bank | 6 | Output | Bank address (BG[2:0] + BA[2:0]) |
| dfi_cs_n | 2 | Output | Chip select (dual sub-channel) |
| dfi_act_n | 1 | Output | Activate command |
| dfi_ras_n | 1 | Output | Row address strobe |
| dfi_cas_n | 1 | Output | Column address strobe |
| dfi_we_n | 1 | Output | Write enable |
| dfi_reset_n | 1 | Output | DDR reset |
| dfi_cke | 2 | Output | Clock enable (dual sub-channel) |
| dfi_odt | 2 | Output | On-die termination |
| dfi_parity_in | 1 | Output | Command/address parity |
| dfi_phycsel | 1 | Output | PHY instance / chip select (B-04) |
| dfi_dram_clk_disable | 2 | Output | DRAM clock disable per sub-channel (B-04) |
| dfi_freq_ratio | 2 | Output | Frequency-ratio indication (B-04) |

> **B-04 note**: `dfi_phycsel`, `dfi_dram_clk_disable`, `dfi_freq_ratio` and
> `dfi_rddata_dnv` are now implemented on `ddr5_dfi_bridge` (driven) and
> `ddr5_phy_digital` (consumed / driven for dnv), and wired through
> `ddr5_controller`. `dfi_parity_in` is tied to 0 (parity generation is an
> opt-in feature); `dfi_rddata_crc` / `dfi_parity_rddata` remain reserved for
> the PHY-side checkers.

#### DFI Write Data Interface

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| dfi_wrdata | 128 | Output | Write data (64-bit × 2 sub-channels) |
| dfi_wrdata_mask | 16 | Output | Write data mask (8-bit × 2 sub-channels) |
| dfi_wrdata_en | 1 | Output | Write data enable |
| dfi_parity_wrdata | 2 | Output | Write data parity |

#### DFI Read Data Interface

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| dfi_rddata | 128 | Input | Read data (64-bit × 2 sub-channels) |
| dfi_rddata_valid | 1 | Input | Read data valid |
| dfi_rddata_dnv | 2 | Input | Read data not valid (per sub-channel) |
| dfi_parity_rddata | 2 | Input | Read data parity |
| dfi_rddata_crc | 2 | Input | Read data CRC error |

#### DFI Status Interface

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| dfi_init_complete | 1 | Input | PHY initialization complete |
| dfi_init_start | 1 | Output | Start PHY initialization |
| dfi_lp_wakeup | 4 | Output | Low-power wake-up request |
| dfi_lp_ctrl | 4 | Output | Low-power control |
| dfi_lp_data | 32 | Output | Low-power data |
| dfi_error | 8 | Input | PHY error status |
| dfi_error_info | 32 | Input | PHY error information |

#### DFI Training Interface

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| dfi_train_start | 1 | Output | Start training sequence |
| dfi_train_complete | 1 | Input | Training complete |
| dfi_train_error | 1 | Input | Training error |
| dfi_train_result | 32 | Input | Training result data |

### 9.4 DDR5 Physical Signals (PHY ↔ DRAM)

#### DDR5 Command/Address Signals

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| CK_t / CK_c | 2 | Output | Differential clock (per sub-channel) |
| CKE | 2 | Output | Clock enable (per sub-channel) |
| CS_n | 2 | Output | Chip select (per sub-channel) |
| CA[6:0] | 14 | Output | Command/Address bus (7-bit × 2 sub-channels) |
| RESET_n | 1 | Output | DDR5 reset (active low) |
| ACT_n | 2 | Output | Activate command (per sub-channel) |
| RAS_n/A16 | 2 | Output | RAS or address bit 16 |
| CAS_n/A15 | 2 | Output | CAS or address bit 15 |
| WE_n/A14 | 2 | Output | WE or address bit 14 |

#### DDR5 Data Signals

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| DQ[31:0] | 64 | Bidirectional | Data bus (32-bit × 2 sub-channels) |
| DQS_t[3:0] / DQS_c[3:0] | 8 | Bidirectional | Differential data strobe (4-bit × 2 sub-channels) |
| DM_n[3:0] | 8 | Output | Data mask (4-bit × 2 sub-channels) |
| CB[7:0] | 16 | Bidirectional | Check bits/ECC (8-bit × 2 sub-channels) |

#### DDR5 Power/Control Signals

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| ZQ | 2 | Output | ZQ calibration reference |
| ALERT_n | 2 | Input | Alert signal (error notification) |
| PARITY | 2 | Output | Command/address parity |
| TEN | 2 | Output | Test enable |
| VREF_CA | 2 | Output | CA Vref reference |
| VREF_DQ | 2 | Output | DQ Vref reference |

### 9.5 Interrupt Interface

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| irq | 1 | Output | Interrupt request (active high) |
| irq_status | 32 | Output | Interrupt status register |
| irq_enable | 32 | Input | Interrupt enable register |
| irq_clear | 32 | Input | Interrupt clear register |

**Interrupt Sources:**
- Bit 0: ECC single-bit error corrected
- Bit 1: ECC double-bit error detected
- Bit 2: CRC error detected
- Bit 3: Training complete
- Bit 4: Training error
- Bit 5: Refresh overflow (credit = 8)
- Bit 6: Temperature alert
- Bit 7: Illegal command detected
- Bit 8: DFI error
- Bit 9: PHY error
- Bit 10~31: Reserved
