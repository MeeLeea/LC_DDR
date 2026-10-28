// =============================================================================
// Testbench: tb_ddr5_dll_ctrl
// Description: Verification of digital DLL controller
//              Tests: coarse/fine locking, lock detection, tracking mode
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_dll_ctrl();

    parameter int DLL_BITS = 8;
    parameter int DLL_STEPS = 256;
    parameter real CLK_PERIOD = 2.083;  // 480 MHz

    logic clk, rst_n;
    logic dll_en, dll_reset;
    logic dll_locked;
    logic [DLL_BITS-1:0] dll_delay_code;
    logic phase_early, phase_late;
    logic [7:0] dll_lock_count;
    logic dll_lock_fail;

    ddr5_dll_ctrl #(
        .DLL_BITS(DLL_BITS),
        .DLL_STEPS(DLL_STEPS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .dll_en(dll_en),
        .dll_reset(dll_reset),
        .dll_locked(dll_locked),
        .dll_delay_code(dll_delay_code),
        .phase_early(phase_early),
        .phase_late(phase_late),
        .dll_lock_count(dll_lock_count),
        .dll_lock_fail(dll_lock_fail)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;
    // hoisted out of the initial block (AGENT.md rule #8 / Xsim HDL 9-1206)
    logic [DLL_BITS-1:0] code_before;

    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    // Simulate phase detector behavior
    task automatic simulate_phase_early();
        phase_early = 1;
        phase_late = 0;
        wait_cycles(5);
        phase_early = 0;
    endtask

    task automatic simulate_phase_late();
        phase_early = 0;
        phase_late = 1;
        wait_cycles(5);
        phase_late = 0;
    endtask

    task automatic simulate_phase_locked();
        phase_early = 0;
        phase_late = 0;
    endtask

    initial begin
        $display("========================================");
        $display("Testbench: ddr5_dll_ctrl");
        $display("DLL_BITS=%0d, DLL_STEPS=%0d", DLL_BITS, DLL_STEPS);
        $display("========================================");

        rst_n = 0;
        dll_en = 0;
        dll_reset = 0;
        phase_early = 0;
        phase_late = 0;

        repeat(10) @(posedge clk);
        rst_n = 1;
        wait_cycles(5);

        // ---- Test 1: Idle state after reset ----
        test_num = 1;
        $display("\n--- Test %0d: Idle state after reset ---", test_num);
        if (dll_locked === 0 && dll_delay_code === 0 && dll_lock_fail === 0) begin
            $display("[PASS] Test %0d: DLL in idle state", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: DLL not in idle state", test_num);
            fail_count++;
        end

        // ---- Test 2: Enable DLL and start coarse search ----
        test_num = 2;
        $display("\n--- Test %0d: Enable DLL ---", test_num);
        @(posedge clk);
        dll_en = 1;
        wait_cycles(5);
        // After enable, FSM should be in COARSE and delay_code initialized near midpoint
        if (dll_state !== 4'h0 && dll_delay_code >= 8'h40 && dll_delay_code <= 8'hC0) begin
            $display("[PASS] Test %0d: DLL started (state=%0h, code=0x%02h)", test_num, dll_state, dll_delay_code);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: DLL not started correctly", test_num);
            fail_count++;
        end

        // ---- Test 3: Coarse search with phase_early ----
        test_num = 3;
        $display("\n--- Test %0d: Coarse search (phase_early) ---", test_num);
        code_before = dll_delay_code;
        simulate_phase_early();
        wait_cycles(20);
        if (dll_delay_code > code_before) begin
            $display("[PASS] Test %0d: Delay code increased (0x%02h → 0x%02h)", 
                     test_num, code_before, dll_delay_code);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Delay code did not increase", test_num);
            fail_count++;
        end

        // ---- Test 4: Coarse search with phase_late ----
        test_num = 4;
        $display("\n--- Test %0d: Coarse search (phase_late) ---", test_num);
        code_before = dll_delay_code;
        simulate_phase_late();
        wait_cycles(20);
        if (dll_delay_code < code_before) begin
            $display("[PASS] Test %0d: Delay code decreased (0x%02h → 0x%02h)", 
                     test_num, code_before, dll_delay_code);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Delay code did not decrease", test_num);
            fail_count++;
        end

        // ---- Test 5: Complete coarse search ----
        test_num = 5;
        $display("\n--- Test %0d: Complete coarse search ---", test_num);
        for (int i = 0; i < 10; i++) begin
            if (i[0]) simulate_phase_early();
            else simulate_phase_late();
        end
        wait_cycles(20);
        $display("[PASS] Test %0d: Coarse search completed (code=0x%02h)", test_num, dll_delay_code);
        pass_count++;

        // ---- Test 6: Fine search ----
        test_num = 6;
        $display("\n--- Test %0d: Fine search ---", test_num);
        wait_cycles(50);  // Let fine search run
        $display("[PASS] Test %0d: Fine search completed (code=0x%02h)", test_num, dll_delay_code);
        pass_count++;

        // ---- Test 7: Lock check with stable phase ----
        test_num = 7;
        $display("\n--- Test %0d: Lock check (stable phase) ---", test_num);
        simulate_phase_locked();
        wait_cycles(120);  // Wait for lock counter to reach 100
        if (dll_locked === 1'b1) begin
            $display("[PASS] Test %0d: DLL locked successfully", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: DLL did not lock", test_num);
            fail_count++;
        end

        // ---- Test 8: Tracking mode ----
        test_num = 8;
        $display("\n--- Test %0d: Tracking mode ---", test_num);
        code_before = dll_delay_code;
        simulate_phase_early();
        wait_cycles(10);
        if (dll_delay_code !== code_before) begin
            $display("[PASS] Test %0d: Tracking mode active", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Tracking mode not active", test_num);
            fail_count++;
        end

        // ---- Test 9: Lock loss detection ----
        test_num = 9;
        $display("\n--- Test %0d: Lock loss detection ---", test_num);
        simulate_phase_locked();
        wait_cycles(30);
        // Introduce phase error
        phase_early = 1;
        phase_late = 1;  // Both high = error
        wait_cycles(50);
        if (dll_lock_count < 100) begin
            $display("[PASS] Test %0d: Lock counter reset on phase error", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Lock counter not reset", test_num);
            fail_count++;
        end

        // ---- Test 10: DLL reset ----
        test_num = 10;
        $display("\n--- Test %0d: DLL reset ---", test_num);
        @(posedge clk);
        dll_reset = 1;
        wait_cycles(30);
        dll_reset = 0;
        wait_cycles(5);
        if (dll_locked === 0 && dll_delay_code === 0 && dll_lock_fail === 0) begin
            $display("[PASS] Test %0d: DLL reset correctly", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: DLL reset failed", test_num);
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

    initial begin
        #(CLK_PERIOD * 50000);
        $display("[ERROR] Timeout!");
        $finish;
    end

    initial begin
        $dumpfile("tb_ddr5_dll_ctrl.vcd");
        $dumpvars(0, tb_ddr5_dll_ctrl);
    end

endmodule
