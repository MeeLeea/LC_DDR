// =============================================================================
// Module: ddr5_phy_digital
// Description: DDR5 PHY digital logic top module
//              Integrates DLL, training engine, gearbox, clock gating
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_phy_digital #(
    parameter int USER_W = 256,
    parameter int DFI_W  = 128,
    parameter int DLL_BITS = `PHY_DLL_BITS,
    parameter int NUM_STEPS = `PHY_TRAIN_STEPS
)(
    // Clocks and reset
    input  logic        ctrl_clk,
    input  logic        dfi_clk,
    input  logic        phy_clk,
    input  logic        rst_n,

    // DFI interface (from DFI bridge)
    input  logic        dfi_cmd_valid,
    output logic        dfi_cmd_ready,
    input  logic [17:0] dfi_address,
    input  logic [5:0]  dfi_bank,
    input  logic [1:0]  dfi_cs_n,
    input  logic        dfi_act_n,
    input  logic        dfi_ras_n,
    input  logic        dfi_cas_n,
    input  logic        dfi_we_n,
    input  logic [127:0] dfi_wrdata,
    input  logic [15:0]  dfi_wrdata_mask,
    input  logic         dfi_wrdata_en,
    output logic [127:0] dfi_rddata,
    output logic         dfi_rddata_valid,

    // --- DFI 5.1 additional control/status signals (B-04) ---
    input  logic [`DFI_PHYCSEL_W-1:0]      dfi_phycsel,          // PHY instance select
    input  logic [`DFI_PARITY_W-1:0]       dfi_parity_in,        // CA parity from MC
    input  logic [`DFI_DRAM_CLK_DIS_W-1:0] dfi_dram_clk_disable, // DRAM clock disable per sub-ch
    input  logic [`DFI_FREQ_RATIO_W-1:0]   dfi_freq_ratio,       // Frequency-ratio indication
    output logic [`DFI_RDDATA_DNV_W-1:0]   dfi_rddata_dnv,       // Read data not-valid per sub-ch

    // Write data interface (from controller)
    input  logic        wr_user_valid,
    input  logic [USER_W-1:0] wr_user_data,
    output logic        wr_user_ready,

    // Read data interface (to controller)
    output logic        rd_user_valid,
    output logic [USER_W-1:0] rd_user_data,
    input  logic        rd_user_ready,

    // Training control
    input  logic        train_start,
    input  logic        train_abort,
    input  logic [2:0]  step_select,
    input  logic [15:0] timeout_ms,
    output logic        train_complete,
    output logic        train_error,
    output logic [2:0]  cur_step,
    output logic [7:0]  progress_pct,
    output logic [7:0]  error_code,

    // DLL control
    input  logic        dll_en,
    input  logic        dll_reset,
    output logic        dll_locked,
    output logic [DLL_BITS-1:0] dll_delay_code,
    input  logic        phase_early,
    input  logic        phase_late,
    output logic [7:0]  dll_lock_count,
    output logic        dll_lock_fail,

    // Clock gating control
    input  logic        cg_enable,
    input  logic [15:0] idle_threshold,
    output logic        ctrl_clk_en,
    output logic        dfi_clk_en,
    output logic        phy_clk_en,
    output logic        idle_detected,
    output logic        clk_gated,

    // PHY initialization
    output logic        phy_init_complete,

    // DDR5 physical interface (to analog PHY)
    output logic [31:0] dq_out,
    input  logic [31:0] dq_in,
    output logic [3:0]  dqs_out,
    input  logic [3:0]  dqs_in,
    output logic [17:0] addr_out,
    output logic [5:0]  bank_out,
    output logic [1:0]  cs_n_out,
    output logic        act_n_out,
    output logic        ras_n_out,
    output logic        cas_n_out,
    output logic        we_n_out,
    output logic [1:0]  cke_out,
    output logic [1:0]  odt_out,
    output logic        reset_n_out
);

    // Internal signals
    logic        wr_dfi_valid;
    logic [DFI_W-1:0] wr_dfi_data;
    logic        wr_dfi_ready;

    logic        rd_dfi_valid;
    logic [DFI_W-1:0] rd_dfi_data;
    logic        rd_dfi_ready;

    // Gearbox instance
    ddr5_gearbox #(
        .USER_W (USER_W),
        .DFI_W  (DFI_W)
    ) u_gearbox (
        .clk           (dfi_clk),
        .rst_n         (rst_n),
        .wr_user_valid (wr_user_valid),
        .wr_user_data  (wr_user_data),
        .wr_user_ready (wr_user_ready),
        .wr_dfi_valid  (wr_dfi_valid),
        .wr_dfi_data   (wr_dfi_data),
        .wr_dfi_ready  (wr_dfi_ready),
        .rd_dfi_valid  (rd_dfi_valid),
        .rd_dfi_data   (rd_dfi_data),
        .rd_dfi_ready  (rd_dfi_ready),
        .rd_user_valid (rd_user_valid),
        .rd_user_data  (rd_user_data),
        .rd_user_ready (rd_user_ready)
    );

    // DLL controller instance
    ddr5_dll_ctrl #(
        .DLL_BITS  (DLL_BITS),
        .DLL_STEPS (`PHY_DLL_STEPS)
    ) u_dll_ctrl (
        .clk            (phy_clk),
        .rst_n          (rst_n),
        .dll_en         (dll_en),
        .dll_reset      (dll_reset),
        .dll_locked     (dll_locked),
        .dll_delay_code (dll_delay_code),
        .phase_early    (phase_early),
        .phase_late     (phase_late),
        .dll_lock_count (dll_lock_count),
        .dll_lock_fail  (dll_lock_fail)
    );

    // Training engine instance
    logic        pattern_wr_en;
    logic [31:0] pattern_data;
    logic        pattern_rd_valid;
    logic [31:0] pattern_rd_data;
    logic        pattern_pass;

    logic [7:0]  ca_delay_result;
    logic [7:0]  wl_delay_result [8];
    logic [7:0]  rgt_delay_result [8];
    logic [7:0]  rdq_delay_result [32];
    logic [7:0]  wdq_delay_result [32];
    logic [6:0]  vref_code_result;
    logic [7:0]  dfe_tap_result [4];
    logic        train_in_progress;

    ddr5_training_engine #(
        .DLL_BITS  (DLL_BITS),
        .NUM_STEPS (NUM_STEPS)
    ) u_training (
        .clk              (ctrl_clk),
        .rst_n            (rst_n),
        .train_start      (train_start),
        .train_abort      (train_abort),
        .step_select      (step_select),
        .timeout_ms       (timeout_ms),
        .dll_delay_code   (),
        .dll_locked       (dll_locked),
        .pattern_wr_en    (pattern_wr_en),
        .pattern_data     (pattern_data),
        .pattern_rd_valid (pattern_rd_valid),
        .pattern_rd_data  (pattern_rd_data),
        .pattern_pass     (pattern_pass),
        .ca_delay_result  (ca_delay_result),
        .wl_delay_result  (wl_delay_result),
        .rgt_delay_result (rgt_delay_result),
        .rdq_delay_result (rdq_delay_result),
        .wdq_delay_result (wdq_delay_result),
        .vref_code_result (vref_code_result),
        .dfe_tap_result   (dfe_tap_result),
        .train_in_progress(train_in_progress),
        .train_complete   (train_complete),
        .train_error      (train_error),
        .cur_step         (cur_step),
        .progress_pct     (progress_pct),
        .error_code       (error_code)
    );

    // Clock gate controller instance
    ddr5_clk_gate_ctrl u_clk_gate (
        .clk            (ctrl_clk),
        .rst_n          (rst_n),
        .cmd_active     (dfi_cmd_valid),
        .data_active    (wr_user_valid || rd_user_valid),
        .train_active   (train_in_progress),
        .sreq_active    (1'b0),  // TODO: connect from controller
        .cg_enable      (cg_enable),
        .idle_threshold (idle_threshold),
        .ctrl_clk_en    (ctrl_clk_en),
        .dfi_clk_en     (dfi_clk_en),
        .phy_clk_en     (phy_clk_en),
        .idle_detected  (idle_detected),
        .clk_gated      (clk_gated)
    );

    // DFI command passthrough (simplified - real PHY would have more logic)
    assign dfi_cmd_ready = 1'b1;
    assign addr_out      = dfi_address;
    assign bank_out      = dfi_bank;
    assign cs_n_out      = dfi_cs_n;
    assign act_n_out     = dfi_act_n;
    assign ras_n_out     = dfi_ras_n;
    assign cas_n_out     = dfi_cas_n;
    assign we_n_out      = dfi_we_n;
    assign cke_out       = 2'b11;
    assign odt_out       = 2'b00;
    assign reset_n_out   = rst_n;

    // Data path (simplified - real PHY would have DDR serialization)
    assign dq_out        = wr_dfi_data[31:0];
    assign dqs_out       = 4'hF;
    assign rd_dfi_data   = {96'h0, dq_in};
    assign rd_dfi_valid  = 1'b0;  // TODO: implement read capture logic

    // B-04: DFI 5.1 read-data-not-valid per sub-channel.
    // Behavioral model: no valid read capture yet, so flag both sub-channels
    // as not-valid whenever a read would be expected. A real PHY drives this
    // from its DQ parity/CRC checkers.
    assign dfi_rddata_dnv = rd_dfi_valid ? 2'b00 : 2'b11;

    // PHY initialization complete after DLL lock and training
    assign phy_init_complete = dll_locked && train_complete;

    // Pattern interface (simplified - connect to actual PHY pattern logic)
    assign pattern_rd_valid = 1'b0;
    assign pattern_rd_data  = 32'h0;
    assign pattern_pass     = 1'b0;

endmodule
