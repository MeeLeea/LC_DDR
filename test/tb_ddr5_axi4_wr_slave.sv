// =============================================================================
// Testbench: tb_ddr5_axi4_wr_slave
// Description: Verification of AXI4 Write Channel Slave (AW/W/B)
//              Tests write transactions with various burst lengths
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_axi4_wr_slave();

    // Parameters
    parameter int ID_W = 8;
    parameter int ADDR_W = 34;
    parameter int DATA_W = 256;
    parameter int STRB_W = DATA_W / 8;
    parameter real CLK_PERIOD = 5.0;

    // Signals
    logic clk;
    logic rst_n;
    
    // AW channel
    logic [ID_W-1:0] awid;
    logic [ADDR_W-1:0] awaddr;
    logic [7:0] awlen;
    logic [2:0] awsize;
    logic [1:0] awburst;
    logic [3:0] awcache;
    logic [2:0] awprot;
    logic [3:0] awqos;
    logic awlock = 1'b0;      // B-02: default to normal (non-exclusive) access
    logic ex_aw_ok = 1'b0;    // B-02: exclusive grant from monitor
    logic awvalid;
    logic awready;
    
    // W channel
    logic [DATA_W-1:0] wdata;
    logic [STRB_W-1:0] wstrb;
    logic wlast;
    logic wvalid;
    logic wready;
    
    // B channel
    logic [ID_W-1:0] bid;
    logic [1:0] bresp;
    logic bvalid;
    logic bready;
    
    // Command output
    logic cmd_valid;
    logic cmd_ready;
    logic [ID_W-1:0] cmd_id;
    logic [ADDR_W-1:0] cmd_addr;
    logic [7:0] cmd_len;
    logic [3:0] cmd_qos;
    
    // Write data output
    logic wr_data_valid;
    logic wr_data_ready;
    logic [DATA_W-1:0] wr_data;
    logic [STRB_W-1:0] wr_strb;
    logic wr_last;

    // DUT
    ddr5_axi4_wr_slave #(
        .ID_W(ID_W),
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .STRB_W(STRB_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .awid(awid),
        .awaddr(awaddr),
        .awlen(awlen),
        .awsize(awsize),
        .awburst(awburst),
        .awcache(awcache),
        .awprot(awprot),
        .awqos(awqos),
        .awlock(awlock),
        .awvalid(awvalid),
        .awready(awready),
        .ex_aw_ok(ex_aw_ok),
        .wdata(wdata),
        .wstrb(wstrb),
        .wlast(wlast),
        .wvalid(wvalid),
        .wready(wready),
        .bid(bid),
        .bresp(bresp),
        .bvalid(bvalid),
        .bready(bready),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_id(cmd_id),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .cmd_qos(cmd_qos),
        .wr_data_valid(wr_data_valid),
        .wr_data_ready(wr_data_ready),
        .wr_data(wr_data),
        .wr_strb(wr_strb),
        .wr_last(wr_last)
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
    int wr_data_count = 0;

    // Initialize
    initial begin
        awid = 0;
        awaddr = 0;
        awlen = 0;
        awsize = 5;  // 32 bytes
        awburst = 2'b01;  // INCR
        awcache = 0;
        awprot = 0;
        awqos = 0;
        awvalid = 0;
        wdata = 0;
        wstrb = {STRB_W{1'b1}};
        wlast = 0;
        wvalid = 0;
        bready = 1;
        cmd_ready = 1;
        wr_data_ready = 1;
    end

    // Monitor write data
    always @(posedge clk) begin
        if (wr_data_valid && wr_data_ready) begin
            wr_data_count++;
        end
    end

    // Write transaction task
    task automatic write_transaction(
        input logic [ID_W-1:0] id,
        input logic [ADDR_W-1:0] addr,
        input logic [7:0] len,
        input logic [3:0] qos
    );
        // Send AW
        @(posedge clk);
        awid = id;
        awaddr = addr;
        awlen = len;
        awqos = qos;
        awvalid = 1;
        @(posedge clk);
        while (!awready) @(posedge clk);
        awvalid = 0;
        
        // Send W data
        for (int i = 0; i <= len; i++) begin
            @(posedge clk);
            wdata = {DATA_W{i[7:0]}};
            wstrb = {STRB_W{1'b1}};
            wlast = (i == len);
            wvalid = 1;
            @(posedge clk);
            while (!wready) @(posedge clk);
            // 握手完成后必须拉低 wvalid: 否则下一轮循环开头的 @(posedge clk)
            // 会让 DUT 再采样一次 wvalid=1, 造成重复握手
            // (旧版 len=3 计到 7 拍、len=15 计到 31 拍, 即 2n-1)
            wvalid = 0;
        end
        wvalid = 0;
        wlast = 0;
        
        // Wait for B response
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        @(posedge clk);
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Testbench: ddr5_axi4_wr_slave");
        $display("DATA_W=%0d, STRB_W=%0d", DATA_W, STRB_W);
        $display("========================================");

        // Reset
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // ==== Test 1: Single beat write (len=0) ====
        $display("\n--- Test 1: Single beat write ---");
        test_num = 1;
        wr_data_count = 0;
        write_transaction(8'h01, 34'h1000, 8'h00, 4'h0);
        if (wr_data_count == 1) begin
            $display("[PASS] Test %0d: Single beat write (1 data beat)", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Expected 1 data beat, got %0d", test_num, wr_data_count);
            fail_count++;
        end

        // ==== Test 2: Burst write (len=3, 4 beats) ====
        $display("\n--- Test 2: Burst write (4 beats) ---");
        test_num = 2;
        wr_data_count = 0;
        write_transaction(8'h02, 34'h2000, 8'h03, 4'h5);
        if (wr_data_count == 4) begin
            $display("[PASS] Test %0d: Burst write (4 data beats)", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Expected 4 data beats, got %0d", test_num, wr_data_count);
            fail_count++;
        end

        // ==== Test 3: Long burst (len=15, 16 beats) ====
        $display("\n--- Test 3: Long burst (16 beats) ---");
        test_num = 3;
        wr_data_count = 0;
        write_transaction(8'h03, 34'h3000, 8'h0F, 4'hA);
        if (wr_data_count == 16) begin
            $display("[PASS] Test %0d: Long burst (16 data beats)", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Expected 16 data beats, got %0d", test_num, wr_data_count);
            fail_count++;
        end

        // ==== Test 4: Command output verification ====
        $display("\n--- Test 4: Command output ---");
        test_num = 4;
        @(posedge clk);
        awid = 8'h10;
        awaddr = 34'hABCD_1234;
        awlen = 8'h07;
        awqos = 4'hC;
        awvalid = 1;
        @(posedge clk);
        while (!awready) @(posedge clk);
        awvalid = 0;
        
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
        for (int i = 0; i <= 7; i++) begin
            @(posedge clk);
            wdata = i;
            wstrb = {STRB_W{1'b1}};
            wlast = (i == 7);
            wvalid = 1;
            @(posedge clk);
            while (!wready) @(posedge clk);
        end
        wvalid = 0;
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        @(posedge clk);

        // ==== Test 5: Backpressure on cmd_ready ====
        $display("\n--- Test 5: Backpressure on cmd_ready ---");
        test_num = 5;
        cmd_ready = 0;
        @(posedge clk);
        awvalid = 1;
        awaddr = 34'h5000;
        awlen = 0;
        @(posedge clk);
        while (!awready) @(posedge clk);
        awvalid = 0;
        
        repeat(5) @(posedge clk);
        if (cmd_valid && !cmd_ready) begin
            $display("[PASS] Test %0d: cmd_valid held when cmd_ready=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Backpressure not working", test_num);
            fail_count++;
        end
        
        cmd_ready = 1;
        @(posedge clk);
        
        // Complete transaction
        @(posedge clk);
        wdata = 0;
        wstrb = {STRB_W{1'b1}};
        wlast = 1;
        wvalid = 1;
        @(posedge clk);
        wvalid = 0;
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        @(posedge clk);

        // ==== Test 6: B response ID match ====
        $display("\n--- Test 6: B response ID ---");
        test_num = 6;
        @(posedge clk);
        awid = 8'h55;
        awvalid = 1;
        awaddr = 34'h6000;
        awlen = 0;
        @(posedge clk);
        while (!awready) @(posedge clk);
        awvalid = 0;
        
        // Send data
        @(posedge clk);
        wdata = 0;
        wstrb = {STRB_W{1'b1}};
        wlast = 1;
        wvalid = 1;
        @(posedge clk);
        wvalid = 0;
        
        // Check B response
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        if (bid === 8'h55) begin
            $display("[PASS] Test %0d: B response ID matches AW ID", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: B ID mismatch (expected 0x55, got 0x%02h)", test_num, bid);
            fail_count++;
        end
        @(posedge clk);

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
        $dumpfile("tb_ddr5_axi4_wr_slave.vcd");
        $dumpvars(0, tb_ddr5_axi4_wr_slave);
    end

endmodule
