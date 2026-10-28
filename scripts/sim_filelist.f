# =============================================================================
# sim_filelist.f  ——  Xsim 仿真源文件清单 (filelist 驱动, 符合 rtl_verification/AGENT.md)
# 用法: 由 scripts/start.tcl 通过 `xvlog -f` 一次性编译; 禁止脚本自行编造此列表。
# 路径相对于仿真工程根目录 (D:\work\tests\ddr); 以 # 开头为注释, 空行忽略。
# 注意: .svh 属 include 文件, 不需在此列出 (由 start.tcl 的 -i ./src 处理)。
# =============================================================================

# ---------------- 综合 RTL (design sources) ----------------
src/common/ddr5_reset_sync.sv
src/common/ddr5_cdc_fifo.sv
src/common/ddr5_clk_gate.sv
src/cfg/ddr5_cfg_apb.sv
src/cfg/ddr5_regfile.sv
src/ctrl/ddr5_bank_manager.sv
src/ctrl/ddr5_cmd_scheduler.sv
src/ctrl/ddr5_ctrl_core.sv
src/ctrl/ddr5_ecc_engine.sv
src/ctrl/ddr5_protocol_fsm.sv
src/ctrl/ddr5_refresh_ctrl.sv
src/ctrl/ddr5_timing_engine.sv
src/dfi/ddr5_dfi_bridge.sv
src/phy/ddr5_clk_gate_ctrl.sv
src/phy/ddr5_dll_ctrl.sv
src/phy/ddr5_gearbox.sv
src/phy/ddr5_phy_digital.sv
src/phy/ddr5_training_engine.sv
src/top/ddr5_controller.sv
src/ui/ddr5_addr_mapper.sv
src/ui/ddr5_axi4_rd_slave.sv
src/ui/ddr5_axi4_wr_slave.sv
src/ui/ddr5_cmd_arbiter.sv
src/ui/ddr5_exclusive_monitor.sv
src/ui/ddr5_ui_axi4.sv
src/ctrl/ddr5_deadlock_monitor.sv

# ---------------- 仿真 TB / 环境文件 (sim/test) ----------------
test/tb_ddr5_reset_sync.sv
test/tb_ddr5_cdc_fifo.sv
test/tb_ddr5_clk_gate.sv
test/tb_ddr5_addr_mapper.sv
test/tb_ddr5_cmd_arbiter.sv
test/tb_ddr5_axi4_wr_slave.sv
test/tb_ddr5_axi4_rd_slave.sv
test/tb_ddr5_ui_top.sv
test/tb_ddr5_cfg_apb.sv
test/tb_ddr5_ui_axi4.sv
test/tb_ddr5_controller.sv
test/tb_ddr5_bank_manager.sv
test/tb_ddr5_cmd_scheduler.sv
test/tb_ddr5_ctrl_core.sv
test/tb_ddr5_deadlock_monitor.sv
test/tb_ddr5_dfi_bridge.sv
test/tb_ddr5_dll_ctrl.sv
test/tb_ddr5_ecc_engine.sv
test/tb_ddr5_exclusive_monitor.sv
test/tb_ddr5_gearbox.sv
test/tb_ddr5_protocol_fsm.sv
test/tb_ddr5_refresh_ctrl.sv
test/tb_ddr5_timing_engine.sv
test/ddr5_covergroups.sv
test/ddr5_assertions.sv

