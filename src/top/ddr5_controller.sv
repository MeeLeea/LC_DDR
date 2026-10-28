// =============================================================================
// Module: ddr5_controller
// Description: DDR5 Memory Controller IP Top-Level
//              Integrates UI(AXI4), CtrlCore, DFI Bridge, PHY Digital, Config
//              Protocol: JEDEC DDR5 (JESD79-5) + DFI 5.1
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_controller #(
    parameter int NUM_PORTS   = `AXI_NUM_PORTS,
    parameter int ID_W        = `AXI_ID_W,
    parameter int ADDR_W      = `AXI_ADDR_W,
    parameter int DATA_W      = `AXI_DATA_W,
    parameter int STRB_W      = `AXI_STRB_W,
    parameter int NUM_BANKS   = `DDR5_NUM_BANKS,
    parameter int QUEUE_DEPTH = 16,
    parameter int FREQ_RATIO  = 2,
    parameter int APB_ADDR_W  = `APB_ADDR_W,
    parameter int APB_DATA_W  = `APB_DATA_W
)(
    input  logic        uclk,
    input  logic        uclk_rst_n,
    input  logic        cclk,
    input  logic        cclk_rst_n,
    input  logic        dfi_clk,
    input  logic        phy_clk,

    // AXI4 Slave (4 ports, flattened) - uclk domain
    input  logic [NUM_PORTS*ID_W-1:0]     s_axi_awid,
    input  logic [NUM_PORTS*ADDR_W-1:0]   s_axi_awaddr,
    input  logic [NUM_PORTS*8-1:0]        s_axi_awlen,
    input  logic [NUM_PORTS*3-1:0]        s_axi_awsize,
    input  logic [NUM_PORTS*2-1:0]        s_axi_awburst,
    input  logic [NUM_PORTS*4-1:0]        s_axi_awcache,
    input  logic [NUM_PORTS*3-1:0]        s_axi_awprot,
    input  logic [NUM_PORTS*4-1:0]        s_axi_awqos,
    input  logic [NUM_PORTS-1:0]          s_axi_awlock,   // B-02: exclusive access
    input  logic [NUM_PORTS-1:0]          s_axi_awvalid,
    output logic [NUM_PORTS-1:0]          s_axi_awready,
    input  logic [NUM_PORTS*DATA_W-1:0]   s_axi_wdata,
    input  logic [NUM_PORTS*STRB_W-1:0]   s_axi_wstrb,
    input  logic [NUM_PORTS-1:0]          s_axi_wlast,
    input  logic [NUM_PORTS-1:0]          s_axi_wvalid,
    output logic [NUM_PORTS-1:0]          s_axi_wready,
    output logic [NUM_PORTS*ID_W-1:0]     s_axi_bid,
    output logic [NUM_PORTS*2-1:0]        s_axi_bresp,
    output logic [NUM_PORTS-1:0]          s_axi_bvalid,
    input  logic [NUM_PORTS-1:0]          s_axi_bready,
    input  logic [NUM_PORTS*ID_W-1:0]     s_axi_arid,
    input  logic [NUM_PORTS*ADDR_W-1:0]   s_axi_araddr,
    input  logic [NUM_PORTS*8-1:0]        s_axi_arlen,
    input  logic [NUM_PORTS*3-1:0]        s_axi_arsize,
    input  logic [NUM_PORTS*2-1:0]        s_axi_arburst,
    input  logic [NUM_PORTS*4-1:0]        s_axi_arcache,
    input  logic [NUM_PORTS*3-1:0]        s_axi_arprot,
    input  logic [NUM_PORTS*4-1:0]        s_axi_arqos,
    input  logic [NUM_PORTS-1:0]          s_axi_arlock,   // B-02: exclusive access
    input  logic [NUM_PORTS-1:0]          s_axi_arvalid,
    output logic [NUM_PORTS-1:0]          s_axi_arready,
    output logic [NUM_PORTS*ID_W-1:0]     s_axi_rid,
    output logic [NUM_PORTS*DATA_W-1:0]   s_axi_rdata,
    output logic [NUM_PORTS*2-1:0]        s_axi_rresp,
    output logic [NUM_PORTS-1:0]          s_axi_rlast,
    output logic [NUM_PORTS-1:0]          s_axi_rvalid,
    input  logic [NUM_PORTS-1:0]          s_axi_rready,

    // APB Configuration - cclk domain
    input  logic [APB_ADDR_W-1:0] paddr,
    input  logic [APB_DATA_W-1:0] pwdata,
    output logic [APB_DATA_W-1:0] prdata,
    input  logic                  psel,
    input  logic                  penable,
    input  logic                  pwrite,
    output logic                  pready,
    output logic                  pslverr,

    // Configuration Inputs - cclk domain
    input  logic [1:0]  addr_map_mode,
    input  logic [1:0]  cfg_freq_ratio,
    input  logic        cfg_dual_channel,

    // DLL Analog Interface - phy_clk domain
    input  logic        dll_phase_early,
    input  logic        dll_phase_late,

    // DDR5 Physical Pads - phy_clk domain
    output logic [31:0] ddr5_dq_out,
    input  logic [31:0] ddr5_dq_in,
    output logic [3:0]  ddr5_dqs_out,
    input  logic [3:0]  ddr5_dqs_in,
    output logic [17:0] ddr5_addr_out,
    output logic [5:0]  ddr5_bank_out,
    output logic [1:0]  ddr5_cs_n_out,
    output logic        ddr5_act_n_out,
    output logic        ddr5_ras_n_out,
    output logic        ddr5_cas_n_out,
    output logic        ddr5_we_n_out,
    output logic [1:0]  ddr5_cke_out,
    output logic [1:0]  ddr5_odt_out,
    output logic        ddr5_reset_n_out,

    // Interrupt - cclk domain
    output logic        irq
);

    // =========================================================================
    // Internal Wires: UI -> Ctrl Core (cclk domain)
    // =========================================================================
    logic              ui_cmd_valid, ui_cmd_ready, ui_cmd_is_write;
    logic [ID_W-1:0]   ui_cmd_id;
    logic [ADDR_W-1:0] ui_cmd_addr;
    logic [7:0]        ui_cmd_len;
    logic [1:0]        ui_cmd_port_id;
    logic [3:0]        ui_cmd_qos;
    logic              ui_wr_data_valid, ui_wr_data_ready, ui_wr_last;
    logic [DATA_W-1:0] ui_wr_data;
    logic [STRB_W-1:0] ui_wr_strb;
    logic [DATA_W-1:0] ui_rd_data;
    logic              ui_rd_data_valid, ui_rd_data_ready;
    logic [1:0]        ui_rd_port_id;
    logic [ID_W-1:0]   ui_rd_id;

    // Internal Wires: Ctrl Core -> DFI Bridge (cclk domain)
    logic        core_dfi_cmd_valid;
    logic [17:0] core_dfi_address;
    logic [5:0]  core_dfi_bank;
    logic [1:0]  core_dfi_cs_n;
    logic        core_dfi_act_n, core_dfi_ras_n, core_dfi_cas_n, core_dfi_we_n;
    logic [127:0] core_dfi_wrdata;
    logic [15:0]  core_dfi_wrdata_mask;
    logic         core_dfi_wrdata_en;
    logic [127:0] core_dfi_rddata;
    logic         core_dfi_rddata_valid;
    logic        core_ctrl_ready;
    logic [3:0]  core_ctrl_state, core_refresh_credit;
    logic        core_refresh_overflow, core_ecc_sbe, core_ecc_dbe;
    // B-03: deadlock prevention status from ctrl core
    logic        core_deadlock_detected;
    logic [15:0] core_deadlock_stall_count;

    // Internal Wires: DFI Bridge -> PHY (dfi_clk domain)
    logic        dfi_phy_cmd_valid, dfi_phy_cmd_ready;
    logic [17:0] dfi_phy_address;
    logic [5:0]  dfi_phy_bank;
    logic [1:0]  dfi_phy_cs_n;
    logic        dfi_phy_act_n, dfi_phy_ras_n, dfi_phy_cas_n, dfi_phy_we_n;
    logic [127:0] dfi_phy_wrdata;
    logic [15:0]  dfi_phy_wrdata_mask;
    logic         dfi_phy_wrdata_en;
    logic [127:0] dfi_phy_rddata;
    logic         dfi_phy_rddata_valid;
    logic        dfi_train_complete, dfi_train_error, dfi_phy_init_complete;
    logic        dfi_ctrl_cmd_ready;
    logic [127:0] dfi_ctrl_rddata;
    logic         dfi_ctrl_rddata_valid;
    // B-04: DFI 5.1 additional control/status signals (bridge <-> PHY)
    logic [`DFI_PHYCSEL_W-1:0]      dfi_phy_phycsel;
    logic [`DFI_PARITY_W-1:0]       dfi_phy_parity_in;
    logic [`DFI_DRAM_CLK_DIS_W-1:0] dfi_phy_dram_clk_disable;
    logic [`DFI_FREQ_RATIO_W-1:0]   dfi_phy_freq_ratio;
    logic [`DFI_RDDATA_DNV_W-1:0]   dfi_phy_rddata_dnv;

    // Internal Wires: PHY Digital outputs
    logic        phy_train_complete, phy_train_error;
    logic [2:0]  phy_cur_step;
    logic [7:0]  phy_progress_pct, phy_error_code;
    logic        phy_dll_locked;
    logic [7:0]  phy_dll_delay_code, phy_dll_lock_count;
    logic        phy_dll_lock_fail;
    logic        phy_ctrl_clk_en, phy_dfi_clk_en, phy_phy_clk_en;
    logic        phy_idle_detected, phy_clk_gated, phy_init_complete;

    // Internal Wires: Regfile outputs
    logic [15:0] cfg_tRCD, cfg_tRP, cfg_tRAS, cfg_tRC;
    logic [15:0] cfg_tRFC, cfg_tRFCsb, cfg_tREFI, cfg_tWR;
    logic [15:0] cfg_tRTP, cfg_CL, cfg_CWL;
    logic [15:0] cfg_tCCD_L, cfg_tCCD_S, cfg_tRRD_L, cfg_tRRD_S;
    logic [15:0] cfg_tFAW, cfg_tXS, cfg_tXP, cfg_tZQCAL, cfg_tZQCS;
    logic [1:0]  cfg_fgr_mode;
    logic        cfg_auto_ref_en, cfg_manual_ref, cfg_ecc_en, cfg_sreq_enter;
    logic        cfg_train_start, cfg_train_abort, cfg_dll_en, cfg_dll_reset;
    logic [2:0]  cfg_step_select;
    logic [15:0] cfg_timeout_ms;
    logic        cfg_cg_enable;
    logic [15:0] cfg_idle_threshold;

    // APB bridge to regfile wires
    logic              apb_reg_wr_en;
    logic [APB_ADDR_W-1:0] apb_reg_addr;
    logic [APB_DATA_W-1:0] apb_reg_wr_data;
    logic [APB_DATA_W-1:0] reg_rd_data;

    // =========================================================================
    // 1. User Interface Layer (AXI4 4-Port + CDC)
    // =========================================================================
    ddr5_ui_axi4 #(
        .NUM_PORTS (NUM_PORTS), .ID_W (ID_W),
        .ADDR_W (ADDR_W), .DATA_W (DATA_W), .STRB_W (STRB_W)
    ) u_ui (
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
        .cmd_valid(ui_cmd_valid), .cmd_ready(ui_cmd_ready),
        .cmd_is_write(ui_cmd_is_write), .cmd_id(ui_cmd_id),
        .cmd_addr(ui_cmd_addr), .cmd_len(ui_cmd_len),
        .cmd_port_id(ui_cmd_port_id), .cmd_qos(ui_cmd_qos),
        .wr_data_valid(ui_wr_data_valid), .wr_data_ready(ui_wr_data_ready),
        .wr_data(ui_wr_data), .wr_strb(ui_wr_strb), .wr_last(ui_wr_last),
        .rd_data(ui_rd_data), .rd_data_valid(ui_rd_data_valid),
        .rd_data_ready(ui_rd_data_ready),
        .rd_port_id(ui_rd_port_id), .rd_id(ui_rd_id),
        .addr_map_mode(addr_map_mode)
    );

    // =========================================================================
    // 2. Controller Core Layer
    // =========================================================================
    ddr5_ctrl_core #(
        .NUM_BANKS (NUM_BANKS), .QUEUE_DEPTH (QUEUE_DEPTH)
    ) u_ctrl (
        .clk(cclk), .rst_n(cclk_rst_n),
        .cmd_in_valid(ui_cmd_valid), .cmd_in_ready(ui_cmd_ready),
        .cmd_in_id(ui_cmd_id), .cmd_in_addr(ui_cmd_addr),
        .cmd_in_len(ui_cmd_len), .cmd_in_is_write(ui_cmd_is_write),
        .cmd_in_port_id(ui_cmd_port_id), .cmd_in_qos(ui_cmd_qos),
        .wr_data(ui_wr_data), .wr_strb(ui_wr_strb),
        .wr_data_valid(ui_wr_data_valid),
        .rd_data(ui_rd_data), .rd_data_valid(ui_rd_data_valid),
        .rd_port_id(ui_rd_port_id), .rd_id(ui_rd_id),
        .dfi_cmd_valid(core_dfi_cmd_valid),
        .dfi_address(core_dfi_address), .dfi_bank(core_dfi_bank),
        .dfi_cs_n(core_dfi_cs_n), .dfi_act_n(core_dfi_act_n),
        .dfi_ras_n(core_dfi_ras_n), .dfi_cas_n(core_dfi_cas_n),
        .dfi_we_n(core_dfi_we_n),
        .dfi_wrdata(core_dfi_wrdata),
        .dfi_wrdata_mask(core_dfi_wrdata_mask),
        .dfi_wrdata_en(core_dfi_wrdata_en),
        .dfi_rddata(dfi_ctrl_rddata),
        .dfi_rddata_valid(dfi_ctrl_rddata_valid),
        .cfg_tRCD(cfg_tRCD), .cfg_tRP(cfg_tRP),
        .cfg_tRAS(cfg_tRAS), .cfg_tRC(cfg_tRC),
        .cfg_tRFC(cfg_tRFC), .cfg_tRFCsb(cfg_tRFCsb),
        .cfg_tREFI(cfg_tREFI), .cfg_tWR(cfg_tWR),
        .cfg_tRTP(cfg_tRTP), .cfg_CL(cfg_CL), .cfg_CWL(cfg_CWL),
        .cfg_tCCD_L(cfg_tCCD_L), .cfg_tCCD_S(cfg_tCCD_S),
        .cfg_tRRD_L(cfg_tRRD_L), .cfg_tRRD_S(cfg_tRRD_S),
        .cfg_tFAW(cfg_tFAW), .cfg_tXS(cfg_tXS), .cfg_tXP(cfg_tXP),
        .cfg_tZQCAL(cfg_tZQCAL), .cfg_tZQCS(cfg_tZQCS),
        .cfg_fgr_mode(cfg_fgr_mode),
        .cfg_auto_ref_en(cfg_auto_ref_en),
        .cfg_manual_ref(cfg_manual_ref),
        .cfg_ecc_en(cfg_ecc_en), .cfg_sreq_enter(cfg_sreq_enter),
        .ctrl_ready(core_ctrl_ready),
        .ctrl_state(core_ctrl_state),
        .refresh_credit(core_refresh_credit),
        .refresh_overflow(core_refresh_overflow),
        .ecc_sbe_detect(core_ecc_sbe),
        .ecc_dbe_detect(core_ecc_dbe),
        .deadlock_detected(core_deadlock_detected),
        .deadlock_stall_count(core_deadlock_stall_count)
    );

    // =========================================================================
    // 3. DFI Bridge Layer
    // =========================================================================
    ddr5_dfi_bridge #(
        .FREQ_RATIO (FREQ_RATIO)
    ) u_dfi (
        .ctrl_clk(cclk), .dfi_clk(dfi_clk), .rst_n(cclk_rst_n),
        .ctrl_cmd_valid(core_dfi_cmd_valid),
        .ctrl_cmd_ready(dfi_ctrl_cmd_ready),
        .ctrl_address(core_dfi_address), .ctrl_bank(core_dfi_bank),
        .ctrl_cs_n(core_dfi_cs_n), .ctrl_act_n(core_dfi_act_n),
        .ctrl_ras_n(core_dfi_ras_n), .ctrl_cas_n(core_dfi_cas_n),
        .ctrl_we_n(core_dfi_we_n),
        .ctrl_wrdata(core_dfi_wrdata),
        .ctrl_wrdata_mask(core_dfi_wrdata_mask),
        .ctrl_wrdata_en(core_dfi_wrdata_en),
        .ctrl_rddata(dfi_ctrl_rddata),
        .ctrl_rddata_valid(dfi_ctrl_rddata_valid),
        .dfi_cmd_valid(dfi_phy_cmd_valid),
        .dfi_cmd_ready(dfi_phy_cmd_ready),
        .dfi_address(dfi_phy_address), .dfi_bank(dfi_phy_bank),
        .dfi_cs_n(dfi_phy_cs_n), .dfi_act_n(dfi_phy_act_n),
        .dfi_ras_n(dfi_phy_ras_n), .dfi_cas_n(dfi_phy_cas_n),
        .dfi_we_n(dfi_phy_we_n),
        .dfi_wrdata(dfi_phy_wrdata),
        .dfi_wrdata_mask(dfi_phy_wrdata_mask),
        .dfi_wrdata_en(dfi_phy_wrdata_en),
        .dfi_rddata(dfi_phy_rddata),
        .dfi_rddata_valid(dfi_phy_rddata_valid),
        .dfi_phycsel(dfi_phy_phycsel),
        .dfi_parity_in(dfi_phy_parity_in),
        .dfi_dram_clk_disable(dfi_phy_dram_clk_disable),
        .dfi_freq_ratio(dfi_phy_freq_ratio),
        .dfi_rddata_dnv(dfi_phy_rddata_dnv),
        .train_start(cfg_train_start),
        .train_complete(dfi_train_complete),
        .train_error(dfi_train_error),
        .phy_init_complete(phy_init_complete),
        .cfg_freq_ratio(cfg_freq_ratio),
        .cfg_dual_channel(cfg_dual_channel)
    );

    // =========================================================================
    // 4. PHY Digital Layer
    // =========================================================================
    ddr5_phy_digital #(
        .USER_W (DATA_W), .DFI_W (128),
        .DLL_BITS (`PHY_DLL_BITS), .NUM_STEPS (`PHY_TRAIN_STEPS)
    ) u_phy (
        .ctrl_clk(cclk), .dfi_clk(dfi_clk), .phy_clk(phy_clk),
        .rst_n(cclk_rst_n),
        .dfi_cmd_valid(dfi_phy_cmd_valid),
        .dfi_cmd_ready(dfi_phy_cmd_ready),
        .dfi_address(dfi_phy_address), .dfi_bank(dfi_phy_bank),
        .dfi_cs_n(dfi_phy_cs_n), .dfi_act_n(dfi_phy_act_n),
        .dfi_ras_n(dfi_phy_ras_n), .dfi_cas_n(dfi_phy_cas_n),
        .dfi_we_n(dfi_phy_we_n),
        .dfi_wrdata(dfi_phy_wrdata),
        .dfi_wrdata_mask(dfi_phy_wrdata_mask),
        .dfi_wrdata_en(dfi_phy_wrdata_en),
        .dfi_rddata(dfi_phy_rddata),
        .dfi_rddata_valid(dfi_phy_rddata_valid),
        .dfi_phycsel(dfi_phy_phycsel),
        .dfi_parity_in(dfi_phy_parity_in),
        .dfi_dram_clk_disable(dfi_phy_dram_clk_disable),
        .dfi_freq_ratio(dfi_phy_freq_ratio),
        .dfi_rddata_dnv(dfi_phy_rddata_dnv),
        .wr_user_valid(ui_wr_data_valid),
        .wr_user_data(ui_wr_data),
        .wr_user_ready(ui_wr_data_ready),
        .rd_user_valid(ui_rd_data_valid),
        .rd_user_data(ui_rd_data),
        .rd_user_ready(ui_rd_data_ready),
        .train_start(cfg_train_start),
        .train_abort(cfg_train_abort),
        .step_select(cfg_step_select),
        .timeout_ms(cfg_timeout_ms),
        .train_complete(phy_train_complete),
        .train_error(phy_train_error),
        .cur_step(phy_cur_step),
        .progress_pct(phy_progress_pct),
        .error_code(phy_error_code),
        .dll_en(cfg_dll_en), .dll_reset(cfg_dll_reset),
        .dll_locked(phy_dll_locked),
        .dll_delay_code(phy_dll_delay_code),
        .phase_early(dll_phase_early),
        .phase_late(dll_phase_late),
        .dll_lock_count(phy_dll_lock_count),
        .dll_lock_fail(phy_dll_lock_fail),
        .cg_enable(cfg_cg_enable),
        .idle_threshold(cfg_idle_threshold),
        .ctrl_clk_en(phy_ctrl_clk_en),
        .dfi_clk_en(phy_dfi_clk_en),
        .phy_clk_en(phy_phy_clk_en),
        .idle_detected(phy_idle_detected),
        .clk_gated(phy_clk_gated),
        .phy_init_complete(phy_init_complete),
        .dq_out(ddr5_dq_out), .dq_in(ddr5_dq_in),
        .dqs_out(ddr5_dqs_out), .dqs_in(ddr5_dqs_in),
        .addr_out(ddr5_addr_out), .bank_out(ddr5_bank_out),
        .cs_n_out(ddr5_cs_n_out), .act_n_out(ddr5_act_n_out),
        .ras_n_out(ddr5_ras_n_out), .cas_n_out(ddr5_cas_n_out),
        .we_n_out(ddr5_we_n_out),
        .cke_out(ddr5_cke_out), .odt_out(ddr5_odt_out),
        .reset_n_out(ddr5_reset_n_out)
    );

    // =========================================================================
    // 5. Configuration Layer (APB Bridge + Register File)
    // =========================================================================
    ddr5_cfg_apb #(
        .ADDR_W (APB_ADDR_W), .DATA_W (APB_DATA_W)
    ) u_apb (
        .clk(cclk), .rst_n(cclk_rst_n),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .pready(pready), .pslverr(pslverr),
        .reg_wr_en(apb_reg_wr_en),
        .reg_addr(apb_reg_addr),
        .reg_wr_data(apb_reg_wr_data),
        .reg_rd_data(reg_rd_data)
    );

    ddr5_regfile #(
        .ADDR_W (APB_ADDR_W), .DATA_W (APB_DATA_W)
    ) u_regfile (
        .clk(cclk), .rst_n(cclk_rst_n),
        .reg_wr_en(apb_reg_wr_en),
        .reg_addr(apb_reg_addr),
        .reg_wr_data(apb_reg_wr_data),
        .reg_rd_data(reg_rd_data),
        .tRCD(cfg_tRCD), .tRP(cfg_tRP),
        .tRAS(cfg_tRAS), .tRC(cfg_tRC),
        .tRFC(cfg_tRFC), .tRFCsb(cfg_tRFCsb),
        .tREFI(cfg_tREFI), .tWR(cfg_tWR),
        .tRTP(cfg_tRTP), .CL(cfg_CL), .CWL(cfg_CWL),
        .tCCD_L(cfg_tCCD_L), .tCCD_S(cfg_tCCD_S),
        .tRRD_L(cfg_tRRD_L), .tRRD_S(cfg_tRRD_S),
        .tFAW(cfg_tFAW), .tXS(cfg_tXS), .tXP(cfg_tXP),
        .tZQCAL(cfg_tZQCAL), .tZQCS(cfg_tZQCS),
        .fgr_mode(cfg_fgr_mode),
        .auto_ref_en(cfg_auto_ref_en),
        .manual_ref(cfg_manual_ref),
        .ecc_en(cfg_ecc_en), .sreq_enter(cfg_sreq_enter),
        .train_start(cfg_train_start),
        .train_abort(cfg_train_abort),
        .dll_en(cfg_dll_en), .dll_reset(cfg_dll_reset),
        .step_select(cfg_step_select),
        .timeout_ms(cfg_timeout_ms),
        .cg_enable(cfg_cg_enable),
        .idle_threshold(cfg_idle_threshold),
        .ctrl_state(core_ctrl_state),
        .ctrl_ready(core_ctrl_ready),
        .refresh_credit(core_refresh_credit),
        .refresh_overflow(core_refresh_overflow),
        .ecc_sbe_detect(core_ecc_sbe),
        .ecc_dbe_detect(core_ecc_dbe),
        .train_complete(phy_train_complete),
        .train_error(phy_train_error),
        .train_in_progress(phy_train_complete | phy_train_error),
        .train_cur_step(phy_cur_step),
        .train_progress_pct(phy_progress_pct),
        .train_error_code(phy_error_code),
        .dll_locked(phy_dll_locked),
        .dll_lock_fail(phy_dll_lock_fail),
        .dll_lock_count(phy_dll_lock_count),
        .idle_detected(phy_idle_detected),
        .clk_gated(phy_clk_gated)
    );

    // =========================================================================
    // 6. Interrupt Aggregation
    // =========================================================================
    assign irq = core_ecc_sbe | core_ecc_dbe
               | phy_train_complete | phy_train_error
               | core_refresh_overflow
               | core_deadlock_detected;   // B-03

endmodule
