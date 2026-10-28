// =============================================================================
// Module: ddr5_timing_engine
// Description: Per-bank countdown timer engine for all JEDEC DDR5 params
//              Checks timing constraints before command issue
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_timing_engine #(
    parameter int NUM_BANKS  = `DDR5_NUM_BANKS,
    parameter int TIM_W      = `TIM_CNT_W,
    parameter int NUM_PARAMS = `NUM_TIM_PARAMS
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Timing parameter registers (from APB config)
    input  logic [15:0]           tRCD, tRP, tRAS, tRC, tRFC, tRFCsb,
    input  logic [15:0]           tREFI, tWR, tRTP, tCCD_L, tCCD_S,
    input  logic [15:0]           tRRD_L, tRRD_S, tFAW, tXS, tXP,
    input  logic [15:0]           CL, CWL, tZQCAL, tZQCS,

    // Command issue interface
    input  logic                  cmd_valid,
    input  logic [3:0]            cmd_type,  // ACT/RD/WR/PRE/REF etc
    input  logic [4:0]            cmd_bank,  // 0~31
    input  logic [2:0]            cmd_bg,    // bank group
    output logic                  cmd_timing_ok,

    // Global timing check outputs
    output logic                  tFAW_ok,
    output logic                  tRRD_ok,
    output logic                  tCCD_ok
);

    // --- Command type encoding ---
    localparam CMD_NOP  = 4'h0;
    localparam CMD_ACT  = 4'h1;
    localparam CMD_RD   = 4'h2;
    localparam CMD_WR   = 4'h3;
    localparam CMD_PRE  = 4'h4;
    localparam CMD_REF  = 4'h5;
    localparam CMD_SREF = 4'h6;
    localparam CMD_ZQ   = 4'h7;

    // --- Per-bank timers ---
    logic [TIM_W-1:0] bank_tRCD_cnt  [NUM_BANKS];
    logic [TIM_W-1:0] bank_tRP_cnt   [NUM_BANKS];
    logic [TIM_W-1:0] bank_tRAS_cnt  [NUM_BANKS];
    logic [TIM_W-1:0] bank_tWR_cnt   [NUM_BANKS];
    logic [TIM_W-1:0] bank_tRTP_cnt  [NUM_BANKS];

    // --- Per-bank-group timers ---
    logic [TIM_W-1:0] bg_tCCD_cnt    [`DDR5_NUM_BG];
    logic [TIM_W-1:0] bg_tRRD_cnt    [`DDR5_NUM_BG];

    // --- Global timers ---
    logic [TIM_W-1:0] bank_tRC_cnt    [NUM_BANKS];
    logic [TIM_W-1:0] global_tRFC_cnt;
    logic [TIM_W-1:0] global_tFAW_cnt;

    // --- tFAW sliding window (track last 4 ACT timestamps) ---
    logic [TIM_W-1:0] faw_window [4];
    logic [15:0]      global_cycle_cnt;

    // Cycle counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            global_cycle_cnt <= '0;
        else
            global_cycle_cnt <= global_cycle_cnt + 16'd1;
    end

    // --- Countdown decrement logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int b = 0; b < NUM_BANKS; b++) begin
                bank_tRCD_cnt[b] <= '0;
                bank_tRP_cnt[b]  <= '0;
                bank_tRAS_cnt[b] <= '0;
                bank_tWR_cnt[b]  <= '0;
                bank_tRTP_cnt[b] <= '0;
            end
            for (int g = 0; g < `DDR5_NUM_BG; g++) begin
                bg_tCCD_cnt[g] <= '0;
                bg_tRRD_cnt[g] <= '0;
            end
            for (int b = 0; b < NUM_BANKS; b++) bank_tRC_cnt[b] <= '0;
            global_tRFC_cnt <= '0;
            global_tFAW_cnt <= '0;
            for (int w = 0; w < 4; w++) faw_window[w] <= '0;
        end else begin
            // Decrement all non-zero timers
            for (int b = 0; b < NUM_BANKS; b++) begin
                if (bank_tRCD_cnt[b] > 0) bank_tRCD_cnt[b] <= bank_tRCD_cnt[b] - 1;
                if (bank_tRP_cnt[b]  > 0) bank_tRP_cnt[b]  <= bank_tRP_cnt[b]  - 1;
                if (bank_tRAS_cnt[b] > 0) bank_tRAS_cnt[b] <= bank_tRAS_cnt[b] - 1;
                if (bank_tWR_cnt[b]  > 0) bank_tWR_cnt[b]  <= bank_tWR_cnt[b]  - 1;
                if (bank_tRTP_cnt[b] > 0) bank_tRTP_cnt[b] <= bank_tRTP_cnt[b] - 1;
            end
            for (int g = 0; g < `DDR5_NUM_BG; g++) begin
                if (bg_tCCD_cnt[g] > 0) bg_tCCD_cnt[g] <= bg_tCCD_cnt[g] - 1;
                if (bg_tRRD_cnt[g] > 0) bg_tRRD_cnt[g] <= bg_tRRD_cnt[g] - 1;
            end
            for (int b = 0; b < NUM_BANKS; b++) begin
                if (bank_tRC_cnt[b] > 0) bank_tRC_cnt[b] <= bank_tRC_cnt[b] - 1;
            end
            if (global_tRFC_cnt > 0) global_tRFC_cnt <= global_tRFC_cnt - 1;
            if (global_tFAW_cnt > 0) global_tFAW_cnt <= global_tFAW_cnt - 1;

            // Load timers on command issue
            if (cmd_valid) begin
                case (cmd_type)
                    CMD_ACT: begin
                        bank_tRCD_cnt[cmd_bank] <= tRCD;
                        bank_tRP_cnt[cmd_bank]  <= '0; // Row now open
                        bank_tRAS_cnt[cmd_bank] <= tRAS;
                        bg_tRRD_cnt[cmd_bg]     <= (cmd_bg == 0) ? tRRD_S : tRRD_L;
                        bank_tRC_cnt[cmd_bank]  <= tRC;
                        // tFAW sliding window shift
                        faw_window[3] <= faw_window[2];
                        faw_window[2] <= faw_window[1];
                        faw_window[1] <= faw_window[0];
                        faw_window[0] <= global_cycle_cnt;
                    end
                    CMD_RD: begin
                        bg_tCCD_cnt[cmd_bg]     <= tCCD_L;
                        bank_tRTP_cnt[cmd_bank] <= tRTP;
                    end
                    CMD_WR: begin
                        bg_tCCD_cnt[cmd_bg]     <= tCCD_L;
                        bank_tWR_cnt[cmd_bank]  <= tWR;
                    end
                    CMD_PRE: begin
                        bank_tRP_cnt[cmd_bank]  <= tRP;
                        bank_tRCD_cnt[cmd_bank] <= '0;
                        bank_tRAS_cnt[cmd_bank] <= '0;
                    end
                    CMD_REF: begin
                        global_tRFC_cnt <= tRFC;
                    end
                    default: ; // NOP, SREF, ZQ etc
                endcase
            end
        end
    end

    // --- Timing check for incoming command ---
    logic bank_rdy, bg_rdy, global_rdy;

    always_comb begin
        bank_rdy   = 1'b1;
        bg_rdy     = 1'b1;
        global_rdy = 1'b1;

        case (cmd_type)
            CMD_ACT: begin
                // Need tRP done (bank idle), tRC done, tRRD done, tFAW ok
                bank_rdy   = (bank_tRP_cnt[cmd_bank] == 0) && (bank_tRCD_cnt[cmd_bank] == 0) && (bank_tRC_cnt[cmd_bank] == 0);
                global_rdy = (global_tRFC_cnt == 0);
            end
            CMD_RD: begin
                bank_rdy = (bank_tRCD_cnt[cmd_bank] == 0);
                bg_rdy   = (bg_tCCD_cnt[cmd_bg] == 0);
            end
            CMD_WR: begin
                bank_rdy = (bank_tRCD_cnt[cmd_bank] == 0);
                bg_rdy   = (bg_tCCD_cnt[cmd_bg] == 0);
            end
            CMD_PRE: begin
                bank_rdy = (bank_tRAS_cnt[cmd_bank] == 0) && (bank_tWR_cnt[cmd_bank] == 0);
            end
            CMD_REF: begin
                global_rdy = (global_tRFC_cnt == 0);
            end
            default: ;
        endcase
    end

    // tFAW check: 4th ACT must be >= tFAW after 1st in window
    assign tFAW_ok = (global_cycle_cnt - faw_window[3]) >= tFAW;
    assign tRRD_ok = (bg_tRRD_cnt[cmd_bg] == 0);
    assign tCCD_ok = (bg_tCCD_cnt[cmd_bg] == 0);

    assign cmd_timing_ok = bank_rdy & bg_rdy & global_rdy & tFAW_ok;

endmodule
