// =============================================================================
// DDR5 Memory Controller IP - Synthesis Filelist
// =============================================================================

// Include directories
+incdir+./src

// Header files
./src/ddr5_defines.svh

// Common modules
./src/common/ddr5_reset_sync.sv
./src/common/ddr5_cdc_fifo.sv
./src/common/ddr5_clk_gate.sv

// User Interface Layer
./src/ui/ddr5_addr_mapper.sv
./src/ui/ddr5_cmd_arbiter.sv
./src/ui/ddr5_axi4_wr_slave.sv
./src/ui/ddr5_axi4_rd_slave.sv
./src/ui/ddr5_exclusive_monitor.sv
./src/ui/ddr5_ui_axi4.sv

// Controller Core Layer
./src/ctrl/ddr5_timing_engine.sv
./src/ctrl/ddr5_bank_manager.sv
./src/ctrl/ddr5_refresh_ctrl.sv
./src/ctrl/ddr5_protocol_fsm.sv
./src/ctrl/ddr5_cmd_scheduler.sv
./src/ctrl/ddr5_deadlock_monitor.sv
./src/ctrl/ddr5_ecc_engine.sv
./src/ctrl/ddr5_ctrl_core.sv

// DFI Bridge Layer
./src/dfi/ddr5_dfi_bridge.sv

// PHY Digital Layer
./src/phy/ddr5_dll_ctrl.sv
./src/phy/ddr5_training_engine.sv
./src/phy/ddr5_gearbox.sv
./src/phy/ddr5_clk_gate_ctrl.sv
./src/phy/ddr5_phy_digital.sv

// Configuration Layer
./src/cfg/ddr5_regfile.sv
./src/cfg/ddr5_cfg_apb.sv

// Top Level
./src/top/ddr5_controller.sv
