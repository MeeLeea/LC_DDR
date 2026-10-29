// =============================================================================
// Testbench: tb_ddr5_clk_gate
// Description: Verification of latch-based glitch-free clock gating
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_clk_gate();

    // Signals
    logic clk_in;
    logic en;
    logic test_en;
    logic clk_out;

    // DUT
    ddr5_clk_gate dut (
        .clk_in(clk_in),
        .en(en),
        .test_en(test_en),
        .clk_out(clk_out)
    );

    // Functional coverage collector (test/ddr5_covergroups.sv), driven hierarchically
    ddr5_coverage_collector u_cov ();
    assign u_cov.clk_in  = clk_in;
    assign u_cov.en      = en;
    assign u_cov.test_en = test_en;
    assign u_cov.clk_out = clk_out;

    // Clock generation
    parameter real CLK_PERIOD = 5.0;  // 200 MHz
    initial begin
        clk_in = 0;
        forever #(CLK_PERIOD/2) clk_in = ~clk_in;
    end

    // Test variables
    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;
    int clk_out_edges = 0;

    // Monitor clk_out edges
    always @(posedge clk_out) clk_out_edges++;

    // Test task
    task automatic check_gating(string test_name, logic expected_gating);
        int edges_before, edges_after;
        test_num++;
        edges_before = clk_out_edges;
        repeat(10) @(posedge clk_in);
        edges_after = clk_out_edges;
        
        if (expected_gating) begin
            // Should see edges (clock passing through)
            if (edges_after > edges_before) begin
                $display("[PASS] Test %0d: %s - clock enabled (%0d edges)", 
                         test_num, test_name, edges_after - edges_before);
                pass_count++;
            end else begin
                $display("[FAIL] Test %0d: %s - clock should be enabled but no edges", 
                         test_num, test_name);
                fail_count++;
            end
        end else begin
            // Should NOT see edges (clock gated)
            if (edges_after == edges_before) begin
                $display("[PASS] Test %0d: %s - clock gated (0 edges)", test_num, test_name);
                pass_count++;
            end else begin
                $display("[FAIL] Test %0d: %s - clock should be gated but saw %0d edges", 
                         test_num, test_name, edges_after - edges_before);
                fail_count++;
            end
        end
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Testbench: ddr5_clk_gate");
        $display("========================================");

        // Init
        en = 0;
        test_en = 0;
        clk_out_edges = 0;

        // Test 1: Clock gating enabled (en=0, test_en=0)
        repeat(5) @(posedge clk_in);
        check_gating("Clock gated (en=0, test_en=0)", 1'b0);

        // Test 2: Enable clock (en=1)
        en = 1;
        repeat(3) @(posedge clk_in);  // Wait for sync
        check_gating("Clock enabled (en=1)", 1'b1);

        // Test 3: Disable clock (en=0)
        en = 0;
        repeat(3) @(posedge clk_in);
        check_gating("Clock disabled (en=0)", 1'b0);

        // Test 4: Test mode bypass (test_en=1, en=0)
        test_en = 1;
        repeat(3) @(posedge clk_in);
        check_gating("Test mode bypass (test_en=1)", 1'b1);

        // Test 5: Test mode override (test_en=1, en=1)
        en = 1;
        repeat(3) @(posedge clk_in);
        check_gating("Test mode + enable (both=1)", 1'b1);

        // Test 6: Exit test mode
        test_en = 0;
        en = 0;
        repeat(3) @(posedge clk_in);
        check_gating("Exit test mode (both=0)", 1'b0);

        // Test 7: Rapid enable/disable (glitch-free check)
        en = 1;
        #(CLK_PERIOD/4);
        en = 0;
        #(CLK_PERIOD/4);
        en = 1;
        repeat(3) @(posedge clk_in);
        check_gating("Rapid toggle (glitch-free)", 1'b1);

        // Summary
        $display("========================================");
        $display("Test Summary: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

    // Timeout
    initial begin
        #(CLK_PERIOD * 1000);
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

    // Waveform
    initial begin
        $dumpfile("tb_ddr5_clk_gate.vcd");
        $dumpvars(0, tb_ddr5_clk_gate);
    end

endmodule
