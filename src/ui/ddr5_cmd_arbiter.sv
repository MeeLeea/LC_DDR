// =============================================================================
// Module: ddr5_cmd_arbiter
// Description: 4-port command arbiter with WRR + Strict Priority
//              Port 0 = CPU (Strict High Priority)
//              Port 1 = DMA   (WRR weight=4)
//              Port 2 = Accel (WRR weight=8)
//              Port 3 = Debug (WRR weight=1)
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_cmd_arbiter #(
    parameter int NUM_PORTS = `AXI_NUM_PORTS,
    parameter int ID_W      = `AXI_ID_W,
    parameter int ADDR_W    = `AXI_ADDR_W,
    parameter int DATA_W    = `AXI_DATA_W
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // Command requests from 4 ports (read/write commands)
    input  logic [NUM_PORTS-1:0]    cmd_valid,
    output logic [NUM_PORTS-1:0]    cmd_ready,
    input  logic [NUM_PORTS-1:0]    cmd_is_write,  // 1=write, 0=read
    input  logic [ID_W-1:0]         cmd_id   [NUM_PORTS],
    input  logic [ADDR_W-1:0]       cmd_addr [NUM_PORTS],
    input  logic [7:0]              cmd_len  [NUM_PORTS],
    input  logic [3:0]              cmd_qos  [NUM_PORTS],

    // Arbitrated output
    output logic                    out_valid,
    input  logic                    out_ready,
    output logic                    out_is_write,
    output logic [ID_W-1:0]         out_id,
    output logic [ADDR_W-1:0]       out_addr,
    output logic [7:0]              out_len,
    output logic [1:0]              out_port_id,
    output logic [3:0]              out_qos
);

    // --- WRR counters ---
    logic [3:0] wrr_cnt [NUM_PORTS];
    logic [3:0] wrr_weight [NUM_PORTS];

    // Port weights: Port0=priority, Port1=4, Port2=8, Port3=1
    assign wrr_weight[0] = 4'd15; // Highest (priority mode)
    assign wrr_weight[1] = 4'd4;
    assign wrr_weight[2] = 4'd8;
    assign wrr_weight[3] = 4'd1;

    // --- Priority encoder for Port 0 (strict high priority) ---
    logic port0_req;
    assign port0_req = cmd_valid[0];

    // --- Round-Robin pointer for WRR among Ports 1-3 ---
    // rr_ptr points to the port that should be checked first in the next round.
    // When a port's counter expires (reaches 1 and is granted), the pointer
    // advances to the next port, ensuring fair rotation.
    logic [1:0] rr_ptr;

    // --- WRR arbitration for Ports 1-3 ---
    logic [1:0] wrr_winner;
    logic       wrr_valid;

    // Find WRR winner starting from rr_ptr, scanning all WRR ports.
    // A port is eligible if it has a valid request AND remaining credit (wrr_cnt > 0).
    // Among eligible ports, the one closest to rr_ptr (in circular order) wins.
    // IMPORTANT: first match wins — break immediately to avoid later ports overwriting.
    always_comb begin
        wrr_winner = 2'd1;
        wrr_valid  = 1'b0;
        // Scan ports in circular order starting from rr_ptr
        for (int offset = 0; offset < NUM_PORTS; offset++) begin
            int idx;
            // Map offset to actual port index (ports 1..NUM_PORTS-1 only)
            idx = (rr_ptr + offset);
            if (idx >= NUM_PORTS) idx = idx - NUM_PORTS;
            if (idx >= 1) begin  // Skip port 0 (handled by strict priority)
                if (cmd_valid[idx] && (wrr_cnt[idx] > 0)) begin
                    wrr_winner = idx[1:0];
                    wrr_valid  = 1'b1;
                    break;  // First match wins — stop scanning
                end
            end
        end
    end

    // --- Final arbitration: Port0 priority > WRR winner ---
    logic [1:0] sel_port;
    logic       grant;

    always_comb begin
        if (port0_req) begin
            sel_port = 2'd0;
            grant    = 1'b1;
        end else if (wrr_valid) begin
            sel_port = wrr_winner;
            grant    = 1'b1;
        end else begin
            sel_port = 2'd0;
            grant    = 1'b0;
        end
    end

    // --- Output mux ---
    assign out_valid    = grant;
    assign out_is_write = cmd_is_write[sel_port];
    assign out_id       = cmd_id[sel_port];
    assign out_addr     = cmd_addr[sel_port];
    assign out_len      = cmd_len[sel_port];
    assign out_port_id  = sel_port;
    assign out_qos      = cmd_qos[sel_port];

    // --- Ready signals ---
    always_comb begin
        for (int i = 0; i < NUM_PORTS; i++) begin
            cmd_ready[i] = grant && (sel_port == i[1:0]) && out_ready;
        end
    end

    // --- WRR counter update ---
    // Decrement on grant; reload weight when counter reaches 1 (last credit).
    // When a port's last credit is consumed, advance rr_ptr to the next port.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PORTS; i++) begin
                wrr_cnt[i] <= wrr_weight[i];
            end
            rr_ptr <= 2'd1;  // Start from port 1
        end else begin
            for (int i = 0; i < NUM_PORTS; i++) begin
                if (cmd_ready[i]) begin
                    if (wrr_cnt[i] == 4'd1) begin
                        wrr_cnt[i] <= wrr_weight[i]; // Reload
                    end else begin
                        wrr_cnt[i] <= wrr_cnt[i] - 4'd1;
                    end
                end
            end
            // Advance round-robin pointer when current winner's last credit consumed
            if (grant && out_ready && !port0_req) begin
                if (wrr_cnt[sel_port] == 4'd1) begin
                    // Last credit consumed - move pointer to next WRR port
                    if (sel_port == (NUM_PORTS - 1))
                        rr_ptr <= 2'd1;
                    else
                        rr_ptr <= sel_port + 1'b1;
                end
            end
        end
    end

endmodule
