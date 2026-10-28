// =============================================================================
// Testbench: tb_ddr5_deadlock_monitor
// Description: B-03 verification of the hardware deadlock-prevention monitor.
//   - no stall -> no detection
//   - command stall beyond CMD_TIMEOUT -> deadlock_detected
//   - refresh stall beyond REF_TIMEOUT -> force_refresh pulse
//   - recovery: flag clears once traffic resumes and FSM is idle
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_deadlock_monitor();

    parameter int CMD_TIMEOUT = 50;
    parameter int REF_TIMEOUT = 30;
    parameter real CLK_PERIOD = 2.0;

    logic clk = 0;
    logic rst_n;
    logic cmd_in_valid, cmd_in_ready;
    logic sched_valid, sched_ready;
    logic ref_req, ref_ack;
    logic fsm_idle;
    logic deadlock_detected, force_refresh;
    logic [15:0] stall_count;

    ddr5_deadlock_monitor #(
        .CMD_TIMEOUT(CMD_TIMEOUT), .REF_TIMEOUT(REF_TIMEOUT), .CNT_W(16)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_in_valid(cmd_in_valid), .cmd_in_ready(cmd_in_ready),
        .sched_valid(sched_valid), .sched_ready(sched_ready),
        .ref_req(ref_req), .ref_ack(ref_ack), .fsm_idle(fsm_idle),
        .deadlock_detected(deadlock_detected),
        .force_refresh(force_refresh), .stall_count(stall_count)
    );

    initial forever #(CLK_PERIOD/2) clk = ~clk;

    int pass_cnt = 0, fail_cnt = 0;
    task automatic chk(string name, bit cond);
        if (cond) begin $display("[PASS] %s", name); pass_cnt++; end
        else      begin $display("[FAIL] %s", name); fail_cnt++; end
    endtask

    initial begin
        rst_n=0; cmd_in_valid=0; cmd_in_ready=1; sched_valid=0; sched_ready=1;
        ref_req=0; ref_ack=1; fsm_idle=1;
        repeat(3) @(posedge clk); rst_n=1; @(posedge clk);

        // T1: idle -> no detection
        chk("T1 no deadlock at idle", !deadlock_detected && !force_refresh);

        // T2: command stall beyond timeout -> detected
        cmd_in_valid=1; cmd_in_ready=0;
        repeat(CMD_TIMEOUT+5) @(posedge clk);
        chk("T2 cmd stall detected", deadlock_detected);
        cmd_in_valid=0; cmd_in_ready=1; @(posedge clk);

        // T3: recovery clears sticky flag once traffic resumes + FSM idle
        repeat(3) @(posedge clk);
        chk("T3 flag cleared after recovery", !deadlock_detected);

        // T4: refresh stall beyond timeout -> force_refresh pulse
        ref_req=1; ref_ack=0;
        repeat(REF_TIMEOUT+5) @(posedge clk);
        chk("T4 force_refresh asserted", force_refresh);
        chk("T4b refresh stall detected", deadlock_detected);
        ref_req=0; ref_ack=1; @(posedge clk);

        // T5: stall_count reflects worst observed stall
        chk("T5 stall_count non-zero", stall_count > 16'd0);

        $display("\n=== tb_ddr5_deadlock_monitor: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
        $finish;
    end

    initial begin #(CLK_PERIOD*1000); $display("[ERROR] timeout"); $finish; end
endmodule
