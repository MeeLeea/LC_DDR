// =============================================================================
// Module: ddr5_regfile
// Description: DDR5 controller register file (timing params + control)
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_regfile #(
    parameter int ADDR_W = 16,
    parameter int DATA_W = 32
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              reg_wr_en,
    input  logic [ADDR_W-1:0] reg_addr,
    input  logic [DATA_W-1:0] reg_wr_data,
    output logic [DATA_W-1:0] reg_rd_data,

    // Timing parameters
    output logic [15:0] tRCD, tRP, tRAS, tRC, tRFC, tRFCsb,
    output logic [15:0] tREFI, tWR, tRTP, CL, CWL,
    output logic [15:0] tCCD_L, tCCD_S, tRRD_L, tRRD_S, tFAW,
    output logic [15:0] tXS, tXP, tZQCAL, tZQCS,

    // Control outputs
    output logic [1:0]  fgr_mode,
    output logic        auto_ref_en, manual_ref, ecc_en, sreq_enter,
    output logic        train_start, train_abort, dll_en, dll_reset,
    output logic [2:0]  step_select,
    output logic [15:0] timeout_ms,
    output logic        cg_enable,
    output logic [15:0] idle_threshold,

    // Status inputs
    input  logic [3:0]  ctrl_state,
    input  logic        ctrl_ready,
    input  logic [3:0]  refresh_credit,
    input  logic        refresh_overflow,
    input  logic        ecc_sbe_detect, ecc_dbe_detect,
    input  logic        train_complete, train_error, train_in_progress,
    input  logic [2:0]  train_cur_step,
    input  logic [7:0]  train_progress_pct, train_error_code,
    input  logic        dll_locked, dll_lock_fail,
    input  logic [7:0]  dll_lock_count,
    input  logic        idle_detected, clk_gated
);

    // Register storage
    logic [31:0] r_tim0, r_tim1, r_tim2, r_tim3, r_tim4;
    logic [31:0] r_tim5, r_tim6, r_tim7, r_tim8, r_tim9;
    logic [31:0] r_ref_ctrl, r_ecc_ctrl, r_train_ctrl;
    logic [31:0] r_dll_ctrl, r_cg_ctrl;

    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_tim0 <= 32'h0022_0022;
            r_tim1 <= 32'h006F_004D;
            r_tim2 <= 32'h0180_02C5;
            r_tim3 <= 32'h0028_249F;
            r_tim4 <= 32'h0028_0012;
            r_tim5 <= 32'h0008_0027;
            r_tim6 <= 32'h0004_0008;
            r_tim7 <= 32'h0004_0010;
            r_tim8 <= 32'h000A_000A;
            r_tim9 <= 32'h0008_0008;
            r_ref_ctrl   <= 32'h0000_0001;
            r_ecc_ctrl   <= 32'h0000_0001;
            r_train_ctrl <= 32'h0000_0000;
            r_dll_ctrl   <= 32'h0000_0001;
            r_cg_ctrl    <= 32'h0000_0000;
        end else if (reg_wr_en) begin
            case (reg_addr)
                `REG_TIMING_0:     r_tim0       <= reg_wr_data;
                `REG_TIMING_1:     r_tim1       <= reg_wr_data;
                `REG_TIMING_2:     r_tim2       <= reg_wr_data;
                `REG_TIMING_3:     r_tim3       <= reg_wr_data;
                `REG_TIMING_4:     r_tim4       <= reg_wr_data;
                `REG_TIMING_5:     r_tim5       <= reg_wr_data;
                `REG_TIMING_6:     r_tim6       <= reg_wr_data;
                `REG_TIMING_7:     r_tim7       <= reg_wr_data;
                `REG_TIMING_8:     r_tim8       <= reg_wr_data;
                `REG_TIMING_9:     r_tim9       <= reg_wr_data;
                `REG_REFRESH_CTRL: r_ref_ctrl   <= reg_wr_data;
                `REG_ECC_CTRL:     r_ecc_ctrl   <= reg_wr_data;
                `REG_TRAIN_CTRL:   r_train_ctrl <= reg_wr_data;
                16'h0410:          r_dll_ctrl   <= reg_wr_data;
                16'h0420:          r_cg_ctrl    <= reg_wr_data;
                default: ;
            endcase
        end
    end

    // Read logic
    always_comb begin
        reg_rd_data = '0;
        case (reg_addr)
            `REG_TIMING_0:      reg_rd_data = r_tim0;
            `REG_TIMING_1:      reg_rd_data = r_tim1;
            `REG_TIMING_2:      reg_rd_data = r_tim2;
            `REG_TIMING_3:      reg_rd_data = r_tim3;
            `REG_TIMING_4:      reg_rd_data = r_tim4;
            `REG_TIMING_5:      reg_rd_data = r_tim5;
            `REG_TIMING_6:      reg_rd_data = r_tim6;
            `REG_TIMING_7:      reg_rd_data = r_tim7;
            `REG_TIMING_8:      reg_rd_data = r_tim8;
            `REG_TIMING_9:      reg_rd_data = r_tim9;
            `REG_REFRESH_CTRL:  reg_rd_data = r_ref_ctrl;
            `REG_REFRESH_STATUS: reg_rd_data = {14'h0, refresh_overflow, refresh_credit, 8'h0};
            `REG_ECC_CTRL:      reg_rd_data = r_ecc_ctrl;
            `REG_ECC_STATUS:    reg_rd_data = {29'h0, ecc_dbe_detect, ecc_sbe_detect, 1'h0};
            `REG_TRAIN_CTRL:    reg_rd_data = r_train_ctrl;
            `REG_TRAIN_STATUS:  reg_rd_data = {8'h0, train_error_code, train_cur_step, 2'h0, train_error, train_complete, train_in_progress};
            `REG_TRAIN_PROGRESS: reg_rd_data = {24'h0, train_progress_pct};
            16'h0410:           reg_rd_data = r_dll_ctrl;
            16'h0414:           reg_rd_data = {23'h0, dll_lock_fail, dll_lock_count};
            16'h0420:           reg_rd_data = r_cg_ctrl;
            16'h0424:           reg_rd_data = {30'h0, clk_gated, idle_detected};
            `REG_STATUS:        reg_rd_data = {27'h0, ctrl_state, ctrl_ready};
            `REG_VERSION:       reg_rd_data = 32'h0001_0000;
            default:            reg_rd_data = '0;
        endcase
    end

    // Timing output assignments
    assign tRCD=r_tim0[15:0]; assign tRP=r_tim0[31:16];
    assign tRAS=r_tim1[15:0]; assign tRC=r_tim1[31:16];
    assign tRFC=r_tim2[15:0]; assign tRFCsb=r_tim2[31:16];
    assign tREFI=r_tim3[15:0]; assign tWR=r_tim3[31:16];
    assign tRTP=r_tim4[15:0]; assign CL=r_tim4[31:16];
    assign CWL=r_tim5[15:0]; assign tCCD_L=r_tim5[31:16];
    assign tCCD_S=r_tim6[15:0]; assign tRRD_L=r_tim6[31:16];
    assign tRRD_S=r_tim7[15:0]; assign tFAW=r_tim7[31:16];
    assign tXS=r_tim8[15:0]; assign tXP=r_tim8[31:16];
    assign tZQCAL=r_tim9[15:0]; assign tZQCS=r_tim9[31:16];

    // Control output assignments
    assign fgr_mode    = r_ref_ctrl[3:2];
    assign auto_ref_en = r_ref_ctrl[0];
    assign manual_ref  = r_ref_ctrl[1];
    assign sreq_enter  = r_ref_ctrl[4];
    assign ecc_en      = r_ecc_ctrl[0];
    assign train_start = r_train_ctrl[0];
    assign train_abort = r_train_ctrl[1];
    assign step_select = r_train_ctrl[4:2];
    assign timeout_ms  = r_train_ctrl[31:16];
    assign dll_en      = r_dll_ctrl[0];
    assign dll_reset   = r_dll_ctrl[1];
    assign cg_enable      = r_cg_ctrl[0];
    assign idle_threshold = r_cg_ctrl[31:16];

endmodule
