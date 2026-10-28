// =============================================================================
// Module: ddr5_addr_mapper
// Description: AXI address to DDR5 Row/BG/Bank/Col mapping
//              Supports configurable mapping modes
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_addr_mapper (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // AXI address input
    input  logic [`AXI_ADDR_W-1:0]  axi_addr,
    
    // DDR5 address output
    output logic [`DDR5_ROW_W-1:0]  row_addr,
    output logic [`DDR5_BG_W-1:0]   bg_addr,
    output logic [`DDR5_BA_W-1:0]   bank_addr,
    output logic [`DDR5_COL_W-1:0]  col_addr,
    output logic [`DDR5_RANK_W-1:0] rank_addr,
    output logic                     sub_channel,  // 0=A, 1=B
    
    // Mapping mode (0: Row-BG-Bank-Col, 1: BG-Row-Bank-Col)
    input  logic [1:0]              map_mode
);

    // Address field extraction (Mode 0: Row-BG-Bank-Col)
    logic [`DDR5_ROW_W-1:0]  row_m0;
    logic [`DDR5_BG_W-1:0]   bg_m0;
    logic [`DDR5_BA_W-1:0]   bank_m0;
    logic [`DDR5_COL_W-1:0]  col_m0;
    logic [`DDR5_RANK_W-1:0] rank_m0;

    // Address field extraction (Mode 1: BG-Row-Bank-Col)
    logic [`DDR5_ROW_W-1:0]  row_m1;
    logic [`DDR5_BG_W-1:0]   bg_m1;
    logic [`DDR5_BA_W-1:0]   bank_m1;
    logic [`DDR5_COL_W-1:0]  col_m1;
    logic [`DDR5_RANK_W-1:0] rank_m1;

    // Sub-channel select: derived from address bit[`DDR5_SUBCH_SEL_BIT].
    // In the default 256-bit full-width datapath the controller broadcasts
    // chip-select to both sub-channels (protocol_fsm DUAL_CH_BROADCAST=1),
    // so this output is informational; it becomes the active cs selector
    // only when DUAL_CH_BROADCAST=0.
    assign sub_channel = axi_addr[`DDR5_SUBCH_SEL_BIT];

    // Mode 0: Row-BG-Bank-Col (default, optimized for bank interleave)
    // [33:32] Rank, [31:14] Row, [13:11] BG, [10:8] Bank, [7:0] Col
    assign rank_m0 = axi_addr[33:32];
    assign row_m0  = axi_addr[31:14];
    assign bg_m0   = axi_addr[13:11];
    assign bank_m0 = axi_addr[10:8];
    assign col_m0  = axi_addr[7:0];

    // Mode 1: BG-Row-Bank-Col (optimized for row hit)
    assign bg_m1   = axi_addr[33:31];
    assign rank_m1 = axi_addr[30:29];
    assign row_m1  = axi_addr[28:11];
    assign bank_m1 = axi_addr[10:8];
    assign col_m1  = axi_addr[7:0];

    // Output mux based on map_mode
    always_comb begin
        case (map_mode)
            2'b00: begin // Mode 0
                row_addr  = row_m0;
                bg_addr   = bg_m0;
                bank_addr = bank_m0;
                col_addr  = col_m0;
                rank_addr = rank_m0;
                // sub_channel is combinational (always axi_addr[3])
            end
            2'b01: begin // Mode 1
                row_addr  = row_m1;
                bg_addr   = bg_m1;
                bank_addr = bank_m1;
                col_addr  = col_m1;
                rank_addr = rank_m1;
            end
            default: begin // Default to Mode 0
                row_addr  = row_m0;
                bg_addr   = bg_m0;
                bank_addr = bank_m0;
                col_addr  = col_m0;
                rank_addr = rank_m0;
            end
        endcase
    end

endmodule
