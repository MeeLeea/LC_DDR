// =============================================================================
// Module: ddr5_cfg_apb
// Description: APB slave interface for DDR5 controller configuration
//              Provides register access bridge between APB and regfile
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_cfg_apb #(
    parameter int ADDR_W = 16,
    parameter int DATA_W = 32
)(
    input  logic              clk,
    input  logic              rst_n,

    // APB slave interface
    input  logic [ADDR_W-1:0] paddr,
    input  logic [DATA_W-1:0] pwdata,
    output logic [DATA_W-1:0] prdata,
    input  logic              psel,
    input  logic              penable,
    input  logic              pwrite,
    output logic              pready,
    output logic              pslverr,

    // Register file interface
    output logic              reg_wr_en,
    output logic [ADDR_W-1:0] reg_addr,
    output logic [DATA_W-1:0] reg_wr_data,
    input  logic [DATA_W-1:0] reg_rd_data
);

    // APB state machine
    typedef enum logic [1:0] {
        APB_IDLE,
        APB_SETUP,
        APB_ACCESS
    } apb_state_t;

    apb_state_t state, state_next;

    // Registered signals
    logic [ADDR_W-1:0] addr_reg;
    logic [DATA_W-1:0] wdata_reg;
    logic              write_reg;

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= APB_IDLE;
            addr_reg  <= '0;
            wdata_reg <= '0;
            write_reg <= 1'b0;
        end else begin
            state <= state_next;
            if (state == APB_IDLE && psel && !penable) begin
                addr_reg  <= paddr;
                wdata_reg <= pwdata;
                write_reg <= pwrite;
            end
        end
    end

    // Next state logic
    always_comb begin
        state_next = state;
        case (state)
            APB_IDLE: begin
                if (psel && !penable)
                    state_next = APB_SETUP;
            end
            APB_SETUP: begin
                if (psel && penable)
                    state_next = APB_ACCESS;
                else
                    state_next = APB_IDLE;
            end
            APB_ACCESS: begin
                state_next = APB_IDLE;
            end
            default: state_next = APB_IDLE;
        endcase
    end

    // Output logic
    assign pready   = (state == APB_ACCESS);
    assign pslverr  = 1'b0;  // No error checking for now
    assign prdata   = reg_rd_data;

    // Register file interface
    assign reg_wr_en   = (state == APB_ACCESS) && write_reg;
    assign reg_addr    = addr_reg;
    assign reg_wr_data = wdata_reg;

endmodule
