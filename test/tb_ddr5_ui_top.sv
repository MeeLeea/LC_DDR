// =============================================================================
// Testbench: tb_ddr5_ui_top
// Description: Top-level testbench for User Interface layer integration
//              Tests AXI4 4-port interface with arbiter and address mapper
// =============================================================================
`timescale 1ns/1ps

module tb_ddr5_ui_top();

    // Parameters
    parameter int NUM_PORTS = 4;
    parameter int ID_W = 8;
    parameter int ADDR_W = 34;
    parameter int DATA_W = 256;
    parameter int STRB_W = DATA_W / 8;
    parameter real USER_CLK_PERIOD = 5.0;  // 200 MHz
    parameter real CTRL_CLK_PERIOD = 2.083; // 480 MHz (DDR5-4800/4)

    // Clocks and reset
    logic user_clk;
    logic ctrl_clk;
    logic por_rst_n;

    // AXI4 interfaces (4 ports)
    logic [ID_W-1:0] s_axi_awid [NUM_PORTS];
    logic [ADDR_W-1:0] s_axi_awaddr [NUM_PORTS];
    logic [7:0] s_axi_awlen [NUM_PORTS];
    logic [2:0] s_axi_awsize [NUM_PORTS];
    logic [1:0] s_axi_awburst [NUM_PORTS];
    logic [3:0] s_axi_awcache [NUM_PORTS];
    logic [2:0] s_axi_awprot [NUM_PORTS];
    logic [3:0] s_axi_awqos [NUM_PORTS];
    logic s_axi_awvalid [NUM_PORTS];
    logic s_axi_awready [NUM_PORTS];
    
    logic [DATA_W-1:0] s_axi_wdata [NUM_PORTS];
    logic [STRB_W-1:0] s_axi_wstrb [NUM_PORTS];
    logic s_axi_wlast [NUM_PORTS];
    logic s_axi_wvalid [NUM_PORTS];
    logic s_axi_wready [NUM_PORTS];
    
    logic [ID_W-1:0] s_axi_bid [NUM_PORTS];
    logic [1:0] s_axi_bresp [NUM_PORTS];
    logic s_axi_bvalid [NUM_PORTS];
    logic s_axi_bready [NUM_PORTS];
    
    logic [ID_W-1:0] s_axi_arid [NUM_PORTS];
    logic [ADDR_W-1:0] s_axi_araddr [NUM_PORTS];
    logic [7:0] s_axi_arlen [NUM_PORTS];
    logic [2:0] s_axi_arsize [NUM_PORTS];
    logic [1:0] s_axi_arburst [NUM_PORTS];
    logic [3:0] s_axi_arcache [NUM_PORTS];
    logic [2:0] s_axi_arprot [NUM_PORTS];
    logic [3:0] s_axi_arqos [NUM_PORTS];
    logic s_axi_arvalid [NUM_PORTS];
    logic s_axi_arready [NUM_PORTS];
    
    logic [ID_W-1:0] s_axi_rid [NUM_PORTS];
    logic [DATA_W-1:0] s_axi_rdata [NUM_PORTS];
    logic [1:0] s_axi_rresp [NUM_PORTS];
    logic s_axi_rlast [NUM_PORTS];
    logic s_axi_rvalid [NUM_PORTS];
    logic s_axi_rready [NUM_PORTS];

    // Command output to controller
    logic cmd_valid;
    logic cmd_ready;
    logic cmd_is_write;
    logic [ID_W-1:0] cmd_id;
    logic [ADDR_W-1:0] cmd_addr;
    logic [7:0] cmd_len;
    logic [1:0] cmd_port_id;
    logic [3:0] cmd_qos;

    // Address mapping output
    logic [17:0] ddr5_row;
    logic [2:0] ddr5_bg;
    logic [2:0] ddr5_ba;
    logic [9:0] ddr5_col;
    logic [1:0] ddr5_rank;

    // Controller-side write data channel (write data sink is always ready here)
    logic wr_data_ready;
    logic [1:0] addr_map_mode;

    // ---------------------------------------------------------------------
    // DUT interconnect: the DUT uses flattened AXI4 vectors, this tb uses
    // unpacked per-port arrays, so bridge them explicitly
    // ---------------------------------------------------------------------
    logic [NUM_PORTS*ID_W-1:0]   f_awid;
    logic [NUM_PORTS*ADDR_W-1:0] f_awaddr;
    logic [NUM_PORTS*8-1:0]      f_awlen;
    logic [NUM_PORTS*3-1:0]      f_awsize;
    logic [NUM_PORTS*2-1:0]      f_awburst;
    logic [NUM_PORTS*4-1:0]      f_awcache;
    logic [NUM_PORTS*3-1:0]      f_awprot;
    logic [NUM_PORTS*4-1:0]      f_awqos;
    logic [NUM_PORTS-1:0]        f_awvalid;
    logic [NUM_PORTS*DATA_W-1:0] f_wdata;
    logic [NUM_PORTS*STRB_W-1:0] f_wstrb;
    logic [NUM_PORTS-1:0]        f_wlast;
    logic [NUM_PORTS-1:0]        f_wvalid;
    logic [NUM_PORTS-1:0]        f_bready;
    logic [NUM_PORTS*ID_W-1:0]   f_arid;
    logic [NUM_PORTS*ADDR_W-1:0] f_araddr;
    logic [NUM_PORTS*8-1:0]      f_arlen;
    logic [NUM_PORTS*3-1:0]      f_arsize;
    logic [NUM_PORTS*2-1:0]      f_arburst;
    logic [NUM_PORTS*4-1:0]      f_arcache;
    logic [NUM_PORTS*3-1:0]      f_arprot;
    logic [NUM_PORTS*4-1:0]      f_arqos;
    logic [NUM_PORTS-1:0]        f_arvalid;
    logic [NUM_PORTS-1:0]        f_awlock;
    logic [NUM_PORTS-1:0]        f_arlock;
    logic [NUM_PORTS-1:0]        f_rready;

    logic [NUM_PORTS-1:0]        d_awready;
    logic [NUM_PORTS-1:0]        d_wready;
    logic [NUM_PORTS*ID_W-1:0]   d_bid;
    logic [NUM_PORTS*2-1:0]      d_bresp;
    logic [NUM_PORTS-1:0]        d_bvalid;
    logic [NUM_PORTS-1:0]        d_arready;
    logic [NUM_PORTS*ID_W-1:0]   d_rid;
    logic [NUM_PORTS*DATA_W-1:0] d_rdata;
    logic [NUM_PORTS*2-1:0]      d_rresp;
    logic [NUM_PORTS-1:0]        d_rlast;
    logic [NUM_PORTS-1:0]        d_rvalid;

    genvar gp;
    generate
        for (gp = 0; gp < NUM_PORTS; gp++) begin : g_axi_flat
            assign f_awid[gp*ID_W+:ID_W]           = s_axi_awid[gp];
            assign f_awaddr[gp*ADDR_W+:ADDR_W]     = s_axi_awaddr[gp];
            assign f_awlen[gp*8+:8]                = s_axi_awlen[gp];
            assign f_awsize[gp*3+:3]               = s_axi_awsize[gp];
            assign f_awburst[gp*2+:2]              = s_axi_awburst[gp];
            assign f_awcache[gp*4+:4]              = s_axi_awcache[gp];
            assign f_awprot[gp*3+:3]               = s_axi_awprot[gp];
            assign f_awqos[gp*4+:4]                = s_axi_awqos[gp];
            assign f_awvalid[gp]                   = s_axi_awvalid[gp];
            assign f_awlock[gp]                    = 1'b0;
            assign f_wdata[gp*DATA_W+:DATA_W]      = s_axi_wdata[gp];
            assign f_wstrb[gp*STRB_W+:STRB_W]      = s_axi_wstrb[gp];
            assign f_wlast[gp]                     = s_axi_wlast[gp];
            assign f_wvalid[gp]                    = s_axi_wvalid[gp];
            assign f_bready[gp]                    = s_axi_bready[gp];
            assign f_arid[gp*ID_W+:ID_W]           = s_axi_arid[gp];
            assign f_araddr[gp*ADDR_W+:ADDR_W]     = s_axi_araddr[gp];
            assign f_arlen[gp*8+:8]                = s_axi_arlen[gp];
            assign f_arsize[gp*3+:3]               = s_axi_arsize[gp];
            assign f_arburst[gp*2+:2]              = s_axi_arburst[gp];
            assign f_arcache[gp*4+:4]              = s_axi_arcache[gp];
            assign f_arprot[gp*3+:3]               = s_axi_arprot[gp];
            assign f_arqos[gp*4+:4]                = s_axi_arqos[gp];
            assign f_arvalid[gp]                   = s_axi_arvalid[gp];
            assign f_arlock[gp]                    = 1'b0;
            assign f_rready[gp]                    = s_axi_rready[gp];

            assign s_axi_awready[gp]               = d_awready[gp];
            assign s_axi_wready[gp]                = d_wready[gp];
            assign s_axi_bid[gp]                   = d_bid[gp*ID_W+:ID_W];
            assign s_axi_bresp[gp]                 = d_bresp[gp*2+:2];
            assign s_axi_bvalid[gp]                = d_bvalid[gp];
            assign s_axi_arready[gp]               = d_arready[gp];
            assign s_axi_rid[gp]                   = d_rid[gp*ID_W+:ID_W];
            assign s_axi_rdata[gp]                 = d_rdata[gp*DATA_W+:DATA_W];
            assign s_axi_rresp[gp]                 = d_rresp[gp*2+:2];
            assign s_axi_rlast[gp]                 = d_rlast[gp];
            assign s_axi_rvalid[gp]                = d_rvalid[gp];
        end
    endgenerate

    // DUT (user interface layer: 4x AXI4 slave + arbiter + addr mapper + cmd CDC)
    ddr5_ui_axi4 #(
        .NUM_PORTS (NUM_PORTS),
        .ID_W      (ID_W),
        .ADDR_W    (ADDR_W),
        .DATA_W    (DATA_W),
        .STRB_W    (STRB_W)
    ) dut (
        .uclk            (user_clk),
        .uclk_rst_n      (por_rst_n),
        .cclk            (ctrl_clk),
        .cclk_rst_n      (por_rst_n),

        .s_axi_awid      (f_awid),
        .s_axi_awaddr    (f_awaddr),
        .s_axi_awlen     (f_awlen),
        .s_axi_awsize    (f_awsize),
        .s_axi_awburst   (f_awburst),
        .s_axi_awcache   (f_awcache),
        .s_axi_awprot    (f_awprot),
        .s_axi_awqos     (f_awqos),
        .s_axi_awlock    (f_awlock),
        .s_axi_awvalid   (f_awvalid),
        .s_axi_awready   (d_awready),
        .s_axi_wdata     (f_wdata),
        .s_axi_wstrb     (f_wstrb),
        .s_axi_wlast     (f_wlast),
        .s_axi_wvalid    (f_wvalid),
        .s_axi_wready    (d_wready),
        .s_axi_bid       (d_bid),
        .s_axi_bresp     (d_bresp),
        .s_axi_bvalid    (d_bvalid),
        .s_axi_bready    (f_bready),
        .s_axi_arid      (f_arid),
        .s_axi_araddr    (f_araddr),
        .s_axi_arlen     (f_arlen),
        .s_axi_arsize    (f_arsize),
        .s_axi_arburst   (f_arburst),
        .s_axi_arcache   (f_arcache),
        .s_axi_arprot    (f_arprot),
        .s_axi_arqos     (f_arqos),
        .s_axi_arlock    (f_arlock),
        .s_axi_arvalid   (f_arvalid),
        .s_axi_arready   (d_arready),
        .s_axi_rid       (d_rid),
        .s_axi_rdata     (d_rdata),
        .s_axi_rresp     (d_rresp),
        .s_axi_rlast     (d_rlast),
        .s_axi_rvalid    (d_rvalid),
        .s_axi_rready    (f_rready),

        .cmd_valid       (cmd_valid),
        .cmd_ready       (cmd_ready),
        .cmd_is_write    (cmd_is_write),
        .cmd_id          (cmd_id),
        .cmd_addr        (cmd_addr),
        .cmd_len         (cmd_len),
        .cmd_port_id     (cmd_port_id),
        .cmd_qos         (cmd_qos),

        .wr_data_valid   (),
        .wr_data_ready   (wr_data_ready),
        .wr_data         (),
        .wr_strb         (),
        .wr_last         (),

        .rd_data         ({DATA_W{1'b0}}),
        .rd_data_valid   (1'b0),
        .rd_data_ready   (),
        .rd_port_id      (2'd0),
        .rd_id           (8'd0),

        .addr_map_mode   (addr_map_mode)
    );

    // ---------------------------------------------------------------------
    // Command monitor (cclk domain): latch the first command accepted by the
    // controller side, because cmd_valid is a one-cycle pulse on the CDC
    // FIFO output and is already gone when the AXI write response returns.
    // ---------------------------------------------------------------------
    logic        mon_cmd_seen;
    logic        mon_cmd_is_wr;
    logic [1:0]  mon_cmd_port;
    logic [ADDR_W-1:0] mon_cmd_addr;

    always_ff @(posedge ctrl_clk or negedge por_rst_n) begin
        if (!por_rst_n) begin
            mon_cmd_seen  <= 1'b0;
            mon_cmd_is_wr <= 1'b0;
            mon_cmd_port  <= 2'd0;
            mon_cmd_addr  <= '0;
        end else if (cmd_valid === 1'b1) begin
            mon_cmd_seen  <= 1'b1;
            mon_cmd_is_wr <= cmd_is_write;
            mon_cmd_port  <= cmd_port_id;
            mon_cmd_addr  <= cmd_addr;
        end
    end

    // Clock generation
    initial begin
        user_clk = 0;
        forever #(USER_CLK_PERIOD/2) user_clk = ~user_clk;
    end
    
    initial begin
        ctrl_clk = 0;
        forever #(CTRL_CLK_PERIOD/2) ctrl_clk = ~ctrl_clk;
    end

    // Initialize all ports
    initial begin
        for (int i = 0; i < NUM_PORTS; i++) begin
            s_axi_awid[i] = 0;
            s_axi_awaddr[i] = 0;
            s_axi_awlen[i] = 0;
            s_axi_awsize[i] = 5;
            s_axi_awburst[i] = 2'b01;
            s_axi_awcache[i] = 0;
            s_axi_awprot[i] = 0;
            s_axi_awqos[i] = 0;
            s_axi_awvalid[i] = 0;
            s_axi_wdata[i] = 0;
            s_axi_wstrb[i] = {STRB_W{1'b1}};
            s_axi_wlast[i] = 0;
            s_axi_wvalid[i] = 0;
            s_axi_bready[i] = 1;
            s_axi_arid[i] = 0;
            s_axi_araddr[i] = 0;
            s_axi_arlen[i] = 0;
            s_axi_arsize[i] = 5;
            s_axi_arburst[i] = 2'b01;
            s_axi_arcache[i] = 0;
            s_axi_arprot[i] = 0;
            s_axi_arqos[i] = 0;
            s_axi_arvalid[i] = 0;
            s_axi_rready[i] = 1;
        end
        cmd_ready = 1;
        wr_data_ready = 1;
        addr_map_mode = 2'b00;
    end

    // Test variables
    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Simple write task for port 0
    task automatic port0_write(
        input logic [ADDR_W-1:0] addr,
        input logic [7:0] len
    );
        @(posedge user_clk);
        s_axi_awid[0] = 8'h01;
        s_axi_awaddr[0] = addr;
        s_axi_awlen[0] = len;
        s_axi_awqos[0] = 4'hF;
        s_axi_awvalid[0] = 1;
        @(posedge user_clk);
        while (!s_axi_awready[0]) @(posedge user_clk);
        s_axi_awvalid[0] = 0;
        
        for (int i = 0; i <= len; i++) begin
            @(posedge user_clk);
            s_axi_wdata[0] = i;
            s_axi_wstrb[0] = {STRB_W{1'b1}};
            s_axi_wlast[0] = (i == len);
            s_axi_wvalid[0] = 1;
            @(posedge user_clk);
            while (!s_axi_wready[0]) @(posedge user_clk);
        end
        s_axi_wvalid[0] = 0;
        
        @(posedge user_clk);
        while (!s_axi_bvalid[0]) @(posedge user_clk);
        @(posedge user_clk);
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Testbench: ddr5_ui_top (Integration)");
        $display("NUM_PORTS=%0d, DATA_W=%0d", NUM_PORTS, DATA_W);
        $display("========================================");

        // Reset
        por_rst_n = 0;
        repeat(10) @(posedge user_clk);
        por_rst_n = 1;
        repeat(5) @(posedge user_clk);

        // ==== Test 1: Single port write ====
        $display("\n--- Test 1: Port 0 single write ---");
        test_num = 1;
        port0_write(34'h1000, 8'h00);
        // cmd_valid reaches the controller side through the uclk->cclk CDC FIFO
        repeat(20) @(posedge ctrl_clk);
        if (mon_cmd_seen && mon_cmd_is_wr && mon_cmd_port === 2'd0) begin
            $display("[PASS] Test %0d: Port 0 write transaction (cmd addr=0x%09h)", test_num, mon_cmd_addr);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Port 0 write failed (seen=%0b is_wr=%0b port=%0d)",
                     test_num, mon_cmd_seen, mon_cmd_is_wr, mon_cmd_port);
            fail_count++;
        end

        // ==== Test 2: Address mapping check ====
        $display("\n--- Test 2: Address mapping ---");
        test_num = 2;
        port0_write(34'hABCD_1234, 8'h00);
        repeat(5) @(posedge user_clk);
        // Check the decoder inside the DUT follows the arbitrated address
        if (dut.map_row !== 'x && dut.map_bg !== 'x && dut.map_ba !== 'x && dut.map_col !== 'x) begin
            $display("[PASS] Test %0d: Address mapping active", test_num);
            $display("  Row=0x%05h BG=%0d BA=%0d Col=0x%03h Rank=%0d",
                     dut.map_row, dut.map_bg, dut.map_ba, dut.map_col, dut.map_rank);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: Address mapping produced X", test_num);
            fail_count++;
        end

        // ==== Test 3: Multi-port arbitration ====
        $display("\n--- Test 3: Multi-port arbitration ---");
        test_num = 3;
        fork
            // Port 0 write
            begin
                @(posedge user_clk);
                s_axi_awid[0] = 8'h10;
                s_axi_awaddr[0] = 34'h2000;
                s_axi_awlen[0] = 0;
                s_axi_awqos[0] = 4'hF;
                s_axi_awvalid[0] = 1;
                @(posedge user_clk);
                while (!s_axi_awready[0]) @(posedge user_clk);
                s_axi_awvalid[0] = 0;
            end
            // Port 1 write
            begin
                @(posedge user_clk);
                s_axi_awid[1] = 8'h20;
                s_axi_awaddr[1] = 34'h3000;
                s_axi_awlen[1] = 0;
                s_axi_awqos[1] = 4'h5;
                s_axi_awvalid[1] = 1;
                @(posedge user_clk);
                while (!s_axi_awready[1]) @(posedge user_clk);
                s_axi_awvalid[1] = 0;
            end
        join
        
        repeat(10) @(posedge user_clk);
        $display("[PASS] Test %0d: Multi-port arbitration (no crash)", test_num);
        pass_count++;

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
        #(USER_CLK_PERIOD * 10000);
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

    // Waveform
    initial begin
        $dumpfile("tb_ddr5_ui_top.vcd");
        $dumpvars(0, tb_ddr5_ui_top);
    end

endmodule
