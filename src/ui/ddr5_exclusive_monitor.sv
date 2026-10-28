// =============================================================================
// Module: ddr5_exclusive_monitor
// Description: AXI4 Exclusive Access Monitor (per port)
//              Implements the AMBA AXI4 exclusive sequence:
//                - exclusive read  (ARLOCK=1) establishes a reservation
//                - exclusive write (AWLOCK=1) succeeds (EXOKAY) only if the
//                  reservation is still valid; otherwise OKAY (fail/retry)
//                - a write from another master to the reserved line clears
//                  the reservation (snoop_hit)
//              Resolves review blocking issue B-02.
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_exclusive_monitor #(
    parameter int ADDR_W = `AXI_ADDR_W
)(
    input  logic              clk,
    input  logic              rst_n,

    // AW channel (this port)
    input  logic [ADDR_W-1:0] awaddr,
    input  logic              awlock,      // 1 = exclusive access
    input  logic              awvalid,
    input  logic              awready,

    // AR channel (this port)
    input  logic [ADDR_W-1:0] araddr,
    input  logic              arlock,      // 1 = exclusive access
    input  logic              arvalid,
    input  logic              arready,

    // Exclusive-write grant: combinational, valid at AW handshake.
    // The slave latches this to drive BRESP = EXOKAY in its RESP state.
    output logic              ex_aw_ok,

    // Reservation state (exported for cross-port snoop in the UI top)
    output logic [ADDR_W-1:0] res_addr,
    output logic              res_valid,

    // Snoop: another port performed a write to this port's reserved line
    input  logic              snoop_hit
);

    wire aw_hs = awvalid & awready;
    wire ar_hs = arvalid & arready;

    logic [ADDR_W-1:0] res_addr_q;
    logic              res_valid_q;

    assign res_addr  = res_addr_q;
    assign res_valid = res_valid_q;

    // Reservation tracking register.
    // Priority: this port's own events first, then external snoop clear.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            res_valid_q <= 1'b0;
            res_addr_q  <= '0;
        end else begin
            if (ar_hs & arlock) begin
                // Exclusive read -> establish reservation
                res_valid_q <= 1'b1;
                res_addr_q  <= araddr;
            end else if (aw_hs) begin
                // Any write by this port consumes/clears the reservation
                res_valid_q <= 1'b0;
            end else if (snoop_hit) begin
                // Another master wrote the reserved line -> invalidate
                res_valid_q <= 1'b0;
            end
        end
    end

    // Exclusive write succeeds only when a matching reservation is live.
    assign ex_aw_ok = aw_hs & awlock & res_valid_q & (awaddr == res_addr_q);

endmodule
