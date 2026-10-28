// =============================================================================
// Testbench: tb_ddr5_refresh_ctrl
// Description: Verification of DDR5 refresh controller
//              Tests: credit accumulation, FGR modes, REFab/REFsb, self-refresh
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_refresh_ctrl();

    parameter int NUM_BANKS = 32;
    parameter real CLK_PERIOD = 2.083;

    logic clk, rst_n;
    logic [15:0] tREFI, tRFC;
    logic [1:0] fgr_mode;
    logic auto_ref_en, manual_trigger;
    logic ref_req, ref_all;
    logic [4:0] ref_bank;
    logic ref_ack;
    logic sreq_enter, sreq_active, sreq_exit;
    logic [3:0] credit_count;
    logic overflow;

    ddr5_refresh_ctrl #(
        .NUM_BANKS(NUM_BANKS)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .tREFI(tREFI), .tRFC(tRFC),
        .fgr_mode(fgr_mode),
        .auto_ref_en(auto_ref_en),
        .manual_trigger(manual_trigger),
        .ref_req(ref_req), .ref_bank(ref_bank),
        .ref_all(ref_all), .ref_ack(ref_ack),
        .sreq_enter(sreq_enter),
        .sreq_active(sreq_active), .sreq_exit(sreq_exit),
        .credit_count(credit_count), .overflow(overflow)
    );

    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    int test_num = 0, pass_count = 0, fail_count = 0;
    // hoisted out of the initial block (AGENT.md rule #8 / Xsim HDL 9-1206)
    logic [3:0] credit_before;
    logic [4:0] bank1, bank2;

    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    initial begin
        $display("========================================");
        $display("Testbench: ddr5_refresh_ctrl");
        $display("========================================");

        rst_n = 0; auto_ref_en = 0; manual_trigger = 0;
        ref_ack = 0; sreq_enter = 0;
        tREFI = 16'd100;  // Short interval for testing
        tRFC = 16'd50;
        fgr_mode = 2'b00;  // 1x mode

        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // ---- Test 1: Credit accumulation in 1x mode ----
        test_num = 1;
        $display("\n--- Test %0d: Credit accumulation (1x mode) ---", test_num);
        auto_ref_en = 1;
        fgr_mode = 2'b00;  // 1x: +1 credit per tREFI
        wait_cycles(110);  // Wait for 1 tREFI cycle
        if (credit_count >= 4'd1) begin
            $display("[PASS] Test %0d: Credit accumulated (count=%0d)", test_num, credit_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No credit accumulated", test_num);
            fail_count++;
        end

        // ---- Test 2: Credit accumulation in 2x mode ----
        test_num = 2;
        $display("\n--- Test %0d: Credit accumulation (2x mode) ---", test_num);
        fgr_mode = 2'b01;  // 2x: +2 credits per tREFI
        wait_cycles(110);
        if (credit_count >= 4'd3) begin
            $display("[PASS] Test %0d: 2x credits accumulated (count=%0d)", test_num, credit_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: 2x mode not working", test_num);
            fail_count++;
        end

        // ---- Test 3: Credit accumulation in 4x mode ----
        test_num = 3;
        $display("\n--- Test %0d: Credit accumulation (4x mode) ---", test_num);
        fgr_mode = 2'b10;  // 4x: +4 credits per tREFI
        wait_cycles(110);
        if (credit_count >= 4'd7) begin
            $display("[PASS] Test %0d: 4x credits accumulated (count=%0d)", test_num, credit_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: 4x mode not working", test_num);
            fail_count++;
        end

        // ---- Test 4: Overflow detection ----
        test_num = 4;
        $display("\n--- Test %0d: Overflow detection (max 8 credits) ---", test_num);
        wait_cycles(330);  // Should hit max 8
        if (overflow === 1'b1 || credit_count === 4'd8) begin
            $display("[PASS] Test %0d: Overflow detected at 8 credits", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Overflow not detected", test_num);
            fail_count++;
        end

        // ---- Test 5: Refresh request generation ----
        test_num = 5;
        $display("\n--- Test %0d: Refresh request generation ---", test_num);
        wait_cycles(10);
        if (ref_req === 1'b1 && credit_count > 0) begin
            $display("[PASS] Test %0d: Refresh request asserted", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No refresh request", test_num);
            fail_count++;
        end

        // ---- Test 6: Credit consumption on ack ----
        test_num = 6;
        $display("\n--- Test %0d: Credit consumption on ack ---", test_num);
        credit_before = credit_count;
        ref_ack = 1;
        wait_cycles(2);
        ref_ack = 0;
        if (credit_count < credit_before) begin
            $display("[PASS] Test %0d: Credit consumed (%0d → %0d)", test_num, credit_before, credit_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Credit not consumed", test_num);
            fail_count++;
        end

        // ---- Test 7: Manual trigger ----
        test_num = 7;
        $display("\n--- Test %0d: Manual trigger ---", test_num);
        credit_before = credit_count;
        manual_trigger = 1;
        wait_cycles(2);
        manual_trigger = 0;
        if (credit_count > credit_before) begin
            $display("[PASS] Test %0d: Manual trigger added credit", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Manual trigger failed", test_num);
            fail_count++;
        end

        // ---- Test 8: REFsb bank rotation ----
        test_num = 8;
        $display("\n--- Test %0d: REFsb bank rotation ---", test_num);
        wait_cycles(110);
        bank1 = ref_bank;
        wait_cycles(110);
        bank2 = ref_bank;
        if (bank2 !== bank1) begin
            $display("[PASS] Test %0d: Bank rotation (%0d → %0d)", test_num, bank1, bank2);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No bank rotation", test_num);
            fail_count++;
        end

        // ---- Test 9: Self-refresh entry ----
        test_num = 9;
        $display("\n--- Test %0d: Self-refresh entry ---", test_num);
        auto_ref_en = 0;
        sreq_enter = 1;
        wait_cycles(10);
        if (sreq_active === 1'b1) begin
            $display("[PASS] Test %0d: Self-refresh active", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Self-refresh not active", test_num);
            fail_count++;
        end

        // ---- Test 10: Self-refresh exit ----
        test_num = 10;
        $display("\n--- Test %0d: Self-refresh exit ---", test_num);
        sreq_enter = 0;
        wait_cycles(10);
        if (sreq_exit === 1'b1 || sreq_active === 1'b0) begin
            $display("[PASS] Test %0d: Self-refresh exited", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Self-refresh not exited", test_num);
            fail_count++;
        end

        // Summary
        $display("\n========================================");
        $display("Test Summary: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        $finish;
    end

    initial begin #(CLK_PERIOD * 50000); $display("[ERROR] Timeout!"); $finish; end
    initial begin $dumpfile("tb_ddr5_refresh_ctrl.vcd"); $dumpvars(0, tb_ddr5_refresh_ctrl); end

endmodule
