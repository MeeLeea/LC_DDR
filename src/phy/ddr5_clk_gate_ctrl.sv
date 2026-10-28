// =============================================================================
// Module: ddr5_clk_gate_ctrl
// Description: Clock gating control for PHY power management
//              Monitors idle conditions and gates clocks when inactive
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_clk_gate_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    // Activity indicators
    input  logic        cmd_active,
    input  logic        data_active,
    input  logic        train_active,
    input  logic        sreq_active,

    // Configuration
    input  logic        cg_enable,      // Clock gating enable
    input  logic [15:0] idle_threshold, // Idle cycle count before gating

    // Clock gate control outputs
    output logic        ctrl_clk_en,
    output logic        dfi_clk_en,
    output logic        phy_clk_en,

    // Status
    output logic        idle_detected,
    output logic        clk_gated
);

    // Idle counter
    logic [15:0] idle_cnt;
    logic        idle_flag;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idle_cnt  <= '0;
            idle_flag <= 1'b0;
        end else if (!cg_enable || sreq_active) begin
            idle_cnt  <= '0;
            idle_flag <= 1'b0;
        end else if (cmd_active || data_active || train_active) begin
            idle_cnt  <= '0;
            idle_flag <= 1'b0;
        end else begin
            if (idle_cnt < idle_threshold) begin
                idle_cnt <= idle_cnt + 16'd1;
            end else begin
                idle_flag <= 1'b1;
            end
        end
    end

    assign idle_detected = idle_flag;

    // Clock gate enables
    // ctrl_clk: gate when idle and no pending commands
    assign ctrl_clk_en = !idle_flag || cmd_active;

    // dfi_clk: gate only in self-refresh mode
    assign dfi_clk_en = !sreq_active;

    // phy_clk: gate only in self-refresh mode
    assign phy_clk_en = !sreq_active;

    assign clk_gated = idle_flag && cg_enable;

endmodule
