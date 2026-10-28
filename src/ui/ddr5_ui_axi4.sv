// =============================================================================
// Module: ddr5_ui_axi4
// Description: User Interface AXI4 Top - 4-port with CDC FIFOs
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_ui_axi4 #(
    parameter int NUM_PORTS = `AXI_NUM_PORTS,
    parameter int ID_W      = `AXI_ID_W,
    parameter int ADDR_W    = `AXI_ADDR_W,
    parameter int DATA_W    = `AXI_DATA_W,
    parameter int STRB_W    = `AXI_STRB_W
)(
    input  logic uclk, uclk_rst_n,
    input  logic cclk, cclk_rst_n,

    // Flattened AXI4 (4 ports)
    input  logic [NUM_PORTS*ID_W-1:0]   s_axi_awid,
    input  logic [NUM_PORTS*ADDR_W-1:0] s_axi_awaddr,
    input  logic [NUM_PORTS*8-1:0]      s_axi_awlen,
    input  logic [NUM_PORTS*3-1:0]      s_axi_awsize,
    input  logic [NUM_PORTS*2-1:0]      s_axi_awburst,
    input  logic [NUM_PORTS*4-1:0]      s_axi_awcache,
    input  logic [NUM_PORTS*3-1:0]      s_axi_awprot,
    input  logic [NUM_PORTS*4-1:0]      s_axi_awqos,
    input  logic [NUM_PORTS-1:0]        s_axi_awlock,   // B-02: per-port exclusive
    input  logic [NUM_PORTS-1:0]        s_axi_awvalid,
    output logic [NUM_PORTS-1:0]        s_axi_awready,
    input  logic [NUM_PORTS*DATA_W-1:0] s_axi_wdata,
    input  logic [NUM_PORTS*STRB_W-1:0] s_axi_wstrb,
    input  logic [NUM_PORTS-1:0]        s_axi_wlast,
    input  logic [NUM_PORTS-1:0]        s_axi_wvalid,
    output logic [NUM_PORTS-1:0]        s_axi_wready,
    output logic [NUM_PORTS*ID_W-1:0]   s_axi_bid,
    output logic [NUM_PORTS*2-1:0]      s_axi_bresp,
    output logic [NUM_PORTS-1:0]        s_axi_bvalid,
    input  logic [NUM_PORTS-1:0]        s_axi_bready,
    input  logic [NUM_PORTS*ID_W-1:0]   s_axi_arid,
    input  logic [NUM_PORTS*ADDR_W-1:0] s_axi_araddr,
    input  logic [NUM_PORTS*8-1:0]      s_axi_arlen,
    input  logic [NUM_PORTS*3-1:0]      s_axi_arsize,
    input  logic [NUM_PORTS*2-1:0]      s_axi_arburst,
    input  logic [NUM_PORTS*4-1:0]      s_axi_arcache,
    input  logic [NUM_PORTS*3-1:0]      s_axi_arprot,
    input  logic [NUM_PORTS*4-1:0]      s_axi_arqos,
    input  logic [NUM_PORTS-1:0]        s_axi_arlock,   // B-02: per-port exclusive
    input  logic [NUM_PORTS-1:0]        s_axi_arvalid,
    output logic [NUM_PORTS-1:0]        s_axi_arready,
    output logic [NUM_PORTS*ID_W-1:0]   s_axi_rid,
    output logic [NUM_PORTS*DATA_W-1:0] s_axi_rdata,
    output logic [NUM_PORTS*2-1:0]      s_axi_rresp,
    output logic [NUM_PORTS-1:0]        s_axi_rlast,
    output logic [NUM_PORTS-1:0]        s_axi_rvalid,
    input  logic [NUM_PORTS-1:0]        s_axi_rready,

    // To controller (cclk domain)
    output logic              cmd_valid,
    input  logic              cmd_ready,
    output logic              cmd_is_write,
    output logic [ID_W-1:0]   cmd_id,
    output logic [ADDR_W-1:0] cmd_addr,
    output logic [7:0]        cmd_len,
    output logic [1:0]        cmd_port_id,
    output logic [3:0]        cmd_qos,

    // Write data to controller (cclk domain)
    output logic              wr_data_valid,
    input  logic              wr_data_ready,
    output logic [DATA_W-1:0] wr_data,
    output logic [STRB_W-1:0] wr_strb,
    output logic              wr_last,

    // Read data from controller (cclk domain)
    input  logic [DATA_W-1:0] rd_data,
    input  logic              rd_data_valid,
    output logic              rd_data_ready,
    input  logic [1:0]        rd_port_id,
    input  logic [ID_W-1:0]   rd_id,

    input  logic [1:0]        addr_map_mode
);

    // Per-port write slave signals
    logic [NUM_PORTS-1:0] wr_cmd_valid;
    logic [NUM_PORTS-1:0] wr_cmd_ready;
    logic [ID_W-1:0]      wr_cmd_id   [NUM_PORTS];
    logic [ADDR_W-1:0]    wr_cmd_addr [NUM_PORTS];
    logic [7:0]           wr_cmd_len  [NUM_PORTS];
    logic [3:0]           wr_cmd_qos  [NUM_PORTS];

    // Per-port read slave signals
    logic [NUM_PORTS-1:0] rd_cmd_valid;
    logic [NUM_PORTS-1:0] rd_cmd_ready;
    logic [ID_W-1:0]      rd_cmd_id   [NUM_PORTS];
    logic [ADDR_W-1:0]    rd_cmd_addr [NUM_PORTS];
    logic [7:0]           rd_cmd_len  [NUM_PORTS];
    logic [3:0]           rd_cmd_qos  [NUM_PORTS];

    // B-02: exclusive-access monitor per port
    logic [NUM_PORTS-1:0] mon_ex_ok;
    logic [ADDR_W-1:0]    mon_res_addr [NUM_PORTS];
    logic [NUM_PORTS-1:0] mon_res_valid;

    // Generate per-port AXI4 slaves
    generate
        for (genvar i = 0; i < NUM_PORTS; i++) begin : gen_port

            ddr5_axi4_wr_slave #(
                .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W), .STRB_W(STRB_W)
            ) u_wr (
                .clk(uclk), .rst_n(uclk_rst_n),
                .awid(s_axi_awid[i*ID_W+:ID_W]),
                .awaddr(s_axi_awaddr[i*ADDR_W+:ADDR_W]),
                .awlen(s_axi_awlen[i*8+:8]),
                .awsize(s_axi_awsize[i*3+:3]),
                .awburst(s_axi_awburst[i*2+:2]),
                .awcache(s_axi_awcache[i*4+:4]),
                .awprot(s_axi_awprot[i*3+:3]),
                .awqos(s_axi_awqos[i*4+:4]),
                .awlock(s_axi_awlock[i]),
                .awvalid(s_axi_awvalid[i]),
                .awready(s_axi_awready[i]),
                .ex_aw_ok(mon_ex_ok[i]),
                .wdata(s_axi_wdata[i*DATA_W+:DATA_W]),
                .wstrb(s_axi_wstrb[i*STRB_W+:STRB_W]),
                .wlast(s_axi_wlast[i]),
                .wvalid(s_axi_wvalid[i]),
                .wready(s_axi_wready[i]),
                .bid(s_axi_bid[i*ID_W+:ID_W]),
                .bresp(s_axi_bresp[i*2+:2]),
                .bvalid(s_axi_bvalid[i]),
                .bready(s_axi_bready[i]),
                .cmd_valid(wr_cmd_valid[i]),
                .cmd_ready(wr_cmd_ready[i]),
                .cmd_id(wr_cmd_id[i]),
                .cmd_addr(wr_cmd_addr[i]),
                .cmd_len(wr_cmd_len[i]),
                .cmd_qos(wr_cmd_qos[i]),
                .wr_data_valid(),
                .wr_data_ready(1'b1),
                .wr_data(), .wr_strb(), .wr_last()
            );

            ddr5_axi4_rd_slave #(
                .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)
            ) u_rd (
                .clk(uclk), .rst_n(uclk_rst_n),
                .arid(s_axi_arid[i*ID_W+:ID_W]),
                .araddr(s_axi_araddr[i*ADDR_W+:ADDR_W]),
                .arlen(s_axi_arlen[i*8+:8]),
                .arsize(s_axi_arsize[i*3+:3]),
                .arburst(s_axi_arburst[i*2+:2]),
                .arcache(s_axi_arcache[i*4+:4]),
                .arprot(s_axi_arprot[i*3+:3]),
                .arqos(s_axi_arqos[i*4+:4]),
                .arlock(s_axi_arlock[i]),
                .arvalid(s_axi_arvalid[i]),
                .arready(s_axi_arready[i]),
                .rid(s_axi_rid[i*ID_W+:ID_W]),
                .rdata(s_axi_rdata[i*DATA_W+:DATA_W]),
                .rresp(s_axi_rresp[i*2+:2]),
                .rlast(s_axi_rlast[i]),
                .rvalid(s_axi_rvalid[i]),
                .rready(s_axi_rready[i]),
                .cmd_valid(rd_cmd_valid[i]),
                .cmd_ready(rd_cmd_ready[i]),
                .cmd_id(rd_cmd_id[i]),
                .cmd_addr(rd_cmd_addr[i]),
                .cmd_len(rd_cmd_len[i]),
                .cmd_qos(rd_cmd_qos[i]),
                .rd_data(rd_data),
                .rd_data_valid(rd_data_valid & (rd_port_id == i[1:0])),
                .rd_data_ready(rd_data_ready)
            );

            // B-02: exclusive monitor for this port, with cross-port snoop
            logic snoop_i;
            always_comb begin
                snoop_i = 1'b0;
                for (int j = 0; j < NUM_PORTS; j++) begin
                    if (j != i && mon_res_valid[i] &&
                        s_axi_awvalid[j] && s_axi_awready[j] &&
                        (s_axi_awaddr[j*ADDR_W +: ADDR_W] == mon_res_addr[i]))
                        snoop_i = 1'b1;
                end
            end

            ddr5_exclusive_monitor #(.ADDR_W(ADDR_W)) u_exmon (
                .clk       (uclk),
                .rst_n     (uclk_rst_n),
                .awaddr    (s_axi_awaddr[i*ADDR_W +: ADDR_W]),
                .awlock    (s_axi_awlock[i]),
                .awvalid   (s_axi_awvalid[i]),
                .awready   (s_axi_awready[i]),
                .araddr    (s_axi_araddr[i*ADDR_W +: ADDR_W]),
                .arlock    (s_axi_arlock[i]),
                .arvalid   (s_axi_arvalid[i]),
                .arready   (s_axi_arready[i]),
                .ex_aw_ok  (mon_ex_ok[i]),
                .res_addr  (mon_res_addr[i]),
                .res_valid (mon_res_valid[i]),
                .snoop_hit (snoop_i)
            );
        end
    endgenerate

    // Combined command signals for arbiter
    logic [NUM_PORTS-1:0] all_cmd_valid;
    logic [NUM_PORTS-1:0] all_cmd_ready;
    logic [NUM_PORTS-1:0] all_cmd_is_write;
    logic [ID_W-1:0]      all_cmd_id   [NUM_PORTS];
    logic [ADDR_W-1:0]    all_cmd_addr [NUM_PORTS];
    logic [7:0]           all_cmd_len  [NUM_PORTS];
    logic [3:0]           all_cmd_qos  [NUM_PORTS];

    generate
        for (genvar i = 0; i < NUM_PORTS; i++) begin : gen_merge
            assign all_cmd_valid[i]    = wr_cmd_valid[i] | rd_cmd_valid[i];
            assign all_cmd_is_write[i] = wr_cmd_valid[i];
            assign all_cmd_id[i]       = wr_cmd_valid[i] ? wr_cmd_id[i]   : rd_cmd_id[i];
            assign all_cmd_addr[i]     = wr_cmd_valid[i] ? wr_cmd_addr[i] : rd_cmd_addr[i];
            assign all_cmd_len[i]      = wr_cmd_valid[i] ? wr_cmd_len[i]  : rd_cmd_len[i];
            assign all_cmd_qos[i]      = wr_cmd_valid[i] ? wr_cmd_qos[i]  : rd_cmd_qos[i];
            assign wr_cmd_ready[i]     = all_cmd_ready[i] & all_cmd_is_write[i];
            assign rd_cmd_ready[i]     = all_cmd_ready[i] & ~all_cmd_is_write[i];
        end
    endgenerate

    // Arbiter
    logic        arb_valid, arb_ready;
    logic        arb_is_write;
    logic [ID_W-1:0] arb_id;
    logic [ADDR_W-1:0] arb_addr;
    logic [7:0]  arb_len;
    logic [1:0]  arb_port;
    logic [3:0]  arb_qos;

    ddr5_cmd_arbiter #(
        .NUM_PORTS(NUM_PORTS), .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)
    ) u_arb (
        .clk(uclk), .rst_n(uclk_rst_n),
        .cmd_valid(all_cmd_valid), .cmd_ready(all_cmd_ready),
        .cmd_is_write(all_cmd_is_write),
        .cmd_id(all_cmd_id), .cmd_addr(all_cmd_addr),
        .cmd_len(all_cmd_len), .cmd_qos(all_cmd_qos),
        .out_valid(arb_valid), .out_ready(arb_ready),
        .out_is_write(arb_is_write), .out_id(arb_id),
        .out_addr(arb_addr), .out_len(arb_len),
        .out_port_id(arb_port), .out_qos(arb_qos)
    );

    // Address Mapper (decode in uclk domain)
    logic [`DDR5_ROW_W-1:0]  map_row;
    logic [`DDR5_BG_W-1:0]   map_bg;
    logic [`DDR5_BA_W-1:0]   map_ba;
    logic [`DDR5_COL_W-1:0]  map_col;
    logic [`DDR5_RANK_W-1:0] map_rank;
    logic                    map_sub_ch;

    ddr5_addr_mapper u_addr_map (
        .clk        (uclk),
        .rst_n      (uclk_rst_n),
        .axi_addr   (arb_addr),
        .row_addr   (map_row),
        .bg_addr    (map_bg),
        .bank_addr  (map_ba),
        .col_addr   (map_col),
        .rank_addr  (map_rank),
        .sub_channel(map_sub_ch),
        .map_mode   (addr_map_mode)
    );

    // map_* are pre-decoded for reference; the scheduler re-decodes per queue
    // entry and carries sub_channel through to the protocol FSM.
    // (map_sub_ch is driven by the addr_mapper .sub_channel output)

    // Command CDC FIFO (uclk -> cclk)
    // Packet: {qos[4], port[2], is_wr[1], len[8], addr[34], id[8]} = 57
    localparam int CMD_PKT_W = 4 + 2 + 1 + 8 + ADDR_W + ID_W;
    logic [CMD_PKT_W-1:0] cmd_din, cmd_dout;
    logic cmd_fifo_full, cmd_fifo_empty, cmd_fifo_rd_valid;

    assign cmd_din = {arb_qos, arb_port, arb_is_write, arb_len, arb_addr, arb_id};

    // arb_ready: deassert for 1 cycle after handshake to let cmd_fifo_full update
    logic arb_ready_r;
    always_ff @(posedge uclk or negedge uclk_rst_n) begin
        if (!uclk_rst_n)
            arb_ready_r <= 1'b1;
        else if (arb_valid & arb_ready_r)
            arb_ready_r <= 1'b0;  // Post-handshake: suppress for 1 cycle
        else
            arb_ready_r <= !cmd_fifo_full;
    end
    assign arb_ready = arb_ready_r;

    ddr5_cdc_fifo #(.DATA_W(CMD_PKT_W), .ADDR_W(4)) u_cmd_fifo (
        .wr_clk(uclk), .wr_rst_n(uclk_rst_n),
        .wr_en(arb_valid & arb_ready),
        .wr_data(cmd_din), .wr_full(cmd_fifo_full),
        .rd_clk(cclk), .rd_rst_n(cclk_rst_n),
        .rd_en(cmd_ready & !cmd_fifo_empty),
        .rd_data(cmd_dout), .rd_empty(cmd_fifo_empty),
        .rd_valid(cmd_fifo_rd_valid)
    );

    assign cmd_valid   = cmd_fifo_rd_valid;
    assign {cmd_qos, cmd_port_id, cmd_is_write, cmd_len, cmd_addr, cmd_id} = cmd_dout;

    // Write data passthrough (simplified - direct connection for now)
    assign wr_data_valid = s_axi_wvalid[0];
    assign wr_data       = s_axi_wdata[DATA_W-1:0];
    assign wr_strb       = s_axi_wstrb[STRB_W-1:0];
    assign wr_last       = s_axi_wlast[0];

    // Read data ready
    assign rd_data_ready = 1'b1;

endmodule
