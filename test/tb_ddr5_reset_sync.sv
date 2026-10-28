// =============================================================================
// Testbench: tb_ddr5_reset_sync
// Description: Verification of async assert, sync deassert reset synchronizer
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_reset_sync();

    // Parameters
    parameter int STAGES = 2;
    parameter real CLK_PERIOD = 5.0;  // 200 MHz

    // Signals
    logic clk;
    logic async_rst_n;
    logic sync_rst_n;

    // DUT instantiation
    ddr5_reset_sync #(
        .STAGES(STAGES)
    ) dut (
        .clk(clk),
        .async_rst_n(async_rst_n),
        .sync_rst_n(sync_rst_n)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test variables
    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Test task
    task automatic check_output(string test_name, logic expected);
        test_num++;
        if (sync_rst_n === expected) begin
            $display("[PASS] Test %0d: %s - sync_rst_n=%0b (expected %0b)", 
                     test_num, test_name, sync_rst_n, expected);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s - sync_rst_n=%0b (expected %0b)", 
                     test_num, test_name, sync_rst_n, expected);
            fail_count++;
        end
    endtask

    // Main test sequence
    initial begin
        $display("========================================");
        $display("Testbench: ddr5_reset_sync");
        $display("========================================");

        // Initialize
        async_rst_n = 0;
        
        // Test 1: Async assert - immediate reset
        #1;
        check_output("Async assert (active low)", 1'b0);
        
        // Test 2: Hold reset for multiple cycles
        repeat(5) @(posedge clk);
        check_output("Reset held for 5 cycles", 1'b0);
        
        // Test 3: Release reset - sync deassert
        async_rst_n = 1;
        @(posedge clk);
        check_output("First cycle after reset release", 1'b0);
        
        @(posedge clk);
        check_output("Second cycle after reset release (STAGES=2)", 1'b1);
        
        // Test 4: Stable operation
        repeat(10) @(posedge clk);
        check_output("Stable after reset", 1'b1);
        
        // Test 5: Re-assert reset
        async_rst_n = 0;
        #1;  // Immediate (async)
        check_output("Re-assert reset (async)", 1'b0);
        
        // Test 6: Multiple reset cycles
        repeat(3) @(posedge clk);
        check_output("Reset held for 3 cycles", 1'b0);
        
        // Test 7: Release again
        async_rst_n = 1;
        repeat(STAGES) @(posedge clk);
        check_output("Sync deassert after STAGES cycles", 1'b1);
        
        // Test 8: Glitch on async_rst_n (should be filtered by sync chain)
        async_rst_n = 0;
        #(CLK_PERIOD/4);  // Short glitch
        async_rst_n = 1;
        @(posedge clk);
        check_output("Glitch rejection (async path still sees it)", 1'b0);
        
        repeat(STAGES) @(posedge clk);
        check_output("Recovery after glitch", 1'b1);
        
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

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 1000);
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_ddr5_reset_sync.vcd");
        $dumpvars(0, tb_ddr5_reset_sync);
    end

endmodule
