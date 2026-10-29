// =============================================================================
// Testbench: tb_ddr5_bank_manager
// Description: Verification of 32-bank state manager (4 BG x 8 banks)
//              Tests: ACT/PRE/REF state transitions, page hit/miss/conflict
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_bank_manager();

    parameter int NUM_BANKS = 32;
    parameter int ROW_W     = 18;
    parameter real CLK_PERIOD = 2.083;

    logic clk, rst_n;
    logic cmd_valid;
    logic [3:0] cmd_type;
    logic [4:0] cmd_bank;
    logic [ROW_W-1:0] cmd_row;
    logic page_hit, page_miss, page_conflict, bank_ready;
    logic [2:0] bank_state [NUM_BANKS];
    logic [ROW_W-1:0] open_row [NUM_BANKS];
    logic row_open [NUM_BANKS];

    ddr5_bank_manager #(
        .NUM_BANKS(NUM_BANKS),
        .ROW_W(ROW_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(cmd_valid), .cmd_type(cmd_type),
        .cmd_bank(cmd_bank), .cmd_row(cmd_row),
        .page_hit(page_hit), .page_miss(page_miss),
        .page_conflict(page_conflict), .bank_ready(bank_ready),
        .bank_state(bank_state), .open_row(open_row), .row_open(row_open)
    );

    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    int test_num = 0, pass_count = 0, fail_count = 0;

    task automatic issue_cmd(logic [3:0] type_, logic [4:0] bank_, logic [ROW_W-1:0] row_);
        // Drive between clock edges so there is no race with the DUT, then keep
        // cmd_valid asserted until the next command: page_hit/miss/conflict and
        // bank_ready are combinational functions of (cmd_valid, cmd_type,
        // cmd_bank, cmd_row), so the checks that follow sample a valid command.
        @(negedge clk);
        cmd_valid = 1'b1;
        cmd_type  = type_;
        cmd_bank  = bank_;
        cmd_row   = row_;
        @(posedge clk);   // command is consumed here
        #1;               // sampling window for the combinational status
    endtask

    // Sample combinational outputs during the cmd_valid=1 cycle (after NBA settles)
    task automatic check_page_status(string desc, bit exp_hit, bit exp_miss, bit exp_conflict, bit exp_ready);
        #1;
        if (page_hit === exp_hit && page_miss === exp_miss &&
            page_conflict === exp_conflict && bank_ready === exp_ready) begin
            $display("[PASS] %s", desc);
            pass_count++;
        end else begin
            $display("[FAIL] %s (hit=%0b miss=%0b conf=%0b rdy=%0b, exp hit=%0b miss=%0b conf=%0b rdy=%0b)",
                     desc, page_hit, page_miss, page_conflict, bank_ready,
                     exp_hit, exp_miss, exp_conflict, exp_ready);
            fail_count++;
        end
    endtask

    initial begin
        $display("========================================");
        $display("Testbench: ddr5_bank_manager");
        $display("========================================");

        rst_n = 0; cmd_valid = 0; cmd_type = 0; cmd_bank = 0; cmd_row = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // ---- Test 1: All banks IDLE after reset ----
        test_num = 1;
        $display("\n--- Test %0d: All banks IDLE after reset ---", test_num);
        @(posedge clk);
        if (bank_state[0] === 3'b000 && bank_state[31] === 3'b000) begin
            $display("[PASS] Test %0d: Banks in IDLE state", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Banks not in IDLE", test_num);
            fail_count++;
        end

        // ---- Test 2: ACT transitions bank to ACTIVE ----
        test_num = 2;
        $display("\n--- Test %0d: ACT → ACTIVE state ---", test_num);
        issue_cmd(4'h1, 5'd0, 18'h12345);  // ACT bank 0, row 0x12345
        @(posedge clk);
        if (bank_state[0] === 3'b001 && open_row[0] === 18'h12345 && row_open[0] === 1'b1) begin
            $display("[PASS] Test %0d: Bank 0 ACTIVE, row=0x%05h", test_num, open_row[0]);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Bank state incorrect", test_num);
            fail_count++;
        end

        // ---- Test 3: Page hit detection ----
        test_num = 3;
        $display("\n--- Test %0d: Page hit detection ---", test_num);
        issue_cmd(4'h2, 5'd0, 18'h12345);  // RD same row
        check_page_status($sformatf("Test %0d: Page hit detected", test_num), 1, 0, 0, 1);

        // ---- Test 4: Page conflict detection ----
        test_num = 4;
        $display("\n--- Test %0d: Page conflict detection ---", test_num);
        issue_cmd(4'h2, 5'd0, 18'hABCDE);  // RD different row
        @(posedge clk);
        if (page_conflict === 1'b1 && bank_ready === 1'b0) begin
            $display("[PASS] Test %0d: Page conflict detected", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Page conflict not detected", test_num);
            fail_count++;
        end

        // ---- Test 5: PRE transitions to PRECHARGING ----
        test_num = 5;
        $display("\n--- Test %0d: PRE → PRECHARGING ---", test_num);
        issue_cmd(4'h4, 5'd0, 18'h00000);  // PRE bank 0
        @(posedge clk);
        if (bank_state[0] === 3'b010 && row_open[0] === 1'b0) begin
            $display("[PASS] Test %0d: Bank 0 PRECHARGING", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: PRE state incorrect", test_num);
            fail_count++;
        end

        // ---- Test 6: Page miss on IDLE bank ----
        test_num = 6;
        $display("\n--- Test %0d: Page miss on IDLE bank ---", test_num);
        wait_cycles(5);
        issue_cmd(4'h2, 5'd1, 18'h54321);  // RD bank 1 (IDLE)
        @(posedge clk);
        if (page_miss === 1'b1 && bank_ready === 1'b1) begin
            $display("[PASS] Test %0d: Page miss detected", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Page miss not detected", test_num);
            fail_count++;
        end

        // ---- Test 7: REF transitions to REFRESHING ----
        test_num = 7;
        $display("\n--- Test %0d: REF → REFRESHING ---", test_num);
        issue_cmd(4'h5, 5'd2, 18'h00000);  // REF bank 2
        @(posedge clk);
        if (bank_state[2] === 3'b011) begin
            $display("[PASS] Test %0d: Bank 2 REFRESHING", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: REF state incorrect", test_num);
            fail_count++;
        end

        // ---- Test 8: Multiple banks independent ----
        test_num = 8;
        $display("\n--- Test %0d: Multiple banks independent ---", test_num);
        issue_cmd(4'h1, 5'd10, 18'h11111);  // ACT bank 10
        issue_cmd(4'h1, 5'd11, 18'h22222);  // ACT bank 11
        issue_cmd(4'h1, 5'd12, 18'h33333);  // ACT bank 12
        @(posedge clk);
        if (bank_state[10] === 3'b001 && bank_state[11] === 3'b001 && 
            bank_state[12] === 3'b001 && open_row[10] === 18'h11111 &&
            open_row[11] === 18'h22222 && open_row[12] === 18'h33333) begin
            $display("[PASS] Test %0d: Multiple banks ACTIVE independently", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Multi-bank state incorrect", test_num);
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

    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    initial begin #(CLK_PERIOD * 50000); $display("[ERROR] Timeout!"); $finish; end
    initial begin $dumpfile("tb_ddr5_bank_manager.vcd"); $dumpvars(0, tb_ddr5_bank_manager); end

endmodule
