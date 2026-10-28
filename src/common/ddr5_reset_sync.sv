// =============================================================================
// Module: ddr5_reset_sync
// Description: Async assert, sync deassert reset synchronizer
//              One instance per clock domain
// =============================================================================
module ddr5_reset_sync #(
    parameter int STAGES = 2
)(
    input  logic clk,
    input  logic async_rst_n,   // Active-low async reset
    output logic sync_rst_n     // Synchronized reset output
);

    logic [STAGES-1:0] sync_chain;

    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            sync_chain <= '0;
        end else begin
            sync_chain <= {sync_chain[STAGES-2:0], 1'b1};
        end
    end

    assign sync_rst_n = sync_chain[STAGES-1];

endmodule
