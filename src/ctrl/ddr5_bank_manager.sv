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

    // Simplified recovery windows: a bank stays in ST_PRECHG for PRE_CYCLES
    // (tRP) and in ST_REFRESH for REF_CYCLES (tRFC) before returning to ST_IDLE
    parameter int PRE_CYCLES = 4;
    parameter int REF_CYCLES = 4;

    logic [7:0] pre_cnt [NUM_BANKS];
    logic [7:0] ref_cnt;
    logic       ref_busy;

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
                pre_cnt[i] <= '0;
            end
            ref_cnt  <= '0;
            ref_busy <= 1'b0;
        end else begin
            // ---- recovery timers (overridden by commands below) -------------
            for (int i = 0; i < NUM_BANKS; i++) begin
                if (pre_cnt[i] > 0) begin
                    pre_cnt[i] <= pre_cnt[i] - 8'd1;
                end else if (state_r[i] == ST_PRECHG) begin
                    state_r[i] <= ST_IDLE;      // precharge complete
                end
            end

            if (ref_busy) begin
                if (ref_cnt > 0) begin
                    ref_cnt <= ref_cnt - 8'd1;
                end else begin
                    ref_busy <= 1'b0;
                    for (int i = 0; i < NUM_BANKS; i++) begin
                        if (state_r[i] == ST_REFRESH) state_r[i] <= ST_IDLE;
                    end
                end
            end

            // ---- command handling -------------------------------------------
            if (cmd_valid) begin
                case (cmd_type)
                    4'h1: begin // ACT
                        state_r[cmd_bank] <= ST_ACTIVE;
                        row_r[cmd_bank]   <= cmd_row;
                        open_r[cmd_bank]  <= 1'b1;
                        pre_cnt[cmd_bank] <= '0;
                    end
                    4'h4: begin // PRE
                        state_r[cmd_bank] <= ST_PRECHG;
                        open_r[cmd_bank]  <= 1'b0;
                        pre_cnt[cmd_bank] <= PRE_CYCLES[7:0];
                    end
                    4'h5: begin // REF
                        for (int i = 0; i < NUM_BANKS; i++) begin
                            state_r[i] <= ST_REFRESH;
                            open_r[i]  <= 1'b0;
                            pre_cnt[i] <= '0;
                        end
                        ref_busy <= 1'b1;
                        ref_cnt  <= REF_CYCLES[7:0];
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
