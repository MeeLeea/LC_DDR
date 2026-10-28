// =============================================================================
// Testbench: tb_ddr5_axi4_rd_slave
// Description: Verification of AXI4 Read Channel Slave (AR/R)
//              Tests read transactions with various burst lengths
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_axi4_rd_slave();

    // Parameters
    parameter int ID_W = 8;
    parameter int ADDR_W = 34;
    parameter int DATA_W = 256;
    parameter real CLK_PERIOD = 5.0;

    // Signals
    logic clk;
    logic rst_n;
    
    // AR channel
    logic [ID_W-1:0] arid;
    logic [ADDR_W-1:0] araddr;
    logic [7:0] arlen;
    logic [2:0] arsize;
    logic [1:0] arburst;
    logic [3:0] arcache;
    logic [2:0] arprot;
    logic [3:0] arqos;
    logic arlock = 1'b0;      // B-02: default to normal (non-exclusive) access
    logic arvalid;
    logic arready;
    
    // R channel
    logic [ID_W-1:0] rid;
    logic [DATA_W-1:0] rdata;
    logic [1:0] rresp;
    logic rlast;
    logic rvalid;
    logic rready;
    
    // Command output
    logic cmd_valid;
    logic cmd_ready;
    logic [ID_W-1:0] cmd_id;
    logic [ADDR_W-1:0] cmd_addr;
    logic [7:0] cmd_len;
    logic [3:0] cmd_qos;
    
    // Read data input
    logic [DATA_W-1:0] rd_data;
    logic rd_data_valid;
    logic rd_data_ready;

    // DUT
    ddr5_axi4_rd_slave #(
        .ID_W(ID_W),
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .arid(arid),
        .araddr(araddr),
        .arlen(arlen),
        .arsize(arsize),
        .arburst(arburst),
        .arcache(arcache),
        .arprot(arprot),
        .arqos(arqos),
        .arlock(arlock),
        .arvalid(arvalid),
        .arready(arready),
        .rid(rid),
        .rdata(rdata),
        .rresp(rresp),
        .rlast(rlast),
        .rvalid(rvalid),
        .rready(rready),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_id(cmd_id),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .cmd_qos(cmd_qos),
        .rd_data(rd_data),
        .rd_data_valid(rd_data_valid),
        .rd_data_ready(rd_data_ready)
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
    int rdata_count = 0;
    logic rlast_seen = 0;

    // Monitor R channel
    always @(posedge clk) begin
        if (rvalid && rready) begin
            rdata_count++;
            if (rlast) rlast_seen = 1;
        end
    end

    // Initialize
    initial begin
        arid = 0;
        araddr = 0;
        arlen = 0;
        arsize = 5;
        arburst = 2'b01;
        arcache = 0;
        arprot = 0;
        arqos = 0;
        arvalid = 0;
        rready = 1;
        cmd_ready = 1;
        rd_data = 0;
        rd_data_valid = 0;
    end

    // Read transaction task
    task automatic read_transaction(
        input logic [ID_W-1:0] id,
        input logic [ADDR_W-1:0] addr,
        input logic [7:0] len,
        input logic [3:0] qos
    );
        // Send AR
        @(posedge clk);
        arid = id;
        araddr = addr;
        arlen = len;
        arqos = qos;
        arvalid = 1;
        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid = 0;
        
        // Wait for command output
        @(posedge clk);
        while (!cmd_valid) @(posedge clk);
        @(posedge clk);
        
        // Provide read data
        for (int i = 0; i <= len; i++) begin
            @(posedge clk);
            rd_data = {DATA_W{i[7:0]}};
            rd_data_valid = 1;
            @(posedge clk);
            while (!rd_data_ready) @(posedge clk);
            // 握手后必须拉低 rd_data_valid: 否则下一轮循环开头的 @(posedge clk)
            // 会让 DUT 再握手一次, beat_cnt 提前到达 len 而回到 IDLE,
            // 此时 rd_data_ready 恒为 0, TB 卡在上面的 while 循环 (仿真超时)。
            rd_data_valid = 0;
        end
        rd_data_valid = 0;
        
        // Wait for transaction to complete
        repeat(5) @(posedge clk);
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Testbench: ddr5_axi4_rd_slave");
        $display("DATA_W=%0d", DATA_W);
        $display("========================================");

        // Reset
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // ==== Test 1: Single beat read (len=0) ====
        $display("\n--- Test 1: Single beat read ---");
        test_num = 1;
        rdata_count = 0;
        rlast_seen = 0;
        read_transaction(8'h01, 34'h1000, 8'h00, 4'h0);
        if (rdata_count == 1 && rlast_seen) begin
            $display("[PASS] Test %0d: Single beat read (1 data beat, rlast seen)", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Expected 1 beat + rlast, got %0d beats, rlast=%0b", 
                     test_num, rdata_count, rlast_seen);
            fail_count++;
        end

        // ==== Test 2: Burst read (len=3, 4 beats) ====
        $display("\n--- Test 2: Burst read (4 beats) ---");
        test_num = 2;
        rdata_count = 0;
        rlast_seen = 0;
        read_transaction(8'h02, 34'h2000, 8'h03, 4'h5);
        if (rdata_count == 4 && rlast_seen) begin
            $display("[PASS] Test %0d: Burst read (4 data beats, rlast seen)", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Expected 4 beats + rlast, got %0d beats, rlast=%0b", 
                     test_num, rdata_count, rlast_seen);
            fail_count++;
        end

        // ==== Test 3: Long burst (len=15, 16 beats) ====
        $display("\n--- Test 3: Long burst (16 beats) ---");
        test_num = 3;
        rdata_count = 0;
        rlast_seen = 0;
        read_transaction(8'h03, 34'h3000, 8'h0F, 4'hA);
        if (rdata_count == 16 && rlast_seen) begin
            $display("[PASS] Test %0d: Long burst (16 data beats, rlast seen)", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Expected 16 beats + rlast, got %0d beats, rlast=%0b", 
                     test_num, rdata_count, rlast_seen);
            fail_count++;
        end

        // ==== Test 4: Command output verification ====
        $display("\n--- Test 4: Command output ---");
        test_num = 4;
        @(posedge clk);
        arid = 8'h10;
        araddr = 34'hABCD_1234;
        arlen = 8'h07;
        arqos = 4'hC;
        arvalid = 1;
        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid = 0;
        
        @(posedge clk);
        while (!cmd_valid) @(posedge clk);
        
        if (cmd_id === 8'h10 && cmd_addr === 34'hABCD_1234 && 
            cmd_len === 8'h07 && cmd_qos === 4'hC) begin
            $display("[PASS] Test %0d: Command output correct", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Command output mismatch", test_num);
            $display("  Expected: id=0x10 addr=0xABCD1234 len=7 qos=C");
            $display("  Got: id=0x%02h addr=0x%09h len=%0d qos=0x%01h", 
                     cmd_id, cmd_addr, cmd_len, cmd_qos);
            fail_count++;
        end
        
        // Complete transaction
        //  每拍握手后必须拉低 rd_data_valid: 否则下一轮开头的 @(posedge clk)
        //  会让 DUT 再握手一次, beat_cnt 提前到达 len 而回 IDLE,
        //  此时 rd_data_ready 恒 0, 本循环永久挂死。
        for (int i = 0; i <= 7; i++) begin
            @(posedge clk);
            rd_data = i;
            rd_data_valid = 1;
            @(posedge clk);
            while (!rd_data_ready) @(posedge clk);
            rd_data_valid = 0;
        end
        rd_data_valid = 0;
        repeat(5) @(posedge clk);

        // ==== Test 5: R response ID match ====
        $display("\n--- Test 5: R response ID ---");
        test_num = 5;
        @(posedge clk);
        arid = 8'h55;
        arvalid = 1;
        araddr = 34'h6000;
        arlen = 0;
        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid = 0;
        
        // Wait for command
        @(posedge clk);
        while (!cmd_valid) @(posedge clk);
        
        // Provide data
        @(posedge clk);
        rd_data = 34'hDEADBEEF;
        rd_data_valid = 1;
        @(posedge clk);
        while (!rd_data_ready) @(posedge clk);
        rd_data_valid = 0;
        
        // Check R response
        repeat(2) @(posedge clk);
        if (rid === 8'h55) begin
            $display("[PASS] Test %0d: R response ID matches AR ID", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: R ID mismatch (expected 0x55, got 0x%02h)", test_num, rid);
            fail_count++;
        end

        // ==== Test 6: Backpressure on rready ====
        $display("\n--- Test 6: Backpressure on rready ---");
        test_num = 6;
        rready = 0;
        @(posedge clk);
        arid = 8'h77;
        arvalid = 1;
        araddr = 34'h7000;
        arlen = 0;
        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid = 0;
        
        // Wait for command
        @(posedge clk);
        while (!cmd_valid) @(posedge clk);
        
        // Provide data
        //  反压场景: rready=0 时 rd_data_ready 恒为 0 (rd_data_ready = rready),
        //  因此绝不能用 `while(!rd_data_ready)` 等握手 (会永久挂死)。
        //  本用例要验的是: 数据已供上时 rvalid 能在 rready=0 下保持。
        @(posedge clk);
        rd_data = 0;
        rd_data_valid = 1;
        @(posedge clk);
        #1;

        // Check that rvalid is held
        repeat(3) @(posedge clk);
        #1;
        if (rvalid && !rready) begin
            $display("[PASS] Test %0d: rvalid held when rready=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Backpressure not working (rvalid=%0b rready=%0b)", test_num, rvalid, rready);
            fail_count++;
        end

        // 释放反压, 让本笔读真正完成 (回到 IDLE), 保证后续用例从一致状态开始
        rready = 1;
        @(posedge clk);
        while (!rd_data_ready && rd_data_valid) @(posedge clk);
        rd_data_valid = 0;
        repeat(3) @(posedge clk);

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
        #(CLK_PERIOD * 10000);
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

    // Waveform
    initial begin
        $dumpfile("tb_ddr5_axi4_rd_slave.vcd");
        $dumpvars(0, tb_ddr5_axi4_rd_slave);
    end

endmodule
