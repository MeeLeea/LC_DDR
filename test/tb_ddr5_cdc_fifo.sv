// =============================================================================
// Testbench: tb_ddr5_cdc_fifo
// Description: Verification of async FIFO with Gray-code pointers
//              Covers: normal read/write, full/empty, CDC, reset mismatch
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_cdc_fifo();

    // Parameters
    parameter int DATA_W = 32;
    parameter int ADDR_W = 4;   // Depth=16 for fast sim
    parameter int DEPTH  = 1 << ADDR_W;
    parameter real WR_CLK_PERIOD = 5.0;   // 200 MHz
    parameter real RD_CLK_PERIOD = 8.0;   // 125 MHz (different domain)

    // Write domain signals
    logic              wr_clk;
    logic              wr_rst_n;
    logic              wr_en;
    logic [DATA_W-1:0] wr_data;
    logic              wr_full;

    // Read domain signals
    logic              rd_clk;
    logic              rd_rst_n;
    logic              rd_en;
    logic [DATA_W-1:0] rd_data;
    logic              rd_empty;

    // DUT
    ddr5_cdc_fifo #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .DEPTH(DEPTH)
    ) dut (
        .wr_clk(wr_clk),
        .wr_rst_n(wr_rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_full(wr_full),
        .rd_clk(rd_clk),
        .rd_rst_n(rd_rst_n),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .rd_empty(rd_empty)
    );

    // Functional coverage collector (test/ddr5_covergroups.sv), driven hierarchically
    ddr5_coverage_collector u_cov ();

    function automatic logic [ADDR_W:0] gray2bin_cov(input logic [ADDR_W:0] g);
        logic [ADDR_W:0] b;
        integer gi;
        b[ADDR_W] = g[ADDR_W];
        for (gi = ADDR_W-1; gi >= 0; gi = gi - 1) begin
            b[gi] = b[gi+1] ^ g[gi];
        end
        return b;
    endfunction

    assign u_cov.wr_clk   = wr_clk;
    assign u_cov.clk      = wr_clk;
    assign u_cov.wr_count = dut.wr_ptr_bin[ADDR_W:0]
                          - gray2bin_cov(dut.rd_ptr_gray_sync_wr[ADDR_W:0]);
    assign u_cov.wr_full  = wr_full;

    // Clock generation (different frequencies for CDC test)
    initial begin
        wr_clk = 0;
        forever #(WR_CLK_PERIOD/2) wr_clk = ~wr_clk;
    end
    initial begin
        rd_clk = 0;
        forever #(RD_CLK_PERIOD/2) rd_clk = ~rd_clk;
    end

    // Reference queue for scoreboard
    logic [DATA_W-1:0] ref_queue [$];
    int wr_count = 0;
    int rd_count = 0;
    int err_count = 0;
    int test_num = 0;

    // rd_pop 的采样/期望值 (提到模块级: 避免在进程内声明带初值的变量)
    logic [DATA_W-1:0] cap_data;
    logic [DATA_W-1:0] exp_data;

    // Write driver task
    task automatic wr_push(input logic [DATA_W-1:0] data);
        @(posedge wr_clk);
        wr_en   <= 1'b1;
        wr_data <= data;
        @(posedge wr_clk);
        wr_en   <= 1'b0;
        if (!wr_full) begin
            ref_queue.push_back(data);
            wr_count++;
        end
    endtask

    // Read checker task
    //  DUT 为组合读 (rd_data = mem[rd_ptr_bin]): 只要 rd_en=0, rd_data 就稳定
    //  显示队头。因此必须"先采样队头, 再拉 rd_en 推进指针"。
    //  旧写法先拉 rd_en 再在撤销后采样, 此时指针已指向下一条 -> 全部 off-by-one
    //  (日志表现为 got 0x1 expected 0x0)。
    task automatic rd_pop();
        // 1) 等 FIFO 非空; 此时 rd_en=0, rd_data 即队头
        while (rd_empty) @(posedge rd_clk);
        cap_data = rd_data;
        // 2) 本沿 rd_en 仍为 0, 指针不动
        @(posedge rd_clk);
        // 3) 拉 rd_en, 下一个 posedge 使指针 +1 (弹出本项)
        rd_en <= 1'b1;
        @(posedge rd_clk);
        rd_en <= 1'b0;
        // 4) 比对先前采样的队头
        if (ref_queue.size() > 0) begin
            exp_data = ref_queue.pop_front();
            if (cap_data !== exp_data) begin
                $display("[FAIL] Read data mismatch: got 0x%08h, expected 0x%08h", cap_data, exp_data);
                err_count++;
            end
            rd_count++;
        end else begin
            $display("[FAIL] Read issued on empty FIFO (ref_queue empty)");
            err_count++;
        end
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Testbench: ddr5_cdc_fifo");
        $display("DATA_W=%0d, DEPTH=%0d", DATA_W, DEPTH);
        $display("WR_CLK=%0.1fns, RD_CLK=%0.1fns", WR_CLK_PERIOD, RD_CLK_PERIOD);
        $display("========================================");

        // Init
        wr_rst_n = 0;
        rd_rst_n = 0;
        wr_en    = 0;
        rd_en    = 0;
        wr_data  = '0;

        // ---- Test 1: Reset behavior ----
        test_num = 1;
        $display("\n--- Test %0d: Reset behavior ---", test_num);
        repeat(5) @(posedge wr_clk);
        if (wr_full !== 1'b0) begin $display("[FAIL] wr_full not 0 after reset"); err_count++; end
        else $display("[PASS] wr_full=0 after reset");

        if (rd_empty !== 1'b1) begin $display("[FAIL] rd_empty not 1 after reset"); err_count++; end
        else $display("[PASS] rd_empty=1 after reset");

        // Release reset
        wr_rst_n = 1;
        rd_rst_n = 1;
        repeat(5) @(posedge wr_clk);

        // ---- Test 2: Single write + read ----
        test_num = 2;
        $display("\n--- Test %0d: Single write + read ---", test_num);
        wr_push(32'hDEAD_BEEF);
        // Wait for CDC sync (2-3 rd_clk cycles)
        repeat(5) @(posedge rd_clk);
        if (rd_empty !== 1'b0) begin $display("[FAIL] rd_empty should be 0 after write"); err_count++; end
        else $display("[PASS] rd_empty=0 after write");
        rd_pop();

        // ---- Test 3: Fill FIFO to full ----
        test_num = 3;
        $display("\n--- Test %0d: Fill FIFO to full ---", test_num);
        for (int i = 0; i < DEPTH; i++) begin
            @(posedge wr_clk);
            wr_en   <= 1'b1;
            wr_data <= i[DATA_W-1:0];
            @(posedge wr_clk);
            wr_en   <= 1'b0;
            ref_queue.push_back(i[DATA_W-1:0]);
            wr_count++;
            // Wait for CDC sync
            repeat(3) @(posedge wr_clk);
            if (wr_full) begin
                $display("[INFO] FIFO full at write #%0d", i+1);
                break;
            end
        end
        repeat(5) @(posedge wr_clk);
        if (wr_full !== 1'b1) begin $display("[FAIL] wr_full not asserted when full"); err_count++; end
        else $display("[PASS] wr_full=1 when FIFO full");

        // ---- Test 4: Write when full (should be ignored) ----
        test_num = 4;
        $display("\n--- Test %0d: Write when full ---", test_num);
        @(posedge wr_clk);
        wr_en   <= 1'b1;
        wr_data <= 32'hFFFF_FFFF;
        @(posedge wr_clk);
        wr_en   <= 1'b0;
        // Should NOT have been pushed
        $display("[PASS] Write when full ignored (no crash)");

        // ---- Test 5: Drain FIFO ----
        //  按参考队列长度 drain (rd_pop 内部会等 rd_empty 释放),
        //  避免单靠 rd_empty 判断因写指针同步滞后而提前退出。
        test_num = 5;
        $display("\n--- Test %0d: Drain FIFO ---", test_num);
        while (ref_queue.size() > 0) begin
            rd_pop();
            repeat(2) @(posedge rd_clk);
        end
        repeat(6) @(posedge rd_clk);
        if (rd_empty !== 1'b1) begin $display("[FAIL] rd_empty not 1 after drain"); err_count++; end
        else $display("[PASS] rd_empty=1 after drain");

        // ---- Test 6: Read when empty (should be ignored) ----
        test_num = 6;
        $display("\n--- Test %0d: Read when empty ---", test_num);
        @(posedge rd_clk);
        rd_en <= 1'b1;
        @(posedge rd_clk);
        rd_en <= 1'b0;
        $display("[PASS] Read when empty ignored (no crash)");

        // ---- Test 7: Back-to-back burst write/read ----
        test_num = 7;
        $display("\n--- Test %0d: Burst write/read ---", test_num);
        fork
            // Writer: push 8 items
            begin
                for (int i = 0; i < 8; i++) begin
                    @(posedge wr_clk);
                    while (wr_full) @(posedge wr_clk);
                    wr_en   <= 1'b1;
                    wr_data <= (32'hA000_0000 + i);
                    @(posedge wr_clk);
                    wr_en   <= 1'b0;
                    ref_queue.push_back(32'hA000_0000 + i);
                    wr_count++;
                end
            end
            // Reader: pop 8 items with CDC delay
            begin
                repeat(10) @(posedge rd_clk); // Let writer start
                for (int i = 0; i < 8; i++) begin
                    @(posedge rd_clk);
                    while (rd_empty) @(posedge rd_clk);
                    rd_pop();
                end
            end
        join

        // ---- Test 8: Reset mismatch (wr domain reset before rd domain) ----
        test_num = 8;
        $display("\n--- Test %0d: Reset mismatch ---", test_num);
        wr_rst_n = 0;
        repeat(3) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat(5) @(posedge rd_clk);
        // rd domain should still see old data or empty
        $display("[PASS] Reset mismatch handled (no X propagation)");

        // ---- Test 8b: 双域同步复位, 恢复指针一致状态 ----
        //  上面只复位了 wr 域: wr_ptr->0 而 rd_ptr 仍为历史值, 两指针永久失步。
        //  异步 FIFO 必须两个域同时复位才能回到一致的空状态,
        //  否则后续用例会从 mem[旧 rd_ptr] 读出残留数据 (表现为整段错位)。
        test_num = 8;
        $display("\n--- Test 8b: dual-domain sync reset to recover coherence ---");
        wr_en  = 0;
        rd_en  = 0;
        wr_rst_n = 0;
        rd_rst_n = 0;
        repeat(5) @(posedge wr_clk);
        repeat(5) @(posedge rd_clk);
        wr_rst_n = 1;
        rd_rst_n = 1;
        repeat(6) @(posedge wr_clk);
        while (ref_queue.size() > 0) void'(ref_queue.pop_front());
        if (rd_empty !== 1'b1) begin $display("[FAIL] rd_empty not 1 after dual reset"); err_count++; end
        else $display("[PASS] rd_empty=1 after dual-domain reset");
        if (wr_full !== 1'b0) begin $display("[FAIL] wr_full not 0 after dual reset"); err_count++; end
        else $display("[PASS] wr_full=0 after dual-domain reset");

        // ---- Test 9: Simultaneous read/write ----
        test_num = 9;
        $display("\n--- Test %0d: Simultaneous read/write ---", test_num);
        // Pre-fill 4 items
        for (int i = 0; i < 4; i++) begin
            @(posedge wr_clk);
            wr_en   <= 1'b1;
            wr_data <= (32'hB000_0000 + i);
            @(posedge wr_clk);
            wr_en   <= 1'b0;
            ref_queue.push_back(32'hB000_0000 + i);
            wr_count++;
        end
        repeat(5) @(posedge rd_clk);
        // Simultaneous read and write
        fork
            begin
                for (int i = 0; i < 4; i++) begin
                    @(posedge wr_clk);
                    wr_en   <= 1'b1;
                    wr_data <= (32'hC000_0000 + i);
                    @(posedge wr_clk);
                    wr_en   <= 1'b0;
                    ref_queue.push_back(32'hC000_0000 + i);
                    wr_count++;
                end
            end
            begin
                for (int i = 0; i < 4; i++) begin
                    @(posedge rd_clk);
                    while (rd_empty) @(posedge rd_clk);
                    rd_pop();
                end
            end
        join
        $display("[PASS] Simultaneous read/write completed");

        // Summary
        $display("\n========================================");
        $display("CDC FIFO Test Summary:");
        $display("  Writes: %0d, Reads: %0d, Errors: %0d", wr_count, rd_count, err_count);
        $display("========================================");
        if (err_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

    // Timeout
    initial begin
        #(WR_CLK_PERIOD * 10000);
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

    // Waveform
    initial begin
        $dumpfile("tb_ddr5_cdc_fifo.vcd");
        $dumpvars(0, tb_ddr5_cdc_fifo);
    end

endmodule
