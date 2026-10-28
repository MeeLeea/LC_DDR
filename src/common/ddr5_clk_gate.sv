// =============================================================================
// Module: ddr5_clk_gate
// Description: Integrated Clock Gating Cell (ICG) wrapper
//              Latch-based glitch-free clock gating
// =============================================================================
module ddr5_clk_gate (
    input  logic clk_in,
    input  logic en,        // Clock enable (active high)
    input  logic test_en,   // Test mode enable (bypass gating)
    output logic clk_out
);

    logic en_latch;
    logic en_sync;

    // Synchronize enable signal to avoid glitches
    always_ff @(posedge clk_in) begin
        en_sync <= en | test_en;
    end

    // Latch-based glitch-free gating
    always_latch begin
        if (!clk_in) begin
            en_latch = en_sync;
        end
    end

    assign clk_out = clk_in & en_latch;

endmodule
