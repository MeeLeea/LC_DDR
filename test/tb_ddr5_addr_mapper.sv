// =============================================================================
// Testbench: tb_ddr5_addr_mapper
// Description: Verification of AXI address to DDR5 Row/BG/Bank/Col mapping
//              Tests both mapping modes (Row-BG-Bank-Col and BG-Row-Bank-Col)
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_addr_mapper();

    // Parameters
    parameter real CLK_PERIOD = 5.0;
    parameter int AXI_ADDR_W = 34;
    parameter int ROW_W = 18;
    parameter int BG_W = 3;
    parameter int BA_W = 3;
    parameter int COL_W = 10;  // 与 RTL `DDR5_COL_W`=10 一致 (sub_channel 为独立输出, 不占 col 位宽)
    parameter int RANK_W = 2;

    // Signals
    logic clk;
    logic rst_n;
    logic [AXI_ADDR_W-1:0] axi_addr;
    logic [ROW_W-1:0] row_addr;
    logic [BG_W-1:0] bg_addr;
    logic [BA_W-1:0] bank_addr;
    logic [COL_W-1:0] col_addr;
    logic [RANK_W-1:0] rank_addr;
    logic [1:0] map_mode;
    logic sub_channel;   // B-05: sub-channel select output

    // DUT
    ddr5_addr_mapper dut (
        .clk(clk),
        .rst_n(rst_n),
        .axi_addr(axi_addr),
        .row_addr(row_addr),
        .bg_addr(bg_addr),
        .bank_addr(bank_addr),
        .col_addr(col_addr),
        .rank_addr(rank_addr),
        .sub_channel(sub_channel),
        .map_mode(map_mode)
    );

    // Functional coverage collector (test/ddr5_covergroups.sv), driven hierarchically
    ddr5_coverage_collector u_cov ();
    assign u_cov.clk         = clk;
    assign u_cov.bg_addr     = bg_addr;
    assign u_cov.bank_addr   = bank_addr;
    assign u_cov.rank_addr   = rank_addr;
    assign u_cov.row_addr    = row_addr;
    assign u_cov.col_addr    = col_addr;
    assign u_cov.sub_channel = sub_channel;

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test variables
    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Check task
    task automatic check_mapping(string test_name, 
                                  logic [ROW_W-1:0] exp_row,
                                  logic [BG_W-1:0] exp_bg,
                                  logic [BA_W-1:0] exp_bank,
                                  logic [COL_W-1:0] exp_col,
                                  logic [RANK_W-1:0] exp_rank);
        test_num++;
        @(posedge clk);
        #1;
        if (row_addr === exp_row && bg_addr === exp_bg && 
            bank_addr === exp_bank && col_addr === exp_col && 
            rank_addr === exp_rank) begin
            $display("[PASS] Test %0d: %s", test_num, test_name);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s", test_num, test_name);
            $display("  Expected: row=0x%05h bg=0x%01h bank=0x%01h col=0x%03h rank=0x%01h",
                     exp_row, exp_bg, exp_bank, exp_col, exp_rank);
            $display("  Got:      row=0x%05h bg=0x%01h bank=0x%01h col=0x%03h rank=0x%01h",
                     row_addr, bg_addr, bank_addr, col_addr, rank_addr);
            fail_count++;
        end
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Testbench: ddr5_addr_mapper");
        $display("========================================");

        // Init
        rst_n = 0;
        axi_addr = '0;
        map_mode = 2'b00;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // ==== Mode 0: Row-BG-Bank-Col ====
        $display("\n--- Mode 0: Row-BG-Bank-Col ---");
        map_mode = 2'b00;

        // Test 1: Address 0x0000_0000
        test_num = 1;
        axi_addr = 34'h0_0000_0000;
        check_mapping("Addr 0x0 (Mode 0)", 
                      18'h00000, 3'h0, 3'h0, 10'h000, 2'h0);

        // Test 2: Address with col bits set
        axi_addr = 34'h0_0000_00FF;
        check_mapping("Col bits [7:0]=0xFF", 
                      18'h00000, 3'h0, 3'h0, 10'h0FF, 2'h0);

        // Test 3: Address with bank bits set
        axi_addr = 34'h0_0000_0700;
        check_mapping("Bank bits [10:8]=0x7", 
                      18'h00000, 3'h0, 3'h7, 10'h000, 2'h0);

        // Test 4: Address with BG bits set
        axi_addr = 34'h0_0000_3800;
        check_mapping("BG bits [13:11]=0x7", 
                      18'h00000, 3'h7, 3'h0, 10'h000, 2'h0);

        // Test 5: Address with row bits set
        axi_addr = 34'h0_ABCD_C000;
        check_mapping("Row bits [31:14]", 
                      18'h2AF37, 3'h0, 3'h0, 10'h000, 2'h0);

        // Test 6: Address with rank bits set
        axi_addr = 34'h3_0000_0000;
        check_mapping("Rank bits [33:32]=0x3", 
                      18'h00000, 3'h0, 3'h0, 10'h000, 2'h3);

        // Test 7: Full address
        // Mode 0 定义: [33:32]Rank [31:14]Row [13:11]BG [10:8]Bank [7:0]Col
        // 0x2_ABCD_EF45 -> bit[13:11]=3'h5 (BG), bit[10:8]=3'h7 (Bank)
        axi_addr = 34'h2_ABCD_EF45;
        check_mapping("Full address (Mode 0)", 
                      18'h2AF37, 3'h5, 3'h7, 10'h045, 2'h2);

        // ==== Mode 1: BG-Row-Bank-Col ====
        $display("\n--- Mode 1: BG-Row-Bank-Col ---");
        map_mode = 2'b01;

        // Test 8: Address 0x0000_0000
        axi_addr = 34'h0_0000_0000;
        check_mapping("Addr 0x0 (Mode 1)", 
                      18'h00000, 3'h0, 3'h0, 10'h000, 2'h0);

        // Test 9: BG bits in mode 1
        axi_addr = 34'h3_8000_0000;
        check_mapping("BG bits [33:31]=0x7 (Mode 1)", 
                      18'h00000, 3'h7, 3'h0, 10'h000, 2'h0);

        // Test 10: Rank bits in mode 1
        axi_addr = 34'h1_8000_0000;
        check_mapping("Rank bits [30:29]=0x3 (Mode 1)", 
                      18'h00000, 3'h3, 3'h0, 10'h000, 2'h0);

        // Test 11: Row bits in mode 1
        // 0x0_1FFF_FC00 -> bit[10:8]=3'h4 落在 Bank 域 (Mode 1 Bank 仍为 [10:8])
        axi_addr = 34'h0_1FFF_FC00;
        check_mapping("Row bits [28:11] (Mode 1)", 
                      18'h3FFFF, 3'h0, 3'h4, 10'h000, 2'h0);

        // ==== Edge Cases ====
        $display("\n--- Edge Cases ---");
        map_mode = 2'b00;

        // Test 12: Max address
        // Col 域仅 [7:0], 故全 1 地址下 col 最大为 0x0FF (非 0x3FF)
        axi_addr = 34'h3_FFFF_FFFF;
        check_mapping("Max address (Mode 0)", 
                      18'h3FFFF, 3'h7, 3'h7, 10'h0FF, 2'h3);

        // Test 13: Default mode (invalid map_mode)
        map_mode = 2'b11;
        axi_addr = 34'h2_ABCD_EF45;
        check_mapping("Invalid mode (should default to Mode 0)", 
                      18'h2AF37, 3'h5, 3'h7, 10'h045, 2'h2);

        // ==== B-05: Sub-channel select checks ====
        $display("\n--- B-05: Sub-channel select (addr bit[3]) ---");
        map_mode = 2'b00;
        axi_addr = 34'h0_0000_0000; @(posedge clk); #1;
        if (sub_channel === 1'b0) begin $display("[PASS] sub_ch=0 for addr[3]=0"); pass_count++; end
        else begin $display("[FAIL] sub_ch expected 0"); fail_count++; end
        axi_addr = 34'h0_0000_0008; @(posedge clk); #1;  // bit[3]=1
        if (sub_channel === 1'b1) begin $display("[PASS] sub_ch=1 for addr[3]=1"); pass_count++; end
        else begin $display("[FAIL] sub_ch expected 1"); fail_count++; end

        // Summary
        $display("\n========================================");
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
        $dumpfile("tb_ddr5_addr_mapper.vcd");
        $dumpvars(0, tb_ddr5_addr_mapper);
    end

endmodule
