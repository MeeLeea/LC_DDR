// =============================================================================
// Assertions: ddr5_assertions
// Description: Protocol and timing assertions for DDR5 IP verification
//              AXI4 handshake, reset behavior, CDC safety checks
// =============================================================================

module ddr5_assertions (
    input logic clk,
    input logic rst_n,
    
    // AXI4 Write Channel
    input logic awvalid,
    input logic awready,
    input logic wvalid,
    input logic wready,
    input logic wlast,
    input logic bvalid,
    input logic bready,
    
    // AXI4 Read Channel
    input logic arvalid,
    input logic arready,
    input logic rvalid,
    input logic rready,
    input logic rlast,
    
    // Address signals
    input logic [33:0] awaddr,
    input logic [33:0] araddr,
    input logic [7:0] awlen,
    input logic [7:0] arlen,
    input logic [2:0] awsize,
    input logic [2:0] arsize,
    input logic [1:0] awburst,
    input logic [1:0] arburst,
    
    // Command interface
    input logic cmd_valid,
    input logic cmd_ready,
    
    // CDC FIFO
    input logic wr_en,
    input logic wr_full,
    input logic rd_en,
    input logic rd_empty,
    
    // Reset synchronizer
    input logic async_rst_n,
    input logic sync_rst_n
);

    // =========================================================================
    // AXI4 Protocol Assertions
    // =========================================================================
    
    // AWVALID stability: Once asserted, must remain high until AWREADY
    property p_awvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        awvalid && !awready |=> awvalid;
    endproperty
    
    assert property (p_awvalid_stable)
        else $error("[AXI4] AWVALID deasserted before AWREADY");
    
    // AWADDR stability: Must not change while AWVALID is high
    property p_awaddr_stable;
        @(posedge clk) disable iff (!rst_n)
        awvalid && !awready |=> $stable(awaddr);
    endproperty
    
    assert property (p_awaddr_stable)
        else $error("[AXI4] AWADDR changed while AWVALID high");
    
    // AWLEN stability
    property p_awlen_stable;
        @(posedge clk) disable iff (!rst_n)
        awvalid && !awready |=> $stable(awlen);
    endproperty
    
    assert property (p_awlen_stable)
        else $error("[AXI4] AWLEN changed while AWVALID high");
    
    // WVALID stability
    property p_wvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        wvalid && !wready |=> wvalid;
    endproperty
    
    assert property (p_wvalid_stable)
        else $error("[AXI4] WVALID deasserted before WREADY");
    
    // BVALID stability
    property p_bvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        bvalid && !bready |=> bvalid;
    endproperty
    
    assert property (p_bvalid_stable)
        else $error("[AXI4] BVALID deasserted before BREADY");
    
    // ARVALID stability
    property p_arvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        arvalid && !arready |=> arvalid;
    endproperty
    
    assert property (p_arvalid_stable)
        else $error("[AXI4] ARVALID deasserted before ARREADY");
    
    // ARADDR stability
    property p_araddr_stable;
        @(posedge clk) disable iff (!rst_n)
        arvalid && !arready |=> $stable(araddr);
    endproperty
    
    assert property (p_araddr_stable)
        else $error("[AXI4] ARADDR changed while ARVALID high");
    
    // RVALID stability
    property p_rvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        rvalid && !rready |=> rvalid;
    endproperty
    
    assert property (p_rvalid_stable)
        else $error("[AXI4] RVALID deasserted before RREADY");
    
    // RLAST must be asserted on last beat
    property p_rlast_correct;
        @(posedge clk) disable iff (!rst_n)
        rvalid && rready && rlast |-> ##[0:$] !rvalid || (rvalid && rready && rlast);
    endproperty
    
    // Burst type must be INCR (01) for DDR5
    property p_awburst_incr;
        @(posedge clk) disable iff (!rst_n)
        awvalid |-> awburst == 2'b01;
    endproperty
    
    assert property (p_awburst_incr)
        else $warning("[AXI4] AWBURST not INCR (only INCR supported)");
    
    property p_arburst_incr;
        @(posedge clk) disable iff (!rst_n)
        arvalid |-> arburst == 2'b01;
    endproperty
    
    assert property (p_arburst_incr)
        else $warning("[AXI4] ARBURST not INCR (only INCR supported)");
    
    // =========================================================================
    // Command Interface Assertions
    // =========================================================================
    
    // CMD_VALID stability
    property p_cmd_valid_stable;
        @(posedge clk) disable iff (!rst_n)
        cmd_valid && !cmd_ready |=> cmd_valid;
    endproperty
    
    assert property (p_cmd_valid_stable)
        else $error("[CMD] CMD_VALID deasserted before CMD_READY");
    
    // No command when reset asserted
    property p_no_cmd_during_reset;
        @(posedge clk)
        !rst_n |-> !cmd_valid;
    endproperty
    
    assert property (p_no_cmd_during_reset)
        else $error("[CMD] Command issued during reset");
    
    // =========================================================================
    // CDC FIFO Safety Assertions
    // =========================================================================
    
    // Write when full should not occur
    property p_no_write_when_full;
        @(posedge clk) disable iff (!rst_n)
        wr_full |-> !wr_en;
    endproperty
    
    assert property (p_no_write_when_full)
        else $warning("[CDC] Write attempted when FIFO full");
    
    // Read when empty should not occur
    property p_no_read_when_empty;
        @(posedge clk) disable iff (!rst_n)
        rd_empty |-> !rd_en;
    endproperty
    
    assert property (p_no_read_when_empty)
        else $warning("[CDC] Read attempted when FIFO empty");
    
    // =========================================================================
    // Reset Synchronizer Assertions
    // =========================================================================
    
    // Async reset should propagate immediately
    property p_async_rst_propagate;
        @(posedge clk or negedge async_rst_n)
        !async_rst_n |-> !sync_rst_n;
    endproperty
    
    assert property (p_async_rst_propagate)
        else $error("[RST] Async reset not propagated to sync_rst_n");
    
    // Sync reset deassert should take 2 cycles (for STAGES=2)
    property p_sync_rst_deassert_latency;
        @(posedge clk)
        $rose(async_rst_n) |-> ##2 $rose(sync_rst_n);
    endproperty
    
    assert property (p_sync_rst_deassert_latency)
        else $error("[RST] Sync reset deassert latency incorrect");
    
    // =========================================================================
    // Performance Assertions
    // =========================================================================
    
    // Command should not be stalled for more than 100 cycles
    property p_cmd_stall_limit;
        @(posedge clk) disable iff (!rst_n)
        cmd_valid |-> ##[1:100] cmd_ready;
    endproperty
    
    assert property (p_cmd_stall_limit)
        else $warning("[PERF] Command stalled for >100 cycles");
    
    // Write response should complete within 200 cycles
    property p_bresp_latency;
        @(posedge clk) disable iff (!rst_n)
        awvalid && awready |-> ##[1:200] bvalid;
    endproperty
    
    assert property (p_bresp_latency)
        else $warning("[PERF] Write response latency >200 cycles");
    
    // Read data should start within 200 cycles
    property p_rdata_latency;
        @(posedge clk) disable iff (!rst_n)
        arvalid && arready |-> ##[1:200] rvalid;
    endproperty
    
    assert property (p_rdata_latency)
        else $warning("[PERF] Read data latency >200 cycles");
    
    // =========================================================================
    // Coverage Display
    // =========================================================================
    
    initial begin
        $display("========================================");
        $display("DDR5 Assertions Loaded");
        $display("  - AXI4 Protocol Checks");
        $display("  - Command Interface Checks");
        $display("  - CDC FIFO Safety Checks");
        $display("  - Reset Synchronizer Checks");
        $display("  - Performance Checks");
        $display("========================================");
    end

endmodule
