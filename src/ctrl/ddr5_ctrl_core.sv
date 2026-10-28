// =============================================================================
// Module: ddr5_ctrl_core
// Description: DDR5 controller core top module
//              Integrates scheduler, FSM, bank manager, refresh, timing, ECC
//              Dual sub-channel support with independent FSMs
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_ctrl_core #(
    parameter int NUM_BANKS   = `DDR5_NUM_BANKS,
    parameter int QUEUE_DEPTH = 16
)(
    input  logic        clk,
    input  logic        rst_n,

    // Command input from UI layer (via CDC FIFO)
    input  logic        cmd_in_valid,
    output logic        cmd_in_ready,
    input  logic [7:0]  cmd_in_id,
    input  logic [33:0] cmd_in_addr,
    input  logic [7:0]  cmd_in_len,
    input  logic        cmd_in_is_write,
    input  logic [1:0]  cmd_in_port_id,
    input  logic [3:0]  cmd_in_qos,

    // Write data interface
    input  logic [255:0] wr_data,
    input  logic [31:0]  wr_strb,
    input  logic         wr_data_valid,

    // Read data interface
    output logic [255:0] rd_data,
    output logic         rd_data_valid,
    output logic [1:0]   rd_port_id,
    output logic [7:0]   rd_id,

    // DFI command interface (to DFI bridge)
    output logic        dfi_cmd_valid,
    output logic [17:0] dfi_address,
    output logic [5:0]  dfi_bank,
    output logic [1:0]  dfi_cs_n,
    output logic        dfi_act_n,
    output logic        dfi_ras_n,
    output logic        dfi_cas_n,
    output logic        dfi_we_n,
    output logic [127:0] dfi_wrdata,
    output logic [15:0]  dfi_wrdata_mask,
    output logic         dfi_wrdata_en,
    input  logic [127:0] dfi_rddata,
    input  logic         dfi_rddata_valid,

    // Configuration interface
    input  logic [15:0] cfg_tRCD,
    input  logic [15:0] cfg_tRP,
    input  logic [15:0] cfg_tRAS,
    input  logic [15:0] cfg_tRC,
    input  logic [15:0] cfg_tRFC,
    input  logic [15:0] cfg_tRFCsb,
    input  logic [15:0] cfg_tREFI,
    input  logic [15:0] cfg_tWR,
    input  logic [15:0] cfg_tRTP,
    input  logic [15:0] cfg_CL,
    input  logic [15:0] cfg_CWL,
    input  logic [15:0] cfg_tCCD_L,
    input  logic [15:0] cfg_tCCD_S,
    input  logic [15:0] cfg_tRRD_L,
    input  logic [15:0] cfg_tRRD_S,
    input  logic [15:0] cfg_tFAW,
    input  logic [15:0] cfg_tXS,
    input  logic [15:0] cfg_tXP,
    input  logic [15:0] cfg_tZQCAL,
    input  logic [15:0] cfg_tZQCS,
    input  logic [1:0]  cfg_fgr_mode,
    input  logic        cfg_auto_ref_en,
    input  logic        cfg_manual_ref,
    input  logic        cfg_ecc_en,
    input  logic        cfg_sreq_enter,

    // Status outputs
    output logic        ctrl_ready,
    output logic [3:0]  ctrl_state,
    output logic [3:0]  refresh_credit,
    output logic        refresh_overflow,
    output logic        ecc_sbe_detect,
    output logic        ecc_dbe_detect,

    // B-03: deadlock prevention status
    output logic        deadlock_detected,
    output logic [15:0] deadlock_stall_count
);

    // Internal signals
    logic        sched_cmd_valid;
    logic        sched_cmd_ready;
    logic [3:0]  sched_cmd_type;
    logic [7:0]  sched_cmd_id;
    logic [4:0]  sched_cmd_bank;
    logic [2:0]  sched_cmd_bg;
    logic [2:0]  sched_cmd_ba;
    logic [17:0] sched_cmd_row;
    logic [9:0]  sched_cmd_col;
    logic        sched_cmd_sub_ch;
    logic [1:0]  sched_cmd_port_id;

    logic        timing_check_req;
    logic [3:0]  timing_check_cmd;
    logic [4:0]  timing_check_bank;
    logic [2:0]  timing_check_bg;
    logic        timing_check_ok;

    logic        bank_mgr_valid;
    logic [3:0]  bank_mgr_cmd;
    logic [4:0]  bank_mgr_bank;
    logic [17:0] bank_mgr_row;

    logic [2:0]  bank_state [NUM_BANKS];
    logic [17:0] open_row   [NUM_BANKS];
    logic        row_open   [NUM_BANKS];

    logic        ref_req;
    logic [4:0]  ref_bank;
    logic        ref_all;
    logic        ref_ack;  // OR of both FSM acknowledges
    logic        ref_ack_a, ref_ack_b;
    logic        sreq_active;
    logic        sreq_exit;

    assign ref_ack = ref_ack_a | ref_ack_b;

    // B-03: forced-refresh recovery pulse from the deadlock monitor
    logic dl_force_ref;

    // Command scheduler instance
    ddr5_cmd_scheduler #(
        .QUEUE_DEPTH (QUEUE_DEPTH),
        .NUM_BANKS   (NUM_BANKS)
    ) u_scheduler (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_in_valid   (cmd_in_valid),
        .cmd_in_ready   (cmd_in_ready),
        .cmd_in_id      (cmd_in_id),
        .cmd_in_addr    (cmd_in_addr),
        .cmd_in_len     (cmd_in_len),
        .cmd_in_is_write(cmd_in_is_write),
        .cmd_in_port_id (cmd_in_port_id),
        .cmd_in_qos     (cmd_in_qos),
        .cmd_out_valid  (sched_cmd_valid),
        .cmd_out_ready  (sched_cmd_ready),
        .cmd_out_type   (sched_cmd_type),
        .cmd_out_id     (sched_cmd_id),
        .cmd_out_bank   (sched_cmd_bank),
        .cmd_out_bg     (sched_cmd_bg),
        .cmd_out_ba     (sched_cmd_ba),
        .cmd_out_row    (sched_cmd_row),
        .cmd_out_col    (sched_cmd_col),
        .cmd_out_sub_ch (sched_cmd_sub_ch),
        .cmd_out_port_id(sched_cmd_port_id),
        .bank_state     (bank_state),
        .open_row       (open_row),
        .row_open       (row_open),
        .ref_req        (ref_req),
        .ref_block      (),
        .queue_count    ()
    );

    // Timing engine instance
    ddr5_timing_engine #(
        .NUM_BANKS  (NUM_BANKS),
        .TIM_W      (16),
        .NUM_PARAMS (20)
    ) u_timing (
        .clk             (clk),
        .rst_n           (rst_n),
        .tRCD            (cfg_tRCD),
        .tRP             (cfg_tRP),
        .tRAS            (cfg_tRAS),
        .tRC             (cfg_tRC),
        .tRFC            (cfg_tRFC),
        .tRFCsb          (cfg_tRFCsb),
        .tREFI           (cfg_tREFI),
        .tWR             (cfg_tWR),
        .tRTP            (cfg_tRTP),
        .tCCD_L          (cfg_tCCD_L),
        .tCCD_S          (cfg_tCCD_S),
        .tRRD_L          (cfg_tRRD_L),
        .tRRD_S          (cfg_tRRD_S),
        .tFAW            (cfg_tFAW),
        .tXS             (cfg_tXS),
        .tXP             (cfg_tXP),
        .CL              (cfg_CL),
        .CWL             (cfg_CWL),
        .tZQCAL          (cfg_tZQCAL),
        .tZQCS           (cfg_tZQCS),
        .cmd_valid       (timing_check_req),
        .cmd_type        (timing_check_cmd),
        .cmd_bank        (timing_check_bank),
        .cmd_bg          (timing_check_bg),
        .cmd_timing_ok   (timing_check_ok),
        .tFAW_ok         (),
        .tRRD_ok         (),
        .tCCD_ok         ()
    );

    // Bank manager instance
    ddr5_bank_manager #(
        .NUM_BANKS (NUM_BANKS),
        .ROW_W     (18)
    ) u_bank_mgr (
        .clk           (clk),
        .rst_n         (rst_n),
        .cmd_valid     (sched_cmd_valid && sched_cmd_ready),
        .cmd_type      (sched_cmd_type),
        .cmd_bank      (sched_cmd_bank),
        .cmd_row       (sched_cmd_row),
        .page_hit      (),
        .page_miss     (),
        .page_conflict (),
        .bank_ready    (),
        .bank_state    (bank_state),
        .open_row      (open_row),
        .row_open      (row_open)
    );

    // Refresh controller instance
    ddr5_refresh_ctrl #(
        .NUM_BANKS (NUM_BANKS)
    ) u_refresh (
        .clk           (clk),
        .rst_n         (rst_n),
        .tREFI         (cfg_tREFI),
        .tRFC          (cfg_tRFC),
        .fgr_mode      (cfg_fgr_mode),
        .auto_ref_en   (cfg_auto_ref_en),
        .manual_trigger(cfg_manual_ref | dl_force_ref),   // B-03 recovery
        .ref_req       (ref_req),
        .ref_bank      (ref_bank),
        .ref_all       (ref_all),
        .ref_ack       (ref_ack),
        .sreq_enter    (cfg_sreq_enter),
        .sreq_active   (sreq_active),
        .sreq_exit     (sreq_exit),
        .credit_count  (refresh_credit),
        .overflow      (refresh_overflow)
    );

    // Protocol FSM instance (sub-channel A)
    ddr5_protocol_fsm u_fsm_a (
        .clk               (clk),
        .rst_n             (rst_n),
        .cmd_valid         (sched_cmd_valid),
        .cmd_type          (sched_cmd_type),
        .cmd_bank          (sched_cmd_bank),
        .cmd_bg            (sched_cmd_bg),
        .cmd_ba            (sched_cmd_ba),
        .cmd_row           (sched_cmd_row),
        .cmd_col           (sched_cmd_col),
        .cmd_sub_ch        (sched_cmd_sub_ch),
        .timing_check_req  (timing_check_req),
        .timing_check_cmd  (timing_check_cmd),
        .timing_check_bank (timing_check_bank),
        .timing_check_bg   (timing_check_bg),
        .timing_check_ok   (timing_check_ok),
        .bank_mgr_valid    (bank_mgr_valid),
        .bank_mgr_cmd      (bank_mgr_cmd),
        .bank_mgr_bank     (bank_mgr_bank),
        .bank_mgr_row      (bank_mgr_row),
        .ref_req           (ref_req),
        .ref_ack           (ref_ack_a),
        .dfi_cmd_valid     (dfi_cmd_valid),
        .dfi_address       (dfi_address),
        .dfi_bank          (dfi_bank),
        .dfi_cs_n          (dfi_cs_n),
        .dfi_act_n         (dfi_act_n),
        .dfi_ras_n         (dfi_ras_n),
        .dfi_cas_n         (dfi_cas_n),
        .dfi_we_n          (dfi_we_n),
        .fsm_ready         (),
        .fsm_state_out     (ctrl_state)
    );

    // Protocol FSM instance (sub-channel B)
    logic        timing_check_req_b;
    logic [3:0]  timing_check_cmd_b;
    logic [4:0]  timing_check_bank_b;
    logic [2:0]  timing_check_bg_b;
    logic        timing_check_ok_b;

    logic        bank_mgr_valid_b;
    logic [3:0]  bank_mgr_cmd_b;
    logic [4:0]  bank_mgr_bank_b;
    logic [17:0] bank_mgr_row_b;

    logic        dfi_cmd_valid_b;
    logic [17:0] dfi_address_b;
    logic [5:0]  dfi_bank_b;
    logic [1:0]  dfi_cs_n_b;
    logic        dfi_act_n_b;
    logic        dfi_ras_n_b;
    logic        dfi_cas_n_b;
    logic        dfi_we_n_b;
    logic [3:0]  ctrl_state_b;

    ddr5_protocol_fsm u_fsm_b (
        .clk               (clk),
        .rst_n             (rst_n),
        .cmd_valid         (sched_cmd_valid),
        .cmd_type          (sched_cmd_type),
        .cmd_bank          (sched_cmd_bank),
        .cmd_bg            (sched_cmd_bg),
        .cmd_ba            (sched_cmd_ba),
        .cmd_row           (sched_cmd_row),
        .cmd_col           (sched_cmd_col),
        .cmd_sub_ch        (sched_cmd_sub_ch),
        .timing_check_req  (timing_check_req_b),
        .timing_check_cmd  (timing_check_cmd_b),
        .timing_check_bank (timing_check_bank_b),
        .timing_check_bg   (timing_check_bg_b),
        .timing_check_ok   (timing_check_ok_b),
        .bank_mgr_valid    (bank_mgr_valid_b),
        .bank_mgr_cmd      (bank_mgr_cmd_b),
        .bank_mgr_bank     (bank_mgr_bank_b),
        .bank_mgr_row      (bank_mgr_row_b),
        .ref_req           (ref_req),
        .ref_ack           (ref_ack_b),
        .dfi_cmd_valid     (dfi_cmd_valid_b),
        .dfi_address       (dfi_address_b),
        .dfi_bank          (dfi_bank_b),
        .dfi_cs_n          (dfi_cs_n_b),
        .dfi_act_n         (dfi_act_n_b),
        .dfi_ras_n         (dfi_ras_n_b),
        .dfi_cas_n         (dfi_cas_n_b),
        .dfi_we_n          (dfi_we_n_b),
        .fsm_ready         (),
        .fsm_state_out     (ctrl_state_b)
    );

    // ECC engine instance
    ddr5_ecc_engine #(
        .DATA_W (32),
        .CODE_W (8)
    ) u_ecc (
        .clk            (clk),
        .rst_n          (rst_n),
        .ecc_en         (cfg_ecc_en),
        .err_inject_en  (1'b0),
        .err_inject_pos (8'h00),
        .enc_valid      (wr_data_valid),
        .enc_data       (wr_data[31:0]),
        .enc_ecc        (),
        .dec_valid      (dfi_rddata_valid),
        .dec_data       (dfi_rddata[31:0]),
        .dec_ecc        (dfi_rddata[39:32]),
        .dec_data_corr  (),
        .dec_sbe        (),
        .dec_dbe        (),
        .sbe_detect     (ecc_sbe_detect),
        .dbe_detect     (ecc_dbe_detect),
        .err_addr       (),
        .err_data       (),
        .err_syndrome   ()
    );

    // Write data buffer: hold wr_data until FSM issues WR command
    logic [127:0] wr_data_buf;
    logic [15:0]  wr_strb_buf;
    logic         wr_data_pending;
    logic         wr_data_buf_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_data_buf      <= '0;
            wr_strb_buf      <= '0;
            wr_data_buf_valid <= 1'b0;
        end else begin
            // Latch write data on arrival
            if (wr_data_valid && !wr_data_buf_valid) begin
                wr_data_buf      <= wr_data[127:0];
                wr_strb_buf      <= wr_strb[15:0];
                wr_data_buf_valid <= 1'b1;
            end
            // Clear when FSM issues WR command on DFI
            if (dfi_cmd_valid && !dfi_cas_n && !dfi_we_n) begin
                wr_data_buf_valid <= 1'b0;
            end
        end
    end

    // Write data to DFI (buffered, not direct pass-through)
    assign dfi_wrdata      = wr_data_buf;
    assign dfi_wrdata_mask = wr_strb_buf;
    assign dfi_wrdata_en   = wr_data_buf_valid;

    // Read data path (simplified - direct pass-through)
    assign rd_data       = {128'h0, dfi_rddata};
    assign rd_data_valid = dfi_rddata_valid;
    assign rd_port_id    = 2'h0;
    assign rd_id         = 8'h00;

    // ref_ack already assigned above (ref_ack_a | ref_ack_b)
    // Command ready: only when FSM is in IDLE state (one command at a time)
    assign sched_cmd_ready = (ctrl_state == 4'h0) && !ref_req;

    // -------------------------------------------------------------------------
    // B-03: Deadlock prevention monitor
    // Watches the UI->core and scheduler->FSM handshakes plus the refresh
    // handshake; raises a sticky deadlock flag and a forced-refresh recovery
    // pulse when a stall exceeds its timeout.
    // -------------------------------------------------------------------------
    ddr5_deadlock_monitor #(
        .CMD_TIMEOUT (1000),
        .REF_TIMEOUT (500),
        .CNT_W       (16)
    ) u_deadlock (
        .clk               (clk),
        .rst_n             (rst_n),
        .cmd_in_valid      (cmd_in_valid),
        .cmd_in_ready      (cmd_in_ready),
        .sched_valid       (sched_cmd_valid),
        .sched_ready       (sched_cmd_ready),
        .ref_req           (ref_req),
        .ref_ack           (ref_ack),
        .fsm_idle          (ctrl_state == 4'h0),
        .deadlock_detected (deadlock_detected),
        .force_refresh     (dl_force_ref),   // B-03 -> refresh_ctrl.manual_trigger
        .stall_count       (deadlock_stall_count)
    );

    // Status outputs
    assign ctrl_ready = (ctrl_state == 4'h0);  // IDLE state

endmodule
