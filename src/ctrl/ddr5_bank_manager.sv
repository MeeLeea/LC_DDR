// =============================================================================
// Module: ddr5_bank_manager
// Description: 32-bank state manager (4 BG x 8 banks)
//              Tracks open row, bank state, page hit/miss/conflict
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_bank_manager #(
    parameter int NUM_BANKS = `DDR5_NUM_BANKS,
    parameter int ROW_W     = `DDR5_ROW_W
)(
    input  logic              clk,
    input  logic              rst_n,

    // Command request
    input  logic              cmd_valid,
    input  logic [3:0]        cmd_type,
    input  logic [4:0]        cmd_bank,
    input  logic [ROW_W-1:0]  cmd_row,

    // Page status output
    output logic              page_hit,
    output logic              page_miss,
    output logic              page_conflict,
    output logic              bank_ready,

    // Bank state query
    output logic [2:0]        bank_state [NUM_BANKS],
    output logic [ROW_W-1:0]  open_row   [NUM_BANKS],
    output logic              row_open   [NUM_BANKS]
);

    // Bank state encoding
    localparam ST_IDLE    = 3'b000;
    localparam ST_ACTIVE  = 3'b001;
    localparam ST_PRECHG  = 3'b010;
    localparam ST_REFRESH = 3'b011;

    // Per-bank state registers
    logic [2:0]     state_r [NUM_BANKS];
    logic [ROW_W-1:0] row_r [NUM_BANKS];
    logic           open_r  [NUM_BANKS];

    // Page status logic (combinational)
    always_comb begin
        page_hit      = 1'b0;
        page_miss     = 1'b0;
        page_conflict = 1'b0;
        bank_ready    = 1'b0;

        if (cmd_valid) begin
            if (state_r[cmd_bank] == ST_IDLE) begin
                page_miss  = 1'b1;
                bank_ready = 1'b1;
            end else if (state_r[cmd_bank] == ST_ACTIVE) begin
                if (open_r[cmd_bank] && (row_r[cmd_bank] == cmd_row)) begin
                    page_hit   = 1'b1;
                    bank_ready = 1'b1;
                end else begin
                    page_conflict = 1'b1;
                    bank_ready    = 1'b0; // Need PRE first
                end
            end else begin
                bank_ready = 1'b0;
            end
        end
    end

    // State update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_BANKS; i++) begin
                state_r[i] <= ST_IDLE;
                row_r[i]   <= '0;
                open_r[i]  <= 1'b0;
            end
        end else begin
            if (cmd_valid) begin
                case (cmd_type)
                    4'h1: begin // ACT
                        state_r[cmd_bank] <= ST_ACTIVE;
                        row_r[cmd_bank]   <= cmd_row;
                        open_r[cmd_bank]  <= 1'b1;
                    end
                    4'h4: begin // PRE
                        state_r[cmd_bank] <= ST_IDLE;
                        open_r[cmd_bank]  <= 1'b0;
                    end
                    4'h5: begin // REF
                        for (int i = 0; i < NUM_BANKS; i++) begin
                            state_r[i] <= ST_IDLE;
                            open_r[i]  <= 1'b0;
                        end
                    end
                    default: ; // RD/WR don't change bank state
                endcase
            end
        end
    end

    // Output assignments
    generate
        for (genvar i = 0; i < NUM_BANKS; i++) begin : gen_out
            assign bank_state[i] = state_r[i];
            assign open_row[i]   = row_r[i];
            assign row_open[i]   = open_r[i];
        end
    endgenerate

endmodule
