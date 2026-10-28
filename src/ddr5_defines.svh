// =============================================================================
// DDR5 Memory Controller IP - Global Defines & Parameters
// Protocol: JEDEC DDR5 (JESD79-5) + DFI 5.1
// =============================================================================
`ifndef DDR5_DEFINES_SVH
`define DDR5_DEFINES_SVH

// --- AXI4 Interface Parameters ---
`define AXI_ID_W        8
`define AXI_ADDR_W      34
`define AXI_DATA_W      256
`define AXI_STRB_W      (`AXI_DATA_W / 8)
`define AXI_NUM_PORTS   4

// --- DDR5 Topology Parameters ---
`define DDR5_NUM_BG         4       // Bank Groups
`define DDR5_NUM_BANK_BG    8       // Banks per Bank Group
`define DDR5_NUM_BANKS      (`DDR5_NUM_BG * `DDR5_NUM_BANK_BG) // 32 banks
`define DDR5_ROW_W          18      // Row address width
`define DDR5_COL_W          10      // Column address width
`define DDR5_BG_W           3       // Bank Group bits (log2(4)=2, but DDR5 uses 3 bits)
`define DDR5_BA_W           3       // Bank Address bits
`define DDR5_RANK_W         2       // Rank select bits
`define DDR5_BL             16      // Burst Length (DDR5 default)
`define DDR5_NUM_SUBCH      2       // Dual sub-channel
`define DDR5_SUBCH_W        1       // Sub-channel select bit width (0=A, 1=B)
`define DDR5_SUBCH_SEL_BIT  3       // Address bit used for sub-channel selection

// --- DFI 5.1 Parameters ---
`define DFI_ADDR_W          18
`define DFI_BANK_W          6       // BG[2:0] + BA[2:0]
`define DFI_CS_W            2
`define DFI_DATA_W          128     // 64-bit x 2 sub-channels
`define DFI_MASK_W          16      // 8-bit x 2 sub-channels

// --- DFI 5.1 Additional Control/Status Signals (B-04) ---
`define DFI_PHYCSEL_W       1       // PHY chip-select / instance select
`define DFI_PARITY_W        1       // CA parity (dfi_parity_in)
`define DFI_RDDATA_DNV_W    2       // Read data not-valid per sub-channel
`define DFI_DRAM_CLK_DIS_W  2       // DRAM clock disable per sub-channel
`define DFI_FREQ_RATIO_W    2       // Frequency-ratio indication

// --- PHY Parameters ---
`define PHY_DQ_PER_SUBCH    32
`define PHY_ECC_PER_SUBCH   8
`define PHY_DLL_BITS        8       // DLL delay control bits
`define PHY_DLL_STEPS       256     // 2^8 delay steps
`define PHY_TRAIN_STEPS     7       // CA, WL, RGT, RDQ, WDQ, Vref, DFE

// --- FIFO Parameters ---
`define CDC_FIFO_ADDR_W     6       // Depth = 64
`define CMD_FIFO_ADDR_W     4       // Depth = 16

// --- Timing Engine Parameters ---
`define TIM_PARAM_W         16      // Timing parameter register width
`define TIM_CNT_W           16      // Countdown counter width
`define NUM_TIM_PARAMS      20      // Number of timing parameters

// --- ECC Parameters ---
`define ECC_DATA_W          32      // Data width per sub-channel
`define ECC_CODE_W          8       // ECC code width (Hsiao SEC-DED)
`define ECC_CODEW_W         (`ECC_DATA_W + `ECC_CODE_W) // 40-bit codeword

// --- APB Parameters ---
`define APB_ADDR_W          16
`define APB_DATA_W          32

// --- Interrupt Parameters ---
`define IRQ_NUM             10

// --- Register Address Offsets ---
`define REG_CTRL            16'h0000
`define REG_STATUS          16'h0004
`define REG_VERSION         16'h0008
`define REG_CAPABILITY      16'h000C
`define REG_TIMING_0        16'h0100
`define REG_TIMING_1        16'h0104
`define REG_TIMING_2        16'h0108
`define REG_TIMING_3        16'h010C
`define REG_TIMING_4        16'h0110
`define REG_TIMING_5        16'h0114
`define REG_TIMING_6        16'h0118
`define REG_TIMING_7        16'h011C
`define REG_TIMING_8        16'h0120
`define REG_TIMING_9        16'h0124
`define REG_REFRESH_CTRL    16'h0200
`define REG_REFRESH_STATUS  16'h0204
`define REG_REFRESH_COUNT   16'h0208
`define REG_ECC_CTRL        16'h0300
`define REG_ECC_STATUS      16'h0304
`define REG_ECC_ERR_ADDR    16'h0308
`define REG_ECC_ERR_DATA    16'h030C
`define REG_ECC_ERR_SYN     16'h0310
`define REG_ECC_SBE_CNT     16'h0314
`define REG_ECC_DBE_CNT     16'h0318
`define REG_TRAIN_CTRL      16'h0400
`define REG_TRAIN_STATUS    16'h0404
`define REG_TRAIN_PROGRESS  16'h0408
`define REG_PERF_CTRL       16'h0700
`define REG_IRQ_STATUS      16'h0800
`define REG_IRQ_ENABLE      16'h0804
`define REG_IRQ_RAW         16'h0808
`define REG_DEBUG_CTRL      16'h0900

// --- AXI4 Response Codes ---
`define AXI_RESP_OKAY       2'b00
`define AXI_RESP_EXOKAY     2'b01
`define AXI_RESP_SLVERR     2'b10
`define AXI_RESP_DECERR     2'b11

// --- AXI4 Burst Types ---
`define AXI_BURST_FIXED     2'b00
`define AXI_BURST_INCR      2'b01
`define AXI_BURST_WRAP      2'b10

`endif // DDR5_DEFINES_SVH
