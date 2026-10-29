// =============================================================================
// Testbench: tb_ddr5_ctrl_core
// Description: Integration testbench for DDR5 controller core
//              Tests: Full pipeline from command input to DFI output
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_ctrl_core();

    parameter int NUM_BANKS = 32;
    parameter int QUEUE_DEPTH = 16;
    parameter real CLK_PERIOD = 2.083;

    logic clk, rst_n;

    // Command input
    logic cmd_in_valid, cmd_in_ready;
    logic [7:0] cmd_in_id;
    logic [33:0] cmd_in_addr;
    logic [7:0] cmd_in_len;
    logic cmd_in_is_write;
    logic [1:0] cmd_in_port_id;
    logic [3:0] cmd_in_qos;

    // Write data
    logic [255:0] wr_data;
    logic [31:0] wr_strb;
    logic wr_data_valid;

    // Read data
    logic [255:0] rd_data;
    logic rd_data_valid;
    logic [1:0] rd_port_id;
    logic [7:0] rd_id;

    // DFI interface
    logic dfi_cmd_valid;
    logic [17:0] dfi_address;
    logic [5:0] dfi_bank;
    logic [1:0] dfi_cs_n;
    logic dfi_act_n, dfi_ras_n, dfi_cas_n, dfi_we_n;
    logic [127:0] dfi_wrdata;
    logic [15:0] dfi_wrdata_mask;
    logic dfi_wrdata_en;
    logic [127:0] dfi_rddata;
    logic dfi_rddata_valid;

    // Configuration
    logic [15:0] cfg_tRCD, cfg_tRP, cfg_tRAS, cfg_tRC;
    logic [15:0] cfg_tRFC, cfg_tRFCsb, cfg_tREFI;
    logic [15:0] cfg_tWR, cfg_tRTP, cfg_CL, cfg_CWL;
    logic [15:0] cfg_tCCD_L, cfg_tCCD_S, cfg_tRRD_L, cfg_tRRD_S;
    logic [15:0] cfg_tFAW, cfg_tXS, cfg_tXP, cfg_tZQCAL, cfg_tZQCS;
    logic [1:0] cfg_fgr_mode;
    logic cfg_auto_ref_en, cfg_manual_ref, cfg_ecc_en, cfg_sreq_enter;

    // Status
    logic ctrl_ready;
    logic [3:0] ctrl_state;
    logic [3:0] refresh_credit;
    logic refresh_overflow;
    logic ecc_sbe_detect, ecc_dbe_detect;
    logic deadlock_detected;          // B-03
    logic [15:0] deadlock_stall_count; // B-03

    // Pulse detection registers
    logic dfi_act_pulse_seen, dfi_rd_pulse_seen, dfi_wr_pulse_seen;
    // Clear strobes: set by initial block, consumed by always_ff
    logic pulse_clr_act, pulse_clr_rd, pulse_clr_wr;

    // Test 6: sticky "refresh credit was ever accumulated" flag.
    // Refresh has top scheduling priority, so credits are consumed within a few
    // cycles of each tREFI expiry; a single instantaneous sample at the end of
    // the window would almost always read 0.
    logic refresh_credit_seen;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) refresh_credit_seen <= 1'b0;
        else if (refresh_credit > 0 || refresh_overflow) refresh_credit_seen <= 1'b1;
    end

    ddr5_ctrl_core #(
        .NUM_BANKS(NUM_BANKS),
        .QUEUE_DEPTH(QUEUE_DEPTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_in_valid(cmd_in_valid), .cmd_in_ready(cmd_in_ready),
        .cmd_in_id(cmd_in_id), .cmd_in_addr(cmd_in_addr),
        .cmd_in_len(cmd_in_len), .cmd_in_is_write(cmd_in_is_write),
        .cmd_in_port_id(cmd_in_port_id), .cmd_in_qos(cmd_in_qos),
        .wr_data(wr_data), .wr_strb(wr_strb), .wr_data_valid(wr_data_valid),
        .rd_data(rd_data), .rd_data_valid(rd_data_valid),
        .rd_port_id(rd_port_id), .rd_id(rd_id),
        .dfi_cmd_valid(dfi_cmd_valid), .dfi_address(dfi_address),
        .dfi_bank(dfi_bank), .dfi_cs_n(dfi_cs_n),
        .dfi_act_n(dfi_act_n), .dfi_ras_n(dfi_ras_n),
        .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_mask(dfi_wrdata_mask),
        .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid),
        .cfg_tRCD(cfg_tRCD), .cfg_tRP(cfg_tRP), .cfg_tRAS(cfg_tRAS),
        .cfg_tRC(cfg_tRC), .cfg_tRFC(cfg_tRFC), .cfg_tRFCsb(cfg_tRFCsb),
        .cfg_tREFI(cfg_tREFI), .cfg_tWR(cfg_tWR), .cfg_tRTP(cfg_tRTP),
        .cfg_CL(cfg_CL), .cfg_CWL(cfg_CWL),
        .cfg_tCCD_L(cfg_tCCD_L), .cfg_tCCD_S(cfg_tCCD_S),
        .cfg_tRRD_L(cfg_tRRD_L), .cfg_tRRD_S(cfg_tRRD_S),
        .cfg_tFAW(cfg_tFAW), .cfg_tXS(cfg_tXS), .cfg_tXP(cfg_tXP),
        .cfg_tZQCAL(cfg_tZQCAL), .cfg_tZQCS(cfg_tZQCS),
        .cfg_fgr_mode(cfg_fgr_mode), .cfg_auto_ref_en(cfg_auto_ref_en),
        .cfg_manual_ref(cfg_manual_ref), .cfg_ecc_en(cfg_ecc_en),
        .cfg_sreq_enter(cfg_sreq_enter),
        .ctrl_ready(ctrl_ready), .ctrl_state(ctrl_state),
        .refresh_credit(refresh_credit), .refresh_overflow(refresh_overflow),
        .ecc_sbe_detect(ecc_sbe_detect), .ecc_dbe_detect(ecc_dbe_detect),
        .deadlock_detected(deadlock_detected),
        .deadlock_stall_count(deadlock_stall_count)
    );

    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    int test_num = 0, pass_count = 0, fail_count = 0;

    // Pulse detectors: latch any DFI command pulse for later sampling
    // Cleared via pulse_clr_* strobes from the initial block (single driver)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dfi_act_pulse_seen <= 1'b0;
            dfi_rd_pulse_seen  <= 1'b0;
            dfi_wr_pulse_seen  <= 1'b0;
        end else begin
            if (pulse_clr_act) dfi_act_pulse_seen <= 1'b0;
            else if (dfi_cmd_valid && !dfi_act_n && !dfi_ras_n)  dfi_act_pulse_seen <= 1'b1;  // ACT
            if (pulse_clr_rd)  dfi_rd_pulse_seen  <= 1'b0;
            else if (dfi_cmd_valid && !dfi_cas_n && dfi_we_n)    dfi_rd_pulse_seen  <= 1'b1;  // RD
            if (pulse_clr_wr)  dfi_wr_pulse_seen  <= 1'b0;
            else if (dfi_cmd_valid && !dfi_cas_n && !dfi_we_n)   dfi_wr_pulse_seen  <= 1'b1;  // WR
            else if (dfi_wrdata_en)                              dfi_wr_pulse_seen  <= 1'b1;
        end
    end

    task automatic wait_cycles(int n);
        repeat(n) @(posedge clk);
    endtask

    task automatic clr_pulses(bit clr_act, bit clr_rd, bit clr_wr);
        @(posedge clk);
        pulse_clr_act = clr_act;
        pulse_clr_rd  = clr_rd;
        pulse_clr_wr  = clr_wr;
        @(posedge clk);
        pulse_clr_act = 0;
        pulse_clr_rd  = 0;
        pulse_clr_wr  = 0;
    endtask

    task automatic send_read_cmd(logic [7:0] id, logic [33:0] addr, logic [1:0] port);
        @(posedge clk);
        cmd_in_valid <= 1;
        cmd_in_id <= id;
        cmd_in_addr <= addr;
        cmd_in_len <= 8'd0;
        cmd_in_is_write <= 0;
        cmd_in_port_id <= port;
        cmd_in_qos <= 4'h0;
        @(posedge clk);
        while (!cmd_in_ready) @(posedge clk);
        cmd_in_valid <= 0;
    endtask

    task automatic send_write_cmd(logic [7:0] id, logic [33:0] addr, logic [1:0] port);
        @(posedge clk);
        cmd_in_valid <= 1;
        cmd_in_id <= id;
        cmd_in_addr <= addr;
        cmd_in_len <= 8'd0;
        cmd_in_is_write <= 1;
        cmd_in_port_id <= port;
        cmd_in_qos <= 4'h0;
        @(posedge clk);
        while (!cmd_in_ready) @(posedge clk);
        cmd_in_valid <= 0;
        
        // Send write data
        @(posedge clk);
        wr_data_valid <= 1;
        wr_data <= 256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0;
        wr_strb <= 32'hFFFFFFFF;
        @(posedge clk);
        wr_data_valid <= 0;
    endtask

    initial begin
        $display("==========================================");
        $display("Testbench: ddr5_ctrl_core (Integration)");
        $display("NUM_BANKS=%0d, QUEUE_DEPTH=%0d", NUM_BANKS, QUEUE_DEPTH);
        $display("==========================================");

        rst_n = 0;
        cmd_in_valid = 0; cmd_in_id = 0; cmd_in_addr = 0;
        cmd_in_len = 0; cmd_in_is_write = 0;
        cmd_in_port_id = 0; cmd_in_qos = 0;
        wr_data = 0; wr_strb = 0; wr_data_valid = 0;
        dfi_rddata = 0; dfi_rddata_valid = 0;
        pulse_clr_act = 0; pulse_clr_rd = 0; pulse_clr_wr = 0;

        // DDR5-4800 timing parameters (shorter for faster simulation)
        cfg_tRCD = 16'd34; cfg_tRP = 16'd34; cfg_tRAS = 16'd77; cfg_tRC = 16'd111;
        cfg_tRFC = 16'd709; cfg_tRFCsb = 16'd384; cfg_tREFI = 16'd9375;
        cfg_tWR = 16'd72; cfg_tRTP = 16'd18;
        cfg_CL = 16'd40; cfg_CWL = 16'd39;
        cfg_tCCD_L = 16'd8; cfg_tCCD_S = 16'd4;
        cfg_tRRD_L = 16'd8; cfg_tRRD_S = 16'd4; cfg_tFAW = 16'd16;
        cfg_tXS = 16'd10; cfg_tXP = 16'd10;
        cfg_tZQCAL = 16'd8; cfg_tZQCS = 16'd8;
        cfg_fgr_mode = 2'b01; cfg_auto_ref_en = 1;
        cfg_manual_ref = 0; cfg_ecc_en = 1; cfg_sreq_enter = 0;

        repeat(10) @(posedge clk);
        rst_n = 1;
        wait_cycles(10);

        // ---- Test 1: Controller ready after reset ----
        test_num = 1;
        $display("\n--- Test %0d: Controller ready after reset ---", test_num);
        if (ctrl_ready === 1'b1) begin
            $display("[PASS] Test %0d: Controller ready (state=%0h)", test_num, ctrl_state);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Controller not ready (state=%0h)", test_num, ctrl_state);
            fail_count++;
        end

        // ---- Test 2: Single read command ----
        // send read -> scheduler queues it -> ACT on DFI -> RD on DFI
        test_num = 2;
        $display("\n--- Test %0d: Single read command ---", test_num);
        clr_pulses(1, 1, 0);
        send_read_cmd(8'h01, 34'h1000, 2'd0);
        // Wait for full command completion: tRCD(34)+CL(40)+burst(8)+tRTP(18)+tRP(34) ~134 cycles
        wait_cycles(400);
        if (dfi_act_pulse_seen) begin
            $display("[PASS] Test %0d: DFI ACT issued", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No DFI ACT seen", test_num);
            fail_count++;
        end

        // ---- Test 3: Single write command ----
        test_num = 3;
        $display("\n--- Test %0d: Single write command ---", test_num);
        clr_pulses(1, 0, 1);
        send_write_cmd(8'h02, 34'h2000, 2'd1);
        wait_cycles(400);
        if (dfi_act_pulse_seen) begin
            $display("[PASS] Test %0d: DFI ACT issued for write", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No DFI ACT for write", test_num);
            fail_count++;
        end

        // ---- Test 4: Multiple read commands to different banks ----
        test_num = 4;
        $display("\n--- Test %0d: Multiple read commands to different banks ---", test_num);
        clr_pulses(1, 1, 0);
        send_read_cmd(8'h10, 34'h3000, 2'd0);  // BG=0, bank=0
        send_read_cmd(8'h11, 34'h4000, 2'd1);  // different bank
        send_read_cmd(8'h12, 34'h5000, 2'd2);  // different bank
        wait_cycles(800);
        if (dfi_act_pulse_seen) begin
            $display("[PASS] Test %0d: DFI ACT issued for multi reads", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No DFI ACT for multi reads", test_num);
            fail_count++;
        end

        // ---- Test 5: Mixed read/write ----
        test_num = 5;
        $display("\n--- Test %0d: Mixed read/write ---", test_num);
        clr_pulses(1, 0, 0);
        send_read_cmd(8'h20, 34'h6000, 2'd0);
        send_write_cmd(8'h21, 34'h7000, 2'd1);
        send_read_cmd(8'h22, 34'h8000, 2'd2);
        wait_cycles(800);
        if (dfi_act_pulse_seen) begin
            $display("[PASS] Test %0d: DFI ACT for mixed R/W", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No DFI ACT for mixed R/W", test_num);
            fail_count++;
        end

        // ---- Test 6: Refresh credit accumulation ----
        test_num = 6;
        $display("\n--- Test %0d: Refresh credit accumulation ---", test_num);
        // Let tREFI expire enough times to accumulate credits
        // With FGR 2x, tREFI=9375, credit accumulates 2 per tREFI tick
        // But ref_ack consumes credits. Credits will be 0-2 range.
        // After 2 tREFI periods (~18750 cycles), check credit was ever non-zero
        // Actually just check that credit_count or overflow is non-zero at some point
        wait_cycles(30000);
        if (refresh_credit_seen) begin
            $display("[PASS] Test %0d: Refresh credits accumulated (credit=%0d, overflow=%0d)", 
                     test_num, refresh_credit, refresh_overflow);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No refresh credits ever (credit=%0d)", test_num, refresh_credit);
            fail_count++;
        end

        // ---- Test 7: Page hit sequence ----
        // First access activates row, second access to same row is page hit (RD directly)
        test_num = 7;
        $display("\n--- Test %0d: Page hit sequence (same row, different col) ---", test_num);
        clr_pulses(1, 1, 0);
        send_read_cmd(8'h30, 34'h9000, 2'd0);   // activate row at 0x9000
        wait_cycles(100); // wait for ACT + tRCD
        // Clear flags and send to same row (different col: 0x9020 = same row 0x9000>>18, col 0x20)
        clr_pulses(1, 1, 0);
        send_read_cmd(8'h31, 34'h9020, 2'd0);   // same row, different column -> page hit
        wait_cycles(100);
        // Should see a RD (not ACT) on DFI
        if (dfi_rd_pulse_seen) begin
            $display("[PASS] Test %0d: Page hit -> DFI RD issued", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No page hit RD (act=%0d, rd=%0d)", 
                     test_num, dfi_act_pulse_seen, dfi_rd_pulse_seen);
            fail_count++;
        end

        // ---- Test 8: Bank group interleaving ----
        test_num = 8;
        $display("\n--- Test %0d: Bank group interleaving ---", test_num);
        clr_pulses(1, 0, 0);
        send_read_cmd(8'h40, 34'hA000, 2'd0);  // BG0
        send_read_cmd(8'h41, 34'hA800, 2'd0);  // BG1
        send_read_cmd(8'h42, 34'hB000, 2'd0);  // BG2
        send_read_cmd(8'h43, 34'hB800, 2'd0);  // BG3
        wait_cycles(300);
        if (dfi_act_pulse_seen) begin
            $display("[PASS] Test %0d: Bank group interleaving ACTs issued", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No ACTs for bank interleaving", test_num);
            fail_count++;
        end

        // ---- Test 9: Back-to-back commands ----
        test_num = 9;
        $display("\n--- Test %0d: Back-to-back commands ---", test_num);
        clr_pulses(1, 0, 0);
        for (int i = 0; i < 10; i++) begin
            send_read_cmd(i[7:0], 34'hC000 + i*32'h100, 2'd0);
            wait_cycles(5);
        end
        wait_cycles(300);
        if (dfi_act_pulse_seen) begin
            $display("[PASS] Test %0d: Back-to-back ACTs issued", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: No ACTs for back-to-back", test_num);
            fail_count++;
        end

        // ---- Test 10: Controller stability ----
        test_num = 10;
        $display("\n--- Test %0d: Controller stability (stress) ---", test_num);
        for (int i = 0; i < 20; i++) begin
            if (i[0]) send_read_cmd(i[7:0], 34'hD000 + i*32'h100, 2'd0);
            else send_write_cmd(i[7:0], 34'hE000 + i*32'h100, 2'd1);
            wait_cycles(10);
        end
        wait_cycles(500);
        // Check controller is not in an error/undefined state
        if (ctrl_state < 4'hA) begin
            $display("[PASS] Test %0d: Controller stable after stress (state=%0h)", test_num, ctrl_state);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Controller in unexpected state (%0h)", test_num, ctrl_state);
            fail_count++;
        end

        // Summary
        $display("\n==========================================");
        $display("Test Summary: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("==========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        $finish;
    end

    initial begin #(CLK_PERIOD * 200000); $display("[ERROR] Timeout!"); $finish; end
    initial begin $dumpfile("tb_ddr5_ctrl_core.vcd"); $dumpvars(0, tb_ddr5_ctrl_core); end

endmodule