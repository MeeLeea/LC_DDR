// =============================================================================
// Testbench: tb_ddr5_cfg_apb
// Description: Verification of APB slave configuration interface
//              Tests: APB read/write transactions, register access, reset
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_cfg_apb();

    parameter int ADDR_W = 16;
    parameter int DATA_W = 32;
    parameter real CLK_PERIOD = 2.083;

    logic clk, rst_n;
    
    // APB interface
    logic [ADDR_W-1:0] paddr;
    logic [DATA_W-1:0] pwdata;
    logic [DATA_W-1:0] prdata;
    logic psel, penable, pwrite;
    logic pready, pslverr;
    
    // Register file interface
    logic reg_wr_en;
    logic [ADDR_W-1:0] reg_addr;
    logic [DATA_W-1:0] reg_wr_data;
    logic [DATA_W-1:0] reg_rd_data;

    ddr5_cfg_apb #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .pready(pready), .pslverr(pslverr),
        .reg_wr_en(reg_wr_en), .reg_addr(reg_addr),
        .reg_wr_data(reg_wr_data), .reg_rd_data(reg_rd_data)
    );

    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    int test_num = 0, pass_count = 0, fail_count = 0;

    // Local variables used across tests (must be at module scope for Xsim)
    logic [DATA_W-1:0] read_data;
    logic [DATA_W-1:0] rd1, rd2, rd3;
    int b2b_pass;
    int tmo_cnt;

    // Simple register model for testing
    logic [DATA_W-1:0] reg_file [256];
    
    always @(posedge clk) begin
        if (reg_wr_en) begin
            reg_file[reg_addr[7:0]] <= reg_wr_data;
        end
        reg_rd_data <= reg_file[reg_addr[7:0]];
    end

    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    // APB write task
    task automatic apb_write(logic [ADDR_W-1:0] addr, logic [DATA_W-1:0] data);
        @(posedge clk);
        paddr <= addr;
        pwdata <= data;
        pwrite <= 1;
        psel <= 1;
        penable <= 0;
        
        @(posedge clk);
        penable <= 1;
        
        wait(pready);
        @(posedge clk);
        
        psel <= 0;
        penable <= 0;
        pwrite <= 0;
    endtask

    // APB read task
    task automatic apb_read(logic [ADDR_W-1:0] addr, output logic [DATA_W-1:0] data);
        @(posedge clk);
        paddr <= addr;
        pwrite <= 0;
        psel <= 1;
        penable <= 0;
        
        @(posedge clk);
        penable <= 1;
        
        wait(pready);
        data = prdata;
        @(posedge clk);
        
        psel <= 0;
        penable <= 0;
    endtask

    initial begin
        $display("========================================");
        $display("Testbench: ddr5_cfg_apb");
        $display("ADDR_W=%0d, DATA_W=%0d", ADDR_W, DATA_W);
        $display("========================================");

        rst_n = 0;
        paddr = 0; pwdata = 0; psel = 0; penable = 0; pwrite = 0;
        reg_rd_data = 0;
        for (int i = 0; i < 256; i++) reg_file[i] = 0;

        repeat(10) @(posedge clk);
        rst_n = 1;
        wait_cycles(5);

        // ---- Test 1: Reset state ----
        test_num = 1;
        $display("\n--- Test %0d: Reset state ---", test_num);
        if (pready === 0 && pslverr === 0 && reg_wr_en === 0) begin
            $display("[PASS] Test %0d: APB idle after reset", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Invalid reset state", test_num);
            fail_count++;
        end

        // ---- Test 2: Single write transaction ----
        test_num = 2;
        $display("\n--- Test %0d: Single write transaction ---", test_num);
        apb_write(16'h0100, 32'hDEAD_BEEF);
        wait_cycles(2);
        if (reg_file[8'h00] === 32'hDEAD_BEEF) begin
            $display("[PASS] Test %0d: Write to 0x0100 = 0x%08h", test_num, reg_file[8'h00]);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Write failed (got 0x%08h)", test_num, reg_file[8'h00]);
            fail_count++;
        end

        // ---- Test 3: Single read transaction ----
        test_num = 3;
        $display("\n--- Test %0d: Single read transaction ---", test_num);
        apb_read(16'h0100, read_data);
        if (read_data === 32'hDEAD_BEEF) begin
            $display("[PASS] Test %0d: Read from 0x0100 = 0x%08h", test_num, read_data);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Read mismatch (got 0x%08h)", test_num, read_data);
            fail_count++;
        end

        // ---- Test 4: Multiple register writes ----
        test_num = 4;
        $display("\n--- Test %0d: Multiple register writes ---", test_num);
        apb_write(16'h0104, 32'h1111_1111);
        apb_write(16'h0108, 32'h2222_2222);
        apb_write(16'h010C, 32'h3333_3333);
        wait_cycles(2);
        if (reg_file[8'h04] === 32'h1111_1111 &&
            reg_file[8'h08] === 32'h2222_2222 &&
            reg_file[8'h0C] === 32'h3333_3333) begin
            $display("[PASS] Test %0d: Multiple writes successful", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Multiple writes failed", test_num);
            fail_count++;
        end

        // ---- Test 5: Multiple register reads ----
        test_num = 5;
        $display("\n--- Test %0d: Multiple register reads ---", test_num);
        apb_read(16'h0104, rd1);
        apb_read(16'h0108, rd2);
        apb_read(16'h010C, rd3);
        if (rd1 === 32'h1111_1111 && rd2 === 32'h2222_2222 && rd3 === 32'h3333_3333) begin
            $display("[PASS] Test %0d: Multiple reads correct", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Read mismatch", test_num);
            fail_count++;
        end

        // ---- Test 6: Back-to-back transactions ----
        test_num = 6;
        $display("\n--- Test %0d: Back-to-back transactions ---", test_num);
        for (int i = 0; i < 10; i++) begin
            apb_write(16'h0200 + i*4, 32'hA000_0000 + i);
        end
        wait_cycles(2);
        b2b_pass = 0;
        for (int i = 0; i < 10; i++) begin
            if (reg_file[8'h00 + i*4] === 32'hA000_0000 + i) b2b_pass++;
        end
        if (b2b_pass == 10) begin
            $display("[PASS] Test %0d: 10 back-to-back writes correct", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Only %0d/10 correct", test_num, b2b_pass);
            fail_count++;
        end

        // ---- Test 7: Write then read same address ----
        test_num = 7;
        $display("\n--- Test %0d: Write then read same address ---", test_num);
        apb_write(16'h0300, 32'hCAFE_BABE);
        apb_read(16'h0300, read_data);
        if (read_data === 32'hCAFE_BABE) begin
            $display("[PASS] Test %0d: Write-read consistency", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Read mismatch (0x%08h)", test_num, read_data);
            fail_count++;
        end

        // ---- Test 8: APB protocol timing ----
        test_num = 8;
        $display("\n--- Test %0d: APB protocol timing ---", test_num);
        @(posedge clk);
        paddr <= 16'h0400;
        pwdata <= 32'h1234_5678;
        pwrite <= 1;
        psel <= 1;
        penable <= 0;
        
        @(posedge clk);
        if (psel && !penable) begin
            $display("[PASS] Test %0d: SETUP phase detected", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: SETUP phase not detected", test_num);
            fail_count++;
        end
        
        penable <= 1;
        @(posedge clk);
        // Wait for pready (DUT may assert it after 1+ cycles)
        if (!pready) begin
            tmo_cnt = 0;
            while (!pready && tmo_cnt < 100) begin @(posedge clk); tmo_cnt++; end
        end
        if (psel && penable && pready) begin
            $display("[PASS] Test %0d: ACCESS phase with pready", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: ACCESS phase issue (psel=%0b penable=%0b pready=%0b)", test_num, psel, penable, pready);
            fail_count++;
        end
        
        psel <= 0; penable <= 0; pwrite <= 0;

        // ---- Test 9: No slave error ----
        test_num = 9;
        $display("\n--- Test %0d: No slave error ---", test_num);
        apb_write(16'hFFFF, 32'hDEAD_DEAD);
        wait_cycles(2);
        if (pslverr === 0) begin
            $display("[PASS] Test %0d: No slave error on any address", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Unexpected slave error", test_num);
            fail_count++;
        end

        // ---- Test 10: Idle state after transactions ----
        test_num = 10;
        $display("\n--- Test %0d: Idle state after transactions ---", test_num);
        wait_cycles(10);
        if (pready === 0 && psel === 0 && penable === 0) begin
            $display("[PASS] Test %0d: APB returns to idle", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: APB not idle", test_num);
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
    initial begin $dumpfile("tb_ddr5_cfg_apb.vcd"); $dumpvars(0, tb_ddr5_cfg_apb); end

endmodule
