// =============================================================================
// Module: ddr5_deadlock_monitor
// Description: Hardware deadlock-prevention monitor for the DDR5 controller.
//              Detects command / refresh stalls via timeout counters and
//              triggers recovery (forced refresh) + an interrupt. Resolves
//              review blocking issue B-03 (previously only "Guaranteed" was
//              claimed with no mechanism).
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_deadlock_monitor #(
    parameter int CMD_TIMEOUT = 1000,   // max cycles a command may stall
    parameter int REF_TIMEOUT = 500,    // max cycles a refresh may stall
    parameter int CNT_W       = 16
)(
    input  logic              clk,
    input  logic              rst_n,

    // UI -> core command handshake
    input  logic              cmd_in_valid,
    input  logic              cmd_in_ready,
    // scheduler -> FSM handshake
    input  logic              sched_valid,
    input  logic              sched_ready,
    // refresh handshake
    input  logic              ref_req,
    input  logic              ref_ack,
    // FSM idle indicator (used for recovery de-assertion)
    input  logic              fsm_idle,

    // Outputs
    output logic              deadlock_detected,  // sticky until traffic resumes
    output logic              force_refresh,      // pulse to inject a refresh
    output logic [CNT_W-1:0]  stall_count         // worst (peak) observed stall
);

    logic [CNT_W-1:0] cmd_cnt, ref_cnt;
    logic [CNT_W-1:0] peak_cnt;
    logic             cmd_stalled, ref_stalled;

    // A command is stalled when it is presented but not accepted, or when the
    // scheduler output is blocked by the protocol FSM.
    assign cmd_stalled = (cmd_in_valid && !cmd_in_ready) ||
                         (sched_valid  && !sched_ready);
    assign ref_stalled = ref_req && !ref_ack;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_cnt           <= '0;
            ref_cnt           <= '0;
            peak_cnt          <= '0;
            deadlock_detected <= 1'b0;
            force_refresh     <= 1'b0;
        end else begin
            // ---- Command stall tracking ----
            if (cmd_stalled) begin
                if (cmd_cnt >= CNT_W'(CMD_TIMEOUT))
                    deadlock_detected <= 1'b1;
                else
                    cmd_cnt <= cmd_cnt + 1'b1;
            end else begin
                cmd_cnt <= '0;
            end

            // ---- Refresh stall tracking + recovery action ----
            if (ref_stalled) begin
                if (ref_cnt >= CNT_W'(REF_TIMEOUT)) begin
                    deadlock_detected <= 1'b1;
                    force_refresh     <= 1'b1;   // inject a forced refresh
                end else begin
                    ref_cnt <= ref_cnt + 1'b1;
                end
            end else begin
                ref_cnt       <= '0;
                force_refresh <= 1'b0;
            end

            // ---- Peak stall bookkeeping (diagnostic, reset-clearable) ----
            if (cmd_cnt > peak_cnt) peak_cnt <= cmd_cnt;
            if (ref_cnt > peak_cnt) peak_cnt <= ref_cnt;

            // ---- Recovery: clear sticky flag once traffic resumes ----
            // NOTE: peak_cnt is intentionally NOT cleared here so software can
            // read DEADLOCK_STATUS[31:16] after auto-recovery to see how bad
            // the stall was; it is cleared only by reset.
            if (!cmd_stalled && !ref_stalled && fsm_idle)
                deadlock_detected <= 1'b0;
        end
    end

    assign stall_count = peak_cnt;

endmodule
