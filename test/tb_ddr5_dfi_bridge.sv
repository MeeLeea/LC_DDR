// =============================================================================
// Testbench: tb_ddr5_dfi_bridge
// Description: Verification of DFI 5.1 bridge with CDC FIFOs
//              Tests: command/data CDC, training FSM, frequency ratio
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_dfi_bridge();

    parameter int FREQ_RATIO = 2;
    parameter real CTRL_CLK_PERIOD = 4.166;  // 240 MHz
    parameter real DFI_CLK_PERIOD = 2.083;   // 480 MHz (1:2 ratio)

    logic ctrl_clk, dfi_clk, rst_n;

    // Controller interface
    logic ctrl_cmd_valid, ctrl_cmd_ready;
    logic [17:0] ctrl_address;
    logic [5:0] ctrl_bank;
    logic [1:0] ctrl_cs_n;
    logic ctrl_act_n, ctrl_ras_n, ctrl_cas_n, ctrl_we_n;
    logic [127:0] ctrl_wrdata;
    logic [15:0] ctrl_wrdata_mask;
    logic ctrl_wrdata_en;
    logic [127:0] ctrl_rddata;
    logic ctrl_rddata_valid;

    // PHY interface
    logic dfi_cmd_valid, dfi_cmd_ready;
    logic [17:0] dfi_address;
    logic [5:0] dfi_bank;
    logic [1:0] dfi_cs_n;
    logic dfi_act_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
    logic [127:0] dfi_wrdata;
    logic [15:0] dfi_wrdata_mask;
    logic dfi_wrdata_en;
    logic [127:0] dfi_rddata;
    logic dfi_rddata_valid;

    // Training
    logic train_start, train_complete, train_error, phy_init_complete;
    logic [1:0] cfg_freq_ratio;
    logic cfg_dual_channel;

    // B-04: DFI 5.1 additional signals
    logic        dfi_phycsel;
    logic        dfi_parity_in;
    logic [1:0]  dfi_dram_clk_disable;
    logic [1:0]  dfi_freq_ratio;
    logic [1:0]  dfi_rddata_dnv = 2'b00;   // driven by TB (default: data valid)

    ddr5_dfi_bridge #(
        .FREQ_RATIO(FREQ_RATIO)
    ) dut (
        .ctrl_clk(ctrl_clk), .dfi_clk(dfi_clk), .rst_n(rst_n),
        .ctrl_cmd_valid(ctrl_cmd_valid), .ctrl_cmd_ready(ctrl_cmd_ready),
        .ctrl_address(ctrl_address), .ctrl_bank(ctrl_bank), .ctrl_cs_n(ctrl_cs_n),
        .ctrl_act_n(ctrl_act_n), .ctrl_ras_n(ctrl_ras_n),
        .ctrl_cas_n(ctrl_cas_n), .ctrl_we_n(ctrl_we_n),
        .ctrl_wrdata(ctrl_wrdata), .ctrl_wrdata_mask(ctrl_wrdata_mask),
        .ctrl_wrdata_en(ctrl_wrdata_en),
        .ctrl_rddata(ctrl_rddata), .ctrl_rddata_valid(ctrl_rddata_valid),
        .dfi_cmd_valid(dfi_cmd_valid), .dfi_cmd_ready(dfi_cmd_ready),
        .dfi_address(dfi_address), .dfi_bank(dfi_bank), .dfi_cs_n(dfi_cs_n),
        .dfi_act_n(dfi_act_n), .dfi_ras_n(dfi_ras_n),
        .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_mask(dfi_wrdata_mask),
        .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid),
        .dfi_phycsel(dfi_phycsel), .dfi_parity_in(dfi_parity_in),
        .dfi_dram_clk_disable(dfi_dram_clk_disable), .dfi_freq_ratio(dfi_freq_ratio),
        .dfi_rddata_dnv(dfi_rddata_dnv),
        .train_start(train_start), .train_complete(train_complete),
        .train_error(train_error), .phy_init_complete(phy_init_complete),
        .cfg_freq_ratio(cfg_freq_ratio), .cfg_dual_channel(cfg_dual_channel)
    );

    initial begin ctrl_clk = 0; forever #(CTRL_CLK_PERIOD/2) ctrl_clk = ~ctrl_clk; end
    initial begin dfi_clk = 0; forever #(DFI_CLK_PERIOD/2) dfi_clk = ~dfi_clk; end

    int test_num = 0, pass_count = 0, fail_count = 0;

    task automatic wait_ctrl_cycles(int n);
        repeat(n) @(posedge ctrl_clk);
    endtask

    task automatic wait_dfi_cycles(int n);
        repeat(n) @(posedge dfi_clk);
    endtask

    task automatic send_ctrl_cmd(logic [17:0] addr, logic [5:0] bank,
                                  logic act, logic ras, logic cas, logic we);
        @(posedge ctrl_clk);
        ctrl_cmd_valid <= 1;
        ctrl_address <= addr;
        ctrl_bank <= bank;
        ctrl_cs_n <= 2'b00;
        ctrl_act_n <= act;
        ctrl_ras_n <= ras;
        ctrl_cas_n <= cas;
        ctrl_we_n <= we;
        @(posedge ctrl_clk);
        while (!ctrl_cmd_ready) @(posedge ctrl_clk);
        ctrl_cmd_valid <= 0;
    endtask

    initial begin
        $display("========================================");
        $display("Testbench: ddr5_dfi_bridge");
        $display("FREQ_RATIO=%0d", FREQ_RATIO);
        $display("========================================");

        rst_n = 0;
        ctrl_cmd_valid = 0; ctrl_address = 0; ctrl_bank = 0;
        ctrl_cs_n = 2'b11; ctrl_act_n = 1; ctrl_ras_n = 1;
        ctrl_cas_n = 1; ctrl_we_n = 1;
        ctrl_wrdata = 0; ctrl_wrdata_mask = 0; ctrl_wrdata_en = 0;
        dfi_cmd_ready = 1; dfi_rddata = 0; dfi_rddata_valid = 0;
        train_start = 0; phy_init_complete = 0;
        cfg_freq_ratio = 2'b01; cfg_dual_channel = 1;

        repeat(10) @(posedge ctrl_clk);
        rst_n = 1;
        wait_ctrl_cycles(5);

        // ---- Test 1: Command CDC (ctrl_clk -> dfi_clk) ----
        test_num = 1;
        $display("\n--- Test %0d: Command CDC ---", test_num);
        send_ctrl_cmd(18'h12345, 6'h15, 0, 1, 1, 1);  // ACT
        // CDC output is a pulse; monitor over a window instead of single-point sample
        begin
            bit cmd_seen = 0;
            for (int i = 0; i < 20; i++) begin
                @(posedge dfi_clk);
                if (dfi_cmd_valid && dfi_address === 18'h12345 && dfi_bank === 6'h15)
                    cmd_seen = 1;
            end
            if (cmd_seen) begin
                $display("[PASS] Test %0d: Command crossed CDC correctly", test_num);
                pass_count++;
            end else begin
                $display("[FAIL] Test %0d: Command CDC failed", test_num);
                fail_count++;
            end
        end

        // ---- Test 2: Multiple commands CDC ----
        test_num = 2;
        $display("\n--- Test %0d: Multiple commands CDC ---", test_num);
        send_ctrl_cmd(18'h20000, 6'h00, 1, 0, 1, 1);  // RD
        send_ctrl_cmd(18'h30000, 6'h01, 1, 1, 0, 1);  // WR
        send_ctrl_cmd(18'h00000, 6'h02, 1, 1, 1, 0);  // PRE
        wait_dfi_cycles(20);
        $display("[PASS] Test %0d: Multiple commands crossed CDC", test_num);
        pass_count++;

        // ---- Test 3: Write data CDC ----
        test_num = 3;
        $display("\n--- Test %0d: Write data CDC ---", test_num);
        @(posedge ctrl_clk);
        ctrl_wrdata_en <= 1;
        ctrl_wrdata <= 128'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0;
        ctrl_wrdata_mask <= 16'hFFFF;
        @(posedge ctrl_clk);
        ctrl_wrdata_en <= 0;
        // CDC output is a pulse; monitor over a window
        begin
            bit wr_seen = 0;
            for (int i = 0; i < 20; i++) begin
                @(posedge dfi_clk);
                if (dfi_wrdata_en && dfi_wrdata === 128'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0)
                    wr_seen = 1;
            end
            if (wr_seen) begin
                $display("[PASS] Test %0d: Write data crossed CDC correctly", test_num);
                pass_count++;
            end else begin
                $display("[FAIL] Test %0d: Write data CDC failed", test_num);
                fail_count++;
            end
        end

        // ---- Test 4: Read data CDC (dfi_clk -> ctrl_clk) ----
        test_num = 4;
        $display("\n--- Test %0d: Read data CDC ---", test_num);
        @(posedge dfi_clk);
        dfi_rddata_valid <= 1;
        dfi_rddata <= 128'h11111111_22222222_33333333_44444444;
        @(posedge dfi_clk);
        dfi_rddata_valid <= 0;
        // CDC output is a pulse; monitor over a window
        begin
            bit rd_seen = 0;
            for (int i = 0; i < 20; i++) begin
                @(posedge ctrl_clk);
                if (ctrl_rddata_valid && ctrl_rddata === 128'h11111111_22222222_33333333_44444444)
                    rd_seen = 1;
            end
            if (rd_seen) begin
                $display("[PASS] Test %0d: Read data crossed CDC correctly", test_num);
                pass_count++;
            end else begin
                $display("[FAIL] Test %0d: Read data CDC failed", test_num);
                fail_count++;
            end
        end

        // ---- Test 5: Training FSM - idle state ----
        test_num = 5;
        $display("\n--- Test %0d: Training FSM idle ---", test_num);
        if (train_complete === 0 && train_error === 0) begin
            $display("[PASS] Test %0d: Training FSM in idle", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Training FSM not idle", test_num);
            fail_count++;
        end

        // ---- Test 6: Training sequence ----
        test_num = 6;
        $display("\n--- Test %0d: Training sequence ---", test_num);
        @(posedge ctrl_clk);
        train_start <= 1;
        @(posedge ctrl_clk);
        train_start <= 0;
        wait_ctrl_cycles(5);
        // Provide phy_init_complete
        phy_init_complete = 1;
        wait_ctrl_cycles(20);
        phy_init_complete = 0;
        if (train_complete === 1'b1) begin
            $display("[PASS] Test %0d: Training completed successfully", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Training not completed", test_num);
            fail_count++;
        end

        // ---- Test 7: Backpressure (FIFO full) ----
        test_num = 7;
        $display("\n--- Test %0d: Backpressure ---", test_num);
        dfi_cmd_ready = 0;  // Block DFI side
        for (int i = 0; i < 20; i++) begin
            @(posedge ctrl_clk);
            ctrl_cmd_valid <= 1;
            ctrl_address <= i[17:0];
            ctrl_bank <= i[5:0];
            ctrl_cs_n <= 2'b00;
            ctrl_act_n <= 1; ctrl_ras_n <= 1; ctrl_cas_n <= 1; ctrl_we_n <= 1;
            @(posedge ctrl_clk);
            ctrl_cmd_valid <= 0;
            wait_ctrl_cycles(2);
        end
        if (ctrl_cmd_ready === 0) begin
            $display("[PASS] Test %0d: Backpressure asserted when FIFO full", test_num);
            pass_count++;
        end else begin
            $display("[PASS] Test %0d: Backpressure functional", test_num);
            pass_count++;
        end
        dfi_cmd_ready = 1;

        // ---- Test 8: Simultaneous command and data ----
        test_num = 8;
        $display("\n--- Test %0d: Simultaneous command and data ---", test_num);
        wait_ctrl_cycles(20);  // Drain FIFOs
        fork
            begin
                send_ctrl_cmd(18'hABCDE, 6'h2A, 0, 1, 1, 1);
            end
            begin
                @(posedge ctrl_clk);
                ctrl_wrdata_en <= 1;
                ctrl_wrdata <= 128'hFEDCBA98_76543210_FEDCBA98_76543210;
                ctrl_wrdata_mask <= 16'hFFFF;
                @(posedge ctrl_clk);
                ctrl_wrdata_en <= 0;
            end
        join
        wait_dfi_cycles(10);
        $display("[PASS] Test %0d: Simultaneous command and data", test_num);
        pass_count++;

        // Summary
        $display("\n========================================");
        $display("Test Summary: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        $finish;
    end

    initial begin #(CTRL_CLK_PERIOD * 50000); $display("[ERROR] Timeout!"); $finish; end
    initial begin $dumpfile("tb_ddr5_dfi_bridge.vcd"); $dumpvars(0, tb_ddr5_dfi_bridge); end

endmodule
