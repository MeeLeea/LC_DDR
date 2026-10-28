// =============================================================================
// Module: ddr5_protocol_fsm
// Description: DDR5 protocol state machine (per sub-channel)
//              Handles ACT/RD/WR/PRE/REF/SREF/ZQ command sequencing
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_protocol_fsm #(
    // 1 = dual sub-channel broadcast (256-bit full-width path, cs_n=00)
    // 0 = single sub-channel selected by cmd_sub_ch (128-bit path)
    parameter bit DUAL_CH_BROADCAST = 1'b1
)(
    input  logic        clk,
    input  logic        rst_n,

    // Command request from scheduler
    input  logic        cmd_valid,
    input  logic [3:0]  cmd_type,
    input  logic [4:0]  cmd_bank,
    input  logic [2:0]  cmd_bg,
    input  logic [2:0]  cmd_ba,
    input  logic [17:0] cmd_row,
    input  logic [9:0]  cmd_col,
    input  logic        cmd_sub_ch,  // 0=A, 1=B

    // Timing check interface
    output logic        timing_check_req,
    output logic [3:0]  timing_check_cmd,
    output logic [4:0]  timing_check_bank,
    output logic [2:0]  timing_check_bg,
    input  logic        timing_check_ok,

    // Bank manager interface
    output logic        bank_mgr_valid,
    output logic [3:0]  bank_mgr_cmd,
    output logic [4:0]  bank_mgr_bank,
    output logic [17:0] bank_mgr_row,

    // Refresh interface
    input  logic        ref_req,
    output logic        ref_ack,

    // DFI command output
    output logic        dfi_cmd_valid,
    output logic [17:0] dfi_address,
    output logic [5:0]  dfi_bank,
    output logic [1:0]  dfi_cs_n,
    output logic        dfi_act_n,
    output logic        dfi_ras_n,
    output logic        dfi_cas_n,
    output logic        dfi_we_n,

    // Status
    output logic        fsm_ready,
    output logic [3:0]  fsm_state_out
);

    // FSM states
    typedef enum logic [3:0] {
        ST_IDLE      = 4'h0,
        ST_ACT       = 4'h1,
        ST_RD        = 4'h2,
        ST_WR        = 4'h3,
        ST_PRE       = 4'h4,
        ST_REF       = 4'h5,
        ST_SREF      = 4'h6,
        ST_ZQ        = 4'h7,
        ST_WAIT_TIM  = 4'h8,
        ST_WAIT_BANK = 4'h9
    } fsm_state_t;

    fsm_state_t state, state_next;

    // Registered command
    logic [3:0]  cmd_type_r;
    logic [4:0]  cmd_bank_r;
    logic [2:0]  cmd_bg_r;
    logic [2:0]  cmd_ba_r;
    logic [17:0] cmd_row_r;
    logic [9:0]  cmd_col_r;
    logic        cmd_sub_ch_r;

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= state_next;
        end
    end

    // Command register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_type_r <= '0;
            cmd_bank_r <= '0;
            cmd_bg_r   <= '0;
            cmd_ba_r   <= '0;
            cmd_row_r    <= '0;
            cmd_col_r    <= '0;
            cmd_sub_ch_r <= 1'b0;
        end else if (cmd_valid && state == ST_IDLE) begin
            cmd_type_r <= cmd_type;
            cmd_bank_r <= cmd_bank;
            cmd_bg_r   <= cmd_bg;
            cmd_ba_r   <= cmd_ba;
            cmd_row_r  <= cmd_row;
            cmd_col_r  <= cmd_col;
            cmd_sub_ch_r <= cmd_sub_ch;
        end
    end

    // Next state and output logic
    always_comb begin
        state_next = state;

        // Default outputs
        timing_check_req   = 1'b0;
        timing_check_cmd   = cmd_type_r;
        timing_check_bank  = cmd_bank_r;
        timing_check_bg    = cmd_bg_r;
        bank_mgr_valid     = 1'b0;
        bank_mgr_cmd       = cmd_type_r;
        bank_mgr_bank      = cmd_bank_r;
        bank_mgr_row       = cmd_row_r;
        ref_ack            = 1'b0;
        dfi_cmd_valid      = 1'b0;
        dfi_address        = '0;
        dfi_bank           = {cmd_bg_r, cmd_ba_r};
        // Sub-channel chip-select generation:
        //   DUAL_CH_BROADCAST=1 -> both sub-channels active (256-bit full-width)
        //   DUAL_CH_BROADCAST=0 -> select by cmd_sub_ch_r (0=A, 1=B)
        dfi_cs_n           = DUAL_CH_BROADCAST ? 2'b00
                                                : (cmd_sub_ch_r ? 2'b10 : 2'b01);
        dfi_act_n          = 1'b1;
        dfi_ras_n          = 1'b1;
        dfi_cas_n          = 1'b1;
        dfi_we_n           = 1'b1;

        case (state)
            ST_IDLE: begin
                // Priority: Refresh > User command
                if (ref_req) begin
                    state_next = ST_REF;
                    ref_ack    = 1'b1;
                end else if (cmd_valid) begin
                    // Check timing and bank status
                    timing_check_req = 1'b1;
                    bank_mgr_valid   = 1'b1;
                    state_next       = ST_WAIT_TIM;
                end
            end

            ST_WAIT_TIM: begin
                timing_check_req = 1'b1;
                bank_mgr_valid   = 1'b1;
                if (timing_check_ok) begin
                    // Issue command based on type
                    case (cmd_type_r)
                        4'h1: state_next = ST_ACT;  // ACT
                        4'h2: state_next = ST_RD;   // RD
                        4'h3: state_next = ST_WR;   // WR
                        4'h4: state_next = ST_PRE;  // PRE
                        default: state_next = ST_IDLE;
                    endcase
                end
            end

            ST_ACT: begin
                dfi_cmd_valid = 1'b1;
                dfi_address   = cmd_row_r;
                dfi_act_n     = 1'b0;
                dfi_ras_n     = 1'b0;
                state_next    = ST_IDLE;
            end

            ST_RD: begin
                dfi_cmd_valid = 1'b1;
                dfi_address   = {8'h00, cmd_col_r};
                dfi_cas_n     = 1'b0;
                state_next    = ST_IDLE;
            end

            ST_WR: begin
                dfi_cmd_valid = 1'b1;
                dfi_address   = {8'h00, cmd_col_r};
                dfi_cas_n     = 1'b0;
                dfi_we_n      = 1'b0;
                state_next    = ST_IDLE;
            end

            ST_PRE: begin
                dfi_cmd_valid = 1'b1;
                dfi_ras_n     = 1'b0;
                dfi_we_n      = 1'b0;
                state_next    = ST_IDLE;
            end

            ST_REF: begin
                dfi_cmd_valid = 1'b1;
                dfi_ras_n     = 1'b0;
                dfi_cas_n     = 1'b0;
                state_next    = ST_IDLE;
            end

            ST_SREF: begin
                dfi_cmd_valid = 1'b1;
                dfi_ras_n     = 1'b0;
                dfi_cas_n     = 1'b0;
                dfi_we_n      = 1'b0;
                state_next    = ST_IDLE;
            end

            ST_ZQ: begin
                dfi_cmd_valid = 1'b1;
                dfi_we_n      = 1'b0;
                state_next    = ST_IDLE;
            end

            default: state_next = ST_IDLE;
        endcase
    end

    // Status outputs
    assign fsm_ready    = (state == ST_IDLE);
    assign fsm_state_out = state;

endmodule
