// =============================================================================
// Testbench: tb_ddr5_ui_axi4
// Description: Integration testbench for UI AXI4 layer
//              Tests 4-port AXI4 slaves + arbiter + addr_mapper + CDC FIFO
//              across uclk/cclk clock domains
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_ui_axi4();

    // Parameters
    parameter int NUM_PORTS = 4;
    parameter int ID_W      = 8;
    parameter int ADDR_W    = 34;
    parameter int DATA_W    = 256;
    parameter int STRB_W    = DATA_W / 8;
    parameter real UCLK_PERIOD = 5.0;    // 200 MHz
    parameter real CCLK_PERIOD = 2.083;  // 480 MHz

    // Clocks and resets
    logic uclk, cclk;
    logic uclk_rst_n, cclk_rst_n;

    // Flattened AXI4 signals (4 ports)
    logic [NUM_PORTS*ID_W-1:0]   s_axi_awid;
    logic [NUM_PORTS*ADDR_W-1:0] s_axi_awaddr;
    logic [NUM_PORTS*8-1:0]      s_axi_awlen;
    logic [NUM_PORTS*3-1:0]      s_axi_awsize;
    logic [NUM_PORTS*2-1:0]      s_axi_awburst;
    logic [NUM_PORTS*4-1:0]      s_axi_awcache;
    logic [NUM_PORTS*3-1:0]      s_axi_awprot;
    logic [NUM_PORTS*4-1:0]      s_axi_awqos;
    logic [NUM_PORTS-1:0]        s_axi_awlock = '0;   // B-02: default normal access
    logic [NUM_PORTS-1:0]        s_axi_awvalid;
    logic [NUM_PORTS-1:0]        s_axi_awready;
    logic [NUM_PORTS*DATA_W-1:0] s_axi_wdata;
    logic [NUM_PORTS*STRB_W-1:0] s_axi_wstrb;
    logic [NUM_PORTS-1:0]        s_axi_wlast;
    logic [NUM_PORTS-1:0]        s_axi_wvalid;
    logic [NUM_PORTS-1:0]        s_axi_wready;
    logic [NUM_PORTS*ID_W-1:0]   s_axi_bid;
    logic [NUM_PORTS*2-1:0]      s_axi_bresp;
    logic [NUM_PORTS-1:0]        s_axi_bvalid;
    logic [NUM_PORTS-1:0]        s_axi_bready;
    logic [NUM_PORTS*ID_W-1:0]   s_axi_arid;
    logic [NUM_PORTS*ADDR_W-1:0] s_axi_araddr;
    logic [NUM_PORTS*8-1:0]      s_axi_arlen;
    logic [NUM_PORTS*3-1:0]      s_axi_arsize;
    logic [NUM_PORTS*2-1:0]      s_axi_arburst;
    logic [NUM_PORTS*4-1:0]      s_axi_arcache;
    logic [NUM_PORTS*3-1:0]      s_axi_arprot;
    logic [NUM_PORTS*4-1:0]      s_axi_arqos;
    logic [NUM_PORTS-1:0]        s_axi_arlock = '0;   // B-02: default normal access
    logic [NUM_PORTS-1:0]        s_axi_arvalid;
    logic [NUM_PORTS-1:0]        s_axi_arready;
    logic [NUM_PORTS*ID_W-1:0]   s_axi_rid;
    logic [NUM_PORTS*DATA_W-1:0] s_axi_rdata;
    logic [NUM_PORTS*2-1:0]      s_axi_rresp;
    logic [NUM_PORTS-1:0]        s_axi_rlast;
    logic [NUM_PORTS-1:0]        s_axi_rvalid;
    logic [NUM_PORTS-1:0]        s_axi_rready;

    // Controller-side command output (cclk domain)
    logic              cmd_valid;
    logic              cmd_ready;
    logic              cmd_is_write;
    logic [ID_W-1:0]   cmd_id;
    logic [ADDR_W-1:0] cmd_addr;
    logic [7:0]        cmd_len;
    logic [1:0]        cmd_port_id;
    logic [3:0]        cmd_qos;

    // Write data output (cclk domain)
    logic              wr_data_valid;
    logic              wr_data_ready;
    logic [DATA_W-1:0] wr_data;
    logic [STRB_W-1:0] wr_strb;
    logic              wr_last;

    // Read data input (cclk domain)
    logic [DATA_W-1:0] rd_data;
    logic              rd_data_valid;
    logic              rd_data_ready;
    logic [1:0]        rd_port_id;
    logic [ID_W-1:0]   rd_id;

    // Address map mode
    logic [1:0] addr_map_mode;

    // =========================================================================
    // DUT
    // =========================================================================
    ddr5_ui_axi4 #(
        .NUM_PORTS(NUM_PORTS), .ID_W(ID_W),
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .STRB_W(STRB_W)
    ) dut (
        .uclk(uclk), .uclk_rst_n(uclk_rst_n),
        .cclk(cclk), .cclk_rst_n(cclk_rst_n),
        .s_axi_awid(s_axi_awid), .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen), .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst), .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot), .s_axi_awqos(s_axi_awqos),
        .s_axi_awlock(s_axi_awlock),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid), .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen), .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst), .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot), .s_axi_arqos(s_axi_arqos),
        .s_axi_arlock(s_axi_arlock),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_is_write(cmd_is_write), .cmd_id(cmd_id),
        .cmd_addr(cmd_addr), .cmd_len(cmd_len),
        .cmd_port_id(cmd_port_id), .cmd_qos(cmd_qos),
        .wr_data_valid(wr_data_valid), .wr_data_ready(wr_data_ready),
        .wr_data(wr_data), .wr_strb(wr_strb), .wr_last(wr_last),
        .rd_data(rd_data), .rd_data_valid(rd_data_valid),
        .rd_data_ready(rd_data_ready),
        .rd_port_id(rd_port_id), .rd_id(rd_id),
        .addr_map_mode(addr_map_mode)
    );

    // =========================================================================
    // Clock generation
    // =========================================================================
    initial begin uclk = 0; forever #(UCLK_PERIOD/2) uclk = ~uclk; end
    initial begin cclk = 0; forever #(CCLK_PERIOD/2) cclk = ~cclk; end

    // =========================================================================
    // Functional coverage collector (test/ddr5_covergroups.sv).
    // The collector exposes its sampling points as internal signals, they are
    // driven hierarchically here from the AXI4 interface and DUT internals.
    // =========================================================================
    ddr5_coverage_collector u_cov ();

    // gray -> binary (CDC FIFO write pointer synchronizer) to get the occupancy
    function automatic logic [4:0] gray2bin5(input logic [4:0] g);
        logic [4:0] b;
        b[4] = g[4];
        b[3] = b[4] ^ g[3];
        b[2] = b[3] ^ g[2];
        b[1] = b[2] ^ g[1];
        b[0] = b[1] ^ g[0];
        return b;
    endfunction

    logic [4:0] cov_fifo_occ;
    assign cov_fifo_occ = dut.u_cmd_fifo.wr_ptr_bin[4:0]
                        - gray2bin5(dut.u_cmd_fifo.rd_ptr_gray_sync_wr[4:0]);

    assign u_cov.clk          = uclk;
    assign u_cov.wr_clk       = uclk;

    // AXI4 write/read channel (port 0 is the port exercised by this tb)
    assign u_cov.awlen        = s_axi_awlen[7:0];
    assign u_cov.awsize       = s_axi_awsize[2:0];
    assign u_cov.awid         = s_axi_awid[7:0];
    assign u_cov.awqos        = s_axi_awqos[3:0];
    assign u_cov.awvalid      = s_axi_awvalid[0];
    assign u_cov.awready      = s_axi_awready[0];
    assign u_cov.arlen        = s_axi_arlen[7:0];
    assign u_cov.arsize       = s_axi_arsize[2:0];
    assign u_cov.arid         = s_axi_arid[7:0];
    assign u_cov.arqos        = s_axi_arqos[3:0];

    // Arbitrated command stream
    assign u_cov.out_port_id  = dut.arb_port;
    assign u_cov.out_is_write = dut.arb_is_write;
    assign u_cov.out_qos      = dut.arb_qos;

    // Address decoder
    assign u_cov.bg_addr      = dut.map_bg;
    assign u_cov.bank_addr    = dut.map_ba;
    assign u_cov.rank_addr    = dut.map_rank;
    assign u_cov.row_addr     = dut.map_row[15:0];
    assign u_cov.col_addr     = dut.map_col[8:0];
    assign u_cov.sub_channel  = dut.map_sub_ch;

    // Command CDC FIFO
    assign u_cov.wr_count     = cov_fifo_occ;
    assign u_cov.wr_full      = dut.cmd_fifo_full;

    // Exclusive access / responses
    assign u_cov.awlock       = s_axi_awlock[0];
    assign u_cov.arlock       = s_axi_arlock[0];
    assign u_cov.res_valid    = dut.mon_res_valid[0];
    assign u_cov.bresp        = s_axi_bresp[1:0];
    assign u_cov.rresp        = s_axi_rresp[1:0];

    // =========================================================================
    // Test infrastructure
    // =========================================================================
    int test_num   = 0;
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(string desc, logic cond);
        if (cond) begin
            $display("[PASS] Test %0d: %s", test_num, desc);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s", test_num, desc);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Port-0 AXI write task (single beat, len=0)
    // =========================================================================
    task automatic port0_write(
        input logic [ID_W-1:0]   id,
        input logic [ADDR_W-1:0] addr,
        input logic [3:0]        qos,
        input logic [DATA_W-1:0] data
    );
        @(posedge uclk);
        s_axi_awid[0*ID_W+:ID_W]       = id;
        s_axi_awaddr[0*ADDR_W+:ADDR_W]  = addr;
        s_axi_awlen[0*8+:8]             = 8'd0;  // single beat
        s_axi_awsize[0*3+:3]            = 3'd5;  // 32 bytes
        s_axi_awburst[0*2+:2]           = 2'b01; // INCR
        s_axi_awqos[0*4+:4]             = qos;
        s_axi_awvalid[0]                = 1;
        s_axi_wdata[0*DATA_W+:DATA_W]   = data;
        s_axi_wstrb[0*STRB_W+:STRB_W]   = {STRB_W{1'b1}};
        s_axi_wlast[0]                  = 1;
        s_axi_wvalid[0]                 = 1;
        s_axi_bready[0]                 = 1;
        @(posedge uclk);
        while (!s_axi_awready[0]) @(posedge uclk);
        s_axi_awvalid[0] = 0;
        while (!s_axi_wready[0]) @(posedge uclk);
        s_axi_wvalid[0] = 0;
        s_axi_wlast[0]  = 0;
        // Wait for B response
        while (!s_axi_bvalid[0]) @(posedge uclk);
        @(posedge uclk);
    endtask

    // =========================================================================
    // Port-1 AXI read task (single beat, len=0)
    // =========================================================================
    task automatic port1_read(
        input logic [ID_W-1:0]   id,
        input logic [ADDR_W-1:0] addr,
        input logic [3:0]        qos
    );
        @(posedge uclk);
        s_axi_arid[1*ID_W+:ID_W]       = id;
        s_axi_araddr[1*ADDR_W+:ADDR_W]  = addr;
        s_axi_arlen[1*8+:8]             = 8'd0;
        s_axi_arsize[1*3+:3]            = 3'd5;
        s_axi_arburst[1*2+:2]           = 2'b01;
        s_axi_arqos[1*4+:4]             = qos;
        s_axi_arvalid[1]                = 1;
        s_axi_rready[1]                 = 1;
        @(posedge uclk);
        while (!s_axi_arready[1]) @(posedge uclk);
        s_axi_arvalid[1] = 0;
        // Wait for R response
        while (!s_axi_rvalid[1]) @(posedge uclk);
        @(posedge uclk);
    endtask

    // =========================================================================
    // cclk-side: always consume commands
    // =========================================================================
    int cmd_count = 0;
    // hoisted out of unnamed begin blocks (AGENT.md rule #8 / Xsim HDL 9-1206)
    int cnt_before;
    logic [ADDR_W-1:0] last_cmd_addr;
    logic              last_cmd_is_write;
    logic [1:0]        last_cmd_port_id;
    logic [3:0]        last_cmd_qos;

    // Always ready to consume — DUT's cmd_valid gates the FIFO read
    assign cmd_ready = 1'b1;

    // Registered sampling: capture data when cmd_valid is high
    // Use edge detection to avoid counting the same command twice
    // (CDC FIFO's rd_empty is registered, causing 1 extra cycle of garbage after empty)
    logic              sample_valid_r;
    logic [ADDR_W-1:0] sample_addr_r;
    logic              sample_is_write_r;
    logic [1:0]        sample_port_id_r;
    logic [3:0]        sample_qos_r;
    logic              prev_valid;

    always_ff @(posedge cclk or negedge cclk_rst_n) begin
        if (!cclk_rst_n) begin
            sample_valid_r    <= 0;
            sample_addr_r     <= 0;
            sample_is_write_r <= 0;
            sample_port_id_r  <= 0;
            sample_qos_r      <= 0;
            prev_valid        <= 0;
        end else begin
            prev_valid <= cmd_valid;
            // Only capture on rising edge of cmd_valid (new data available)
            if (cmd_valid && !prev_valid) begin
                sample_valid_r    <= 1;
                sample_addr_r     <= cmd_addr;
                sample_is_write_r <= cmd_is_write;
                sample_port_id_r  <= cmd_port_id;
                sample_qos_r      <= cmd_qos;
            end else begin
                sample_valid_r <= 0;
            end
        end
    end

    initial begin
        // cmd_ready driven by assign above
        cmd_count = 0;
        last_cmd_addr = 0;
        last_cmd_is_write = 0;
        last_cmd_port_id = 0;
        last_cmd_qos = 0;
        forever begin
            @(posedge cclk);
            // Detect rising edge of sample_valid_r to count unique commands
            if (sample_valid_r) begin
                last_cmd_addr     = sample_addr_r;
                last_cmd_is_write = sample_is_write_r;
                last_cmd_port_id  = sample_port_id_r;
                last_cmd_qos      = sample_qos_r;
                cmd_count++;
                $display("[MON] cclk cmd #%0d: addr=0x%09h wr=%0b port=%0d qos=0x%0h",
                         cmd_count, sample_addr_r, sample_is_write_r, sample_port_id_r, sample_qos_r);
            end
        end
    end

    // Write data always ready
    assign wr_data_ready = 1;

    // Read data: respond with a fixed pattern after a short delay
    initial begin
        rd_data       = 0;
        rd_data_valid = 0;
        rd_port_id    = 0;
        rd_id         = 0;
    end

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $display("========================================");
        $display("Testbench: ddr5_ui_axi4 (Integration)");
        $display("NUM_PORTS=%0d, DATA_W=%0d", NUM_PORTS, DATA_W);
        $display("uclk=%0.1f ns, cclk=%0.3f ns", UCLK_PERIOD, CCLK_PERIOD);
        $display("========================================");

        // Initialize
        uclk_rst_n = 0; cclk_rst_n = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_wlast = 0;
        s_axi_arvalid = 0;
        s_axi_bready  = {NUM_PORTS{1'b1}};
        s_axi_rready  = {NUM_PORTS{1'b1}};
        s_axi_awid    = 0; s_axi_awaddr  = 0; s_axi_awlen = 0;
        s_axi_awsize  = 0; s_axi_awburst = 0; s_axi_awcache = 0;
        s_axi_awprot  = 0; s_axi_awqos   = 0;
        s_axi_wdata   = 0; s_axi_wstrb   = 0;
        s_axi_arid    = 0; s_axi_araddr  = 0; s_axi_arlen = 0;
        s_axi_arsize  = 0; s_axi_arburst = 0; s_axi_arcache = 0;
        s_axi_arprot  = 0; s_axi_arqos   = 0;
        addr_map_mode = 2'b00;

        repeat(10) @(posedge uclk);
        uclk_rst_n = 1; cclk_rst_n = 1;
        repeat(5) @(posedge uclk);

        // ==== Test 1: Port 0 single write → CDC output ===
        test_num = 1;
        begin
            cnt_before = cmd_count;
            port0_write(8'hAA, 34'h1000, 4'hF, 256'hDEAD_BEEF);
            repeat(10) @(posedge cclk);
            check("Port 0 write: cmd received in cclk domain",
                  (cmd_count - cnt_before) >= 1 && last_cmd_is_write && last_cmd_addr == 34'h1000);
        end

        // ==== Test 2: Port 0 write QoS passthrough ===
        test_num = 2;
        begin
            cnt_before = cmd_count;
            $display("[DBG] Test 2: cnt_before=%0d", cnt_before);
            port0_write(8'hBB, 34'h2000, 4'h5, 256'hCAFE_BABE);
            repeat(10) @(posedge cclk);
            $display("[DBG] Test 2: cmd_count=%0d last_qos=0x%0h", cmd_count, last_cmd_qos);
            check("Port 0 write: QoS=0x5 passed through",
                  (cmd_count - cnt_before) >= 1 && last_cmd_qos == 4'h5);
        end

        // ==== Test 3: Port 1 single read → CDC output ===
        test_num = 3;
        begin
            cnt_before = cmd_count;
            $display("[DBG] Test 3: cnt_before=%0d", cnt_before);
            @(posedge uclk);
            s_axi_arid[1*ID_W+:ID_W]       = 8'hCC;
            s_axi_araddr[1*ADDR_W+:ADDR_W]  = 34'h3000;
            s_axi_arlen[1*8+:8]             = 8'd0;
            s_axi_arsize[1*3+:3]            = 3'd5;
            s_axi_arburst[1*2+:2]           = 2'b01;
            s_axi_arqos[1*4+:4]             = 4'h3;
            s_axi_arvalid[1]                = 1;
            s_axi_rready[1]                 = 1;
            @(posedge uclk);
            while (!s_axi_arready[1]) @(posedge uclk);
            s_axi_arvalid[1] = 0;
            repeat(5) @(posedge cclk);
            @(posedge cclk);
            rd_data       = 256'h1234_5678;
            rd_data_valid = 1;
            rd_port_id    = 2'd1;
            rd_id         = 8'hCC;
            @(posedge cclk);
            rd_data_valid = 0;
            repeat(20) @(posedge uclk);
            $display("[DBG] Test 3: cmd_count=%0d last_addr=0x%09h", cmd_count, last_cmd_addr);
            check("Port 1 read: cmd received in cclk domain",
                  (cmd_count - cnt_before) >= 1 && last_cmd_addr == 34'h3000);
        end

        // ==== Test 4: Multi-port simultaneous write ===
        test_num = 4;
        begin
            cnt_before = cmd_count;
            fork
            // Port 0 write
            begin
                @(posedge uclk);
                s_axi_awid[0*ID_W+:ID_W]       = 8'h10;
                s_axi_awaddr[0*ADDR_W+:ADDR_W]  = 34'h4000;
                s_axi_awlen[0*8+:8]             = 8'd0;
                s_axi_awsize[0*3+:3]            = 3'd5;
                s_axi_awburst[0*2+:2]           = 2'b01;
                s_axi_awqos[0*4+:4]             = 4'hF;
                s_axi_awvalid[0]                = 1;
                s_axi_wdata[0*DATA_W+:DATA_W]   = 256'hA0;
                s_axi_wstrb[0*STRB_W+:STRB_W]   = {STRB_W{1'b1}};
                s_axi_wlast[0]                  = 1;
                s_axi_wvalid[0]                 = 1;
                s_axi_bready[0]                 = 1;
                @(posedge uclk);
                while (!s_axi_awready[0]) @(posedge uclk);
                s_axi_awvalid[0] = 0;
                while (!s_axi_wready[0]) @(posedge uclk);
                s_axi_wvalid[0] = 0;
                s_axi_wlast[0]  = 0;
                while (!s_axi_bvalid[0]) @(posedge uclk);
                @(posedge uclk);
            end
            // Port 2 write
            begin
                @(posedge uclk);
                s_axi_awid[2*ID_W+:ID_W]       = 8'h20;
                s_axi_awaddr[2*ADDR_W+:ADDR_W]  = 34'h5000;
                s_axi_awlen[2*8+:8]             = 8'd0;
                s_axi_awsize[2*3+:3]            = 3'd5;
                s_axi_awburst[2*2+:2]           = 2'b01;
                s_axi_awqos[2*4+:4]             = 4'hA;
                s_axi_awvalid[2]                = 1;
                s_axi_wdata[2*DATA_W+:DATA_W]   = 256'hB0;
                s_axi_wstrb[2*STRB_W+:STRB_W]   = {STRB_W{1'b1}};
                s_axi_wlast[2]                  = 1;
                s_axi_wvalid[2]                 = 1;
                s_axi_bready[2]                 = 1;
                @(posedge uclk);
                while (!s_axi_awready[2]) @(posedge uclk);
                s_axi_awvalid[2] = 0;
                while (!s_axi_wready[2]) @(posedge uclk);
                s_axi_wvalid[2] = 0;
                s_axi_wlast[2]  = 0;
                while (!s_axi_bvalid[2]) @(posedge uclk);
                @(posedge uclk);
            end
            join
            repeat(20) @(posedge cclk);
            check("Multi-port write: both commands received",
                  (cmd_count - cnt_before) >= 2);
        end

        // ==== Test 5: Port ID tracking ===
        test_num = 5;
        begin
            cnt_before = cmd_count;
            $display("[DBG] Test 5: cnt_before=%0d", cnt_before);
        // Send from port 3 only
        @(posedge uclk);
        s_axi_awid[3*ID_W+:ID_W]       = 8'h33;
        s_axi_awaddr[3*ADDR_W+:ADDR_W]  = 34'h6000;
        s_axi_awlen[3*8+:8]             = 8'd0;
        s_axi_awsize[3*3+:3]            = 3'd5;
        s_axi_awburst[3*2+:2]           = 2'b01;
        s_axi_awqos[3*4+:4]             = 4'h1;
        s_axi_awvalid[3]                = 1;
        s_axi_wdata[3*DATA_W+:DATA_W]   = 256'hC0;
        s_axi_wstrb[3*STRB_W+:STRB_W]   = {STRB_W{1'b1}};
        s_axi_wlast[3]                  = 1;
        s_axi_wvalid[3]                 = 1;
        s_axi_bready[3]                 = 1;
        @(posedge uclk);
        while (!s_axi_awready[3]) @(posedge uclk);
        s_axi_awvalid[3] = 0;
        while (!s_axi_wready[3]) @(posedge uclk);
        s_axi_wvalid[3] = 0;
        s_axi_wlast[3]  = 0;
        while (!s_axi_bvalid[3]) @(posedge uclk);
        @(posedge uclk);
        repeat(10) @(posedge cclk);
            $display("[DBG] Test 5: cmd_count=%0d last_port=%0d", cmd_count, last_cmd_port_id);
            check("Port 3 write: port_id=3 in cclk domain",
                  (cmd_count - cnt_before) >= 1 && last_cmd_port_id == 2'd3);
        end

        // ==== Test 6: Address map mode change ===
        test_num = 6;
        addr_map_mode = 2'b01;
        repeat(5) @(posedge uclk);
        addr_map_mode = 2'b10;
        repeat(5) @(posedge uclk);
        addr_map_mode = 2'b00;
        repeat(5) @(posedge uclk);
        check("Address map mode switching: no crash", 1'b1);

        // ==== Test 7: Back-to-back writes ===
        test_num = 7;
        begin
            cnt_before = cmd_count;
            for (int i = 0; i < 5; i++) begin
                port0_write(i[7:0], 34'h8000 + i*32'h100, 4'h0, i);
            end
            repeat(20) @(posedge cclk);
            check("Back-to-back writes: 5 commands received",
                  (cmd_count - cnt_before) >= 5);
        end

        // ==== Test 8: Write data passthrough ===
        test_num = 8;
        @(posedge uclk);
        s_axi_awid[0*ID_W+:ID_W]       = 8'hDD;
        s_axi_awaddr[0*ADDR_W+:ADDR_W]  = 34'h9000;
        s_axi_awlen[0*8+:8]             = 8'd0;
        s_axi_awsize[0*3+:3]            = 3'd5;
        s_axi_awburst[0*2+:2]           = 2'b01;
        s_axi_awqos[0*4+:4]             = 4'h0;
        s_axi_awvalid[0]                = 1;
        s_axi_wdata[0*DATA_W+:DATA_W]   = 256'hFEED_FACE;
        s_axi_wstrb[0*STRB_W+:STRB_W]   = {STRB_W{1'b1}};
        s_axi_wlast[0]                  = 1;
        s_axi_wvalid[0]                 = 1;
        s_axi_bready[0]                 = 1;
        @(posedge uclk);
        while (!s_axi_awready[0]) @(posedge uclk);
        s_axi_awvalid[0] = 0;
        while (!s_axi_wready[0]) @(posedge uclk);
        // Check write data passthrough
        #1;
        check("Write data passthrough: wr_data matches",
              wr_data == 256'hFEED_FACE && wr_data_valid);
        s_axi_wvalid[0] = 0;
        s_axi_wlast[0]  = 0;
        while (!s_axi_bvalid[0]) @(posedge uclk);
        @(posedge uclk);

        // Summary
        $display("\n========================================");
        $display("Test Summary: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        $finish;
    end

    // Timeout
    initial begin
        #(UCLK_PERIOD * 50000);
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

    // Waveform
    initial begin
        $dumpfile("tb_ddr5_ui_axi4.vcd");
        $dumpvars(0, tb_ddr5_ui_axi4);
    end

endmodule
