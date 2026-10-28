// =============================================================================
// Testbench: tb_ddr5_cmd_arbiter
// Description: Verification of 4-port WRR + Strict Priority arbiter
//              Port 0 = CPU (Strict High Priority)
//              Port 1 = DMA (WRR weight=4)
//              Port 2 = Accel (WRR weight=8)
//              Port 3 = Debug (WRR weight=1)
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_cmd_arbiter();

    // Parameters
    parameter int NUM_PORTS = 4;
    parameter int ID_W = 8;
    parameter int ADDR_W = 34;
    parameter int DATA_W = 256;
    parameter real CLK_PERIOD = 5.0;

    // Signals
    logic clk;
    logic rst_n;
    
    logic [NUM_PORTS-1:0] cmd_valid;
    logic [NUM_PORTS-1:0] cmd_ready;
    logic [NUM_PORTS-1:0] cmd_is_write;
    logic [ID_W-1:0] cmd_id [NUM_PORTS];
    logic [ADDR_W-1:0] cmd_addr [NUM_PORTS];
    logic [7:0] cmd_len [NUM_PORTS];
    logic [3:0] cmd_qos [NUM_PORTS];
    
    logic out_valid;
    logic out_ready;
    logic out_is_write;
    logic [ID_W-1:0] out_id;
    logic [ADDR_W-1:0] out_addr;
    logic [7:0] out_len;
    logic [1:0] out_port_id;
    logic [3:0] out_qos;

    // DUT
    ddr5_cmd_arbiter #(
        .NUM_PORTS(NUM_PORTS),
        .ID_W(ID_W),
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_is_write(cmd_is_write),
        .cmd_id(cmd_id),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .cmd_qos(cmd_qos),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_is_write(out_is_write),
        .out_id(out_id),
        .out_addr(out_addr),
        .out_len(out_len),
        .out_port_id(out_port_id),
        .out_qos(out_qos)
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
    int grant_count [NUM_PORTS];

    // Initialize
    initial begin
        for (int i = 0; i < NUM_PORTS; i++) begin
            cmd_valid[i] = 0;
            cmd_is_write[i] = 0;
            cmd_id[i] = 0;
            cmd_addr[i] = 0;
            cmd_len[i] = 0;
            cmd_qos[i] = 0;
            grant_count[i] = 0;
        end
        out_ready = 1;
    end

    // Monitor grants
    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            grant_count[out_port_id]++;
        end
    end

    // Test task
    task automatic check_arbitration(string test_name, logic [1:0] expected_port);
        test_num++;
        @(posedge clk);
        #1;
        if (out_valid && out_port_id === expected_port) begin
            $display("[PASS] Test %0d: %s - Port %0d granted", 
                     test_num, test_name, out_port_id);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s - Expected port %0d, got port %0d (valid=%0b)", 
                     test_num, test_name, expected_port, out_port_id, out_valid);
            fail_count++;
        end
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Testbench: ddr5_cmd_arbiter");
        $display("========================================");

        // Reset
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // ==== Test 1: Single port request ====
        $display("\n--- Test 1: Single port request ---");
        cmd_valid[2] = 1;
        cmd_addr[2] = 34'h1000;
        check_arbitration("Single port 2 request", 2'd2);
        cmd_valid[2] = 0;

        // ==== Test 2: Port 0 strict priority ====
        $display("\n--- Test 2: Port 0 strict priority ---");
        cmd_valid[0] = 1;
        cmd_valid[1] = 1;
        cmd_valid[2] = 1;
        cmd_valid[3] = 1;
        check_arbitration("Port 0 has highest priority", 2'd0);
        cmd_valid[0] = 0;
        cmd_valid[1] = 0;
        cmd_valid[2] = 0;
        cmd_valid[3] = 0;

        // ==== Test 3: WRR among ports 1-3 ====
        $display("\n--- Test 3: WRR among ports 1-3 ---");
        cmd_valid[1] = 1;
        cmd_valid[2] = 1;
        cmd_valid[3] = 1;
        
        // WRR starts from port 1 (rr_ptr=1 after reset)
        // Port 1 has weight=4, should win first
        check_arbitration("WRR: Port 1 (weight=4) wins first", 2'd1);
        
        // Let it run for several cycles to see WRR rotation
        repeat(20) @(posedge clk);
        
        $display("[INFO] Grant distribution over 20 cycles:");
        for (int i = 0; i < NUM_PORTS; i++) begin
            $display("  Port %0d: %0d grants", i, grant_count[i]);
        end
        
        cmd_valid[1] = 0;
        cmd_valid[2] = 0;
        cmd_valid[3] = 0;

        // ==== Test 4: Port 0 preemption ====
        $display("\n--- Test 4: Port 0 preemption ---");
        cmd_valid[2] = 1;
        repeat(3) @(posedge clk);
        cmd_valid[0] = 1;
        check_arbitration("Port 0 preempts port 2", 2'd0);
        cmd_valid[0] = 0;
        cmd_valid[2] = 0;

        // ==== Test 5: Backpressure (out_ready=0) ====
        $display("\n--- Test 5: Backpressure ---");
        cmd_valid[1] = 1;
        out_ready = 0;
        repeat(5) @(posedge clk);
        test_num++;
        if (cmd_ready[1] === 1'b0) begin
            $display("[PASS] Test %0d: Backpressure - cmd_ready=0 when out_ready=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Backpressure - cmd_ready should be 0", test_num);
            fail_count++;
        end
        out_ready = 1;
        cmd_valid[1] = 0;

        // ==== Test 6: QoS field passthrough ====
        $display("\n--- Test 6: QoS passthrough ---");
        cmd_valid[1] = 1;
        cmd_qos[1] = 4'hA;
        @(posedge clk);
        #1;
        test_num++;
        if (out_qos === 4'hA) begin
            $display("[PASS] Test %0d: QoS field correctly passed through", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: QoS field mismatch (expected 0xA, got 0x%01h)", test_num, out_qos);
            fail_count++;
        end
        cmd_valid[1] = 0;

        // ==== Test 7: All ports idle ====
        $display("\n--- Test 7: All ports idle ---");
        repeat(5) @(posedge clk);
        test_num++;
        if (out_valid === 1'b0) begin
            $display("[PASS] Test %0d: No grant when all ports idle", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: out_valid should be 0", test_num);
            fail_count++;
        end

        // Summary
        $display("\n========================================");
        $display("Final Grant Distribution:");
        for (int i = 0; i < NUM_PORTS; i++) begin
            $display("  Port %0d: %0d grants", i, grant_count[i]);
        end
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
        $dumpfile("tb_ddr5_cmd_arbiter.vcd");
        $dumpvars(0, tb_ddr5_cmd_arbiter);
    end

endmodule
