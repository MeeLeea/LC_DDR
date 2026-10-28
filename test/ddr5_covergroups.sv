// =============================================================================
// Covergroup library: ddr5_covergroups.sv
// Description: Functional coverage definitions for DDR5 IP verification.
//              Adapted for Vivado Xsim (covergroups declared INSIDE a module,
//              all sampled signals declared as module-level ports).
//
// 用法: 本文件提供 `ddr5_coverage_collector` 模块, 其 covergroup 的采样信号
//       以 input 端口形式暴露。集成方式二选一:
//         (a) 在 tb 中实例化 ddr5_coverage_collector 并把 DUT/接口信号连到端口;
//         (b) 直接把本文件内的 covergroup 段落复制到具体 tb 的 module 内,
//             用 tb 已有的信号名替换端口名。
//       未连接端口时 covergroup 仍可编译/elaborate, 采样值恒为 X -> 不计覆盖。
//
// 历史问题: 原版本把 covergroup 放在文件作用域(module 外)并引用未声明信号,
//          xvlog 报 VRFC 10-2989 'xxx' is not declared, 整个文件无法编译。
// =============================================================================
`timescale 1ns / 1ps

module ddr5_coverage_collector;

    // ---- 采样时钟 ----
    logic        clk;          // user / core 域时钟
    logic        clk_in;       // 门控前时钟 (cg_clk_gate)
    logic        wr_clk;       // CDC FIFO 写域时钟

    // ---- AXI4 写通道 ----
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [7:0]  awid;
    logic [3:0]  awqos;
    logic        awvalid;
    logic        awready;

    // ---- AXI4 读通道 ----
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [7:0]  arid;
    logic [3:0]  arqos;

    // ---- 命令仲裁器 ----
    logic [1:0]  out_port_id;
    logic        out_is_write;
    logic [3:0]  out_qos;

    // ---- 地址映射 ----
    logic [2:0]  bg_addr;
    logic [2:0]  bank_addr;
    logic [1:0]  rank_addr;
    logic [15:0] row_addr;
    logic [8:0]  col_addr;
    logic        sub_channel;   // B-05 新增

    // ---- CDC FIFO ----
    localparam int DEPTH = 16;
    logic [4:0]  wr_count;
    logic        wr_full;

    // ---- 复位同步器 ----
    logic        async_rst_n;
    logic        sync_rst_n;

    // ---- 时钟门控 ----
    logic        en;
    logic        test_en;
    logic        clk_out;

    // =====================================================================
    // Coverage for AXI4 Write Channel
    // =====================================================================
    covergroup cg_axi4_wr @(posedge clk);
        cp_awlen: coverpoint awlen {
            bins w_single    = {0};
            bins w_burst_4   = {3};
            bins w_burst_8   = {7};
            bins w_burst_16  = {15};
            bins w_burst_32  = {31};
            bins w_burst_64  = {63};
            bins w_burst_128 = {127};
            bins w_burst_256 = {255};
        }
        cp_awsize: coverpoint awsize {
            bins w_b_byte     = {0};
            bins w_halfword   = {1};
            bins w_word       = {2};
            bins w_dword      = {3};
            bins w_qword      = {4};
            bins w_cache_line = {5};
        }
        cp_awid: coverpoint awid {
            bins w_low_ids[]  = {[0:15]};
            bins w_mid_ids[]  = {[16:127]};
            bins w_high_ids[] = {[128:255]};
        }
        cp_awqos: coverpoint awqos {
            bins w_low      = {[0:3]};
            bins w_med      = {[4:7]};
            bins w_high     = {[8:11]};
            bins w_critical = {[12:15]};
        }
        cx_w_len_size: cross cp_awlen, cp_awsize;
        cx_w_id_qos:   cross cp_awid,  cp_awqos;
    endgroup

    // =====================================================================
    // Coverage for AXI4 Read Channel
    // =====================================================================
    covergroup cg_axi4_rd @(posedge clk);
        cp_arlen: coverpoint arlen {
            bins r_single    = {0};
            bins r_burst_4   = {3};
            bins r_burst_8   = {7};
            bins r_burst_16  = {15};
            bins r_burst_32  = {31};
            bins r_burst_64  = {63};
            bins r_burst_128 = {127};
            bins r_burst_256 = {255};
        }
        cp_arsize: coverpoint arsize {
            bins r_b_byte     = {0};
            bins r_halfword   = {1};
            bins r_word       = {2};
            bins r_dword      = {3};
            bins r_qword      = {4};
            bins r_cache_line = {5};
        }
        cp_arid: coverpoint arid {
            bins r_low_ids[]  = {[0:15]};
            bins r_mid_ids[]  = {[16:127]};
            bins r_high_ids[] = {[128:255]};
        }
        cp_arqos: coverpoint arqos {
            bins r_low      = {[0:3]};
            bins r_med      = {[4:7]};
            bins r_high     = {[8:11]};
            bins r_critical = {[12:15]};
        }
        cx_r_len_size: cross cp_arlen, cp_arsize;
        cx_r_id_qos:   cross cp_arid,  cp_arqos;
    endgroup

    // =====================================================================
    // Coverage for Command Arbiter
    // =====================================================================
    covergroup cg_cmd_arbiter @(posedge clk);
        cp_out_port: coverpoint out_port_id {
            bins arb_port_0 = {0};
            bins arb_port_1 = {1};
            bins arb_port_2 = {2};
            bins arb_port_3 = {3};
        }
        cp_cmd_type: coverpoint out_is_write {
            bins arb_read  = {0};
            bins arb_write = {1};
        }
        cp_out_qos: coverpoint out_qos {
            bins arb_low      = {[0:3]};
            bins arb_med      = {[4:7]};
            bins arb_high     = {[8:11]};
            bins arb_critical = {[12:15]};
        }
        cx_port_cmd: cross cp_out_port, cp_cmd_type;
        cx_port_qos: cross cp_out_port, cp_out_qos;
    endgroup

    // =====================================================================
    // Coverage for Address Mapper (含 B-05 sub_channel)
    // =====================================================================
    covergroup cg_addr_mapper @(posedge clk);
        cp_bg: coverpoint bg_addr {
            bins map_bg0 = {0}; bins map_bg1 = {1};
            bins map_bg2 = {2}; bins map_bg3 = {3};
            bins map_bg4 = {4}; bins map_bg5 = {5};
            bins map_bg6 = {6}; bins map_bg7 = {7};
        }
        cp_ba: coverpoint bank_addr {
            bins map_bank0 = {0}; bins map_bank1 = {1};
            bins map_bank2 = {2}; bins map_bank3 = {3};
            bins map_bank4 = {4}; bins map_bank5 = {5};
            bins map_bank6 = {6}; bins map_bank7 = {7};
        }
        cp_rank: coverpoint rank_addr {
            bins map_rank0 = {0}; bins map_rank1 = {1};
            bins map_rank2 = {2}; bins map_rank3 = {3};
        }
        cp_row: coverpoint row_addr {
            bins map_low_rows  = {[16'h0000:16'h3FFF]};
            bins map_mid_rows  = {[16'h4000:16'hBFFF]};
            bins map_high_rows = {[16'hC000:16'hFFFF]};
        }
        cp_col: coverpoint col_addr {
            bins map_low_cols  = {[9'h000:9'h07F]};
            bins map_mid_cols  = {[9'h080:9'h0FF]};
            bins map_high_cols = {[9'h100:9'h1FF]};
        }
        // B-05: 子通道必须两个取值都被覆盖
        cp_sub_ch: coverpoint sub_channel {
            bins map_subch0 = {0};
            bins map_subch1 = {1};
        }
        cx_bg_bank:  cross cp_bg,   cp_ba;
        cx_rank_bg:  cross cp_rank, cp_bg;
        cx_subch_bg: cross cp_sub_ch, cp_bg;
    endgroup

    // =====================================================================
    // Coverage for CDC FIFO
    // =====================================================================
    covergroup cg_cdc_fifo @(posedge wr_clk);
        cp_wr_fullness: coverpoint wr_count {
            bins fifo_empty    = {0};
            bins fifo_quarter  = {[1:(DEPTH/4)]};
            bins fifo_half     = {[(DEPTH/4+1):(DEPTH/2)]};
            bins fifo_3quarter = {[(DEPTH/2+1):(3*DEPTH/4)]};
            bins fifo_afull    = {[(3*DEPTH/4+1):(DEPTH-1)]};
            bins fifo_full     = {DEPTH};
        }
        cp_wr_when_full: coverpoint wr_full {
            bins fifo_not_full = {0};
            bins fifo_is_full  = {1};
        }
        cx_wr_fullness: cross cp_wr_fullness, cp_wr_when_full;
    endgroup

    // =====================================================================
    // Coverage for Reset Synchronizer
    // =====================================================================
    covergroup cg_reset_sync @(posedge clk);
        cp_async_rst: coverpoint async_rst_n {
            bins rst_async_asserted   = {0};
            bins rst_async_deasserted = {1};
        }
        cp_sync_rst: coverpoint sync_rst_n {
            bins rst_sync_asserted   = {0};
            bins rst_sync_deasserted = {1};
        }
        cp_async_trans: coverpoint async_rst_n {
            bins rst_async_a_trans   = (1 => 0);
            bins rst_async_dea_trans = (0 => 1);
        }
        cp_sync_trans: coverpoint sync_rst_n {
            bins rst_sync_a_trans   = (1 => 0);
            bins rst_sync_dea_trans = (0 => 1);
        }
    endgroup

    // =====================================================================
    // Coverage for Clock Gating
    // =====================================================================
    covergroup cg_clk_gate @(posedge clk_in);
        cp_en: coverpoint en {
            bins cg_disabled = {0};
            bins cg_enabled  = {1};
        }
        cp_test_en: coverpoint test_en {
            bins cg_normal = {0};
            bins cg_test   = {1};
        }
        cp_clk_out: coverpoint clk_out {
            bins cg_out_low  = {0};
            bins cg_out_high = {1};
        }
        cp_en_trans: coverpoint en {
            bins cg_disable_trans = (1 => 0);
            bins cg_enable_trans  = (0 => 1);
        }
        cx_en_test: cross cp_en, cp_test_en;
    endgroup

    // =====================================================================
    // Coverage for Deadlock Monitor (B-03 新增)
    // =====================================================================
    logic        cmd_in_valid;
    logic        cmd_in_ready;
    logic        ref_req;
    logic        ref_ack;
    logic        deadlock_detected;
    logic [15:0] stall_count;

    covergroup cg_deadlock @(posedge clk);
        // 反压组合: valid 高但 ready 低 = 停滞
        cp_stall: coverpoint (cmd_in_valid && !cmd_in_ready) {
            bins dl_running = {0};
            bins dl_stalled = {1};
        }
        cp_ref_handshake: coverpoint (ref_req && ref_ack) {
            bins dl_ref_idle = {0};
            bins dl_ref_done = {1};
        }
        cp_detected: coverpoint deadlock_detected {
            bins dl_clear = {0};
            bins dl_flag  = {1};
        }
        cp_stall_mag: coverpoint stall_count {
            bins dl_s_zero  = {0};
            bins dl_s_small = {[1:16'h03FF]};
            bins dl_s_large = {[16'h0400:$]};
        }
        cx_stall_detect: cross cp_stall, cp_detected;
    endgroup

    // =====================================================================
    // Coverage for Gearbox 2:1 拆分 (B-01 新增)
    // =====================================================================
    logic        gb_valid;
    logic        gb_phase;      // DFI 相位 0/1
    logic        gb_last;

    covergroup cg_gearbox @(posedge clk);
        cp_phase: coverpoint gb_phase {
            bins gb_ph0 = {0};
            bins gb_ph1 = {1};
        }
        cp_valid: coverpoint gb_valid {
            bins gb_idle = {0};
            bins gb_act  = {1};
        }
        cp_last: coverpoint gb_last {
            bins gb_not_last = {0};
            bins gb_is_last  = {1};
        }
        cx_ph_valid: cross cp_phase, cp_valid;
        cx_ph_last:  cross cp_phase, cp_last;
    endgroup

    // =====================================================================
    // Coverage for AXI4 Exclusive Access (B-02 新增)
    // =====================================================================
    logic        awlock;
    logic        arlock;
    logic        res_valid;
    logic [1:0]  bresp;
    logic [1:0]  rresp;

    covergroup cg_exclusive @(posedge clk);
        cp_awlock: coverpoint awlock {
            bins ex_aw_normal = {0};
            bins ex_aw_excl   = {1};
        }
        cp_arlock: coverpoint arlock {
            bins ex_ar_normal = {0};
            bins ex_ar_excl   = {1};
        }
        cp_reservation: coverpoint res_valid {
            bins ex_res_free = {0};
            bins ex_res_held = {1};
        }
        cp_bresp: coverpoint bresp {
            bins ex_b_okay   = {2'b00};
            bins ex_b_exokay = {2'b01};
            bins ex_b_slverr = {2'b10};
            bins ex_b_decerr = {2'b11};
        }
        cp_rresp: coverpoint rresp {
            bins ex_r_okay   = {2'b00};
            bins ex_r_exokay = {2'b01};
            bins ex_r_slverr = {2'b10};
            bins ex_r_decerr = {2'b11};
        }
        cx_awlock_res: cross cp_awlock, cp_reservation;
        cx_arlock_res: cross cp_arlock, cp_reservation;
    endgroup

    // =====================================================================
    // Covergroup 实例化
    // =====================================================================
    cg_axi4_wr        cov_axi4_wr;
    cg_axi4_rd        cov_axi4_rd;
    cg_cmd_arbiter    cov_cmd_arb;
    cg_addr_mapper    cov_addr_map;
    cg_cdc_fifo       cov_cdc_fifo;
    cg_reset_sync     cov_rst_sync;
    cg_clk_gate       cov_clk_gate;
    cg_deadlock       cov_deadlock;
    cg_gearbox        cov_gearbox;
    cg_exclusive      cov_exclusive;

    initial begin
        cov_axi4_wr   = new();
        cov_axi4_rd   = new();
        cov_cmd_arb   = new();
        cov_addr_map  = new();
        cov_cdc_fifo  = new();
        cov_rst_sync  = new();
        cov_clk_gate  = new();
        cov_deadlock  = new();
        cov_gearbox   = new();
        cov_exclusive = new();
    end

    // 覆盖率汇总打印 (Xsim 下精确数据以 coverage report / .ucdb 为准)
    task automatic report_cov();
        $display("\n========================================");
        $display("Functional Coverage - per-instance percent");
        $display("========================================");
        $display("AXI4 Write      : %0.2f%%", cov_axi4_wr.get_inst_coverage());
        $display("AXI4 Read       : %0.2f%%", cov_axi4_rd.get_inst_coverage());
        $display("Cmd Arbiter     : %0.2f%%", cov_cmd_arb.get_inst_coverage());
        $display("Addr Mapper     : %0.2f%%", cov_addr_map.get_inst_coverage());
        $display("CDC FIFO        : %0.2f%%", cov_cdc_fifo.get_inst_coverage());
        $display("Reset Sync      : %0.2f%%", cov_rst_sync.get_inst_coverage());
        $display("Clock Gate      : %0.2f%%", cov_clk_gate.get_inst_coverage());
        $display("Deadlock Mon    : %0.2f%%", cov_deadlock.get_inst_coverage());
        $display("Gearbox         : %0.2f%%", cov_gearbox.get_inst_coverage());
        $display("Exclusive Acc   : %0.2f%%", cov_exclusive.get_inst_coverage());
        $display("========================================");
    endtask

endmodule
