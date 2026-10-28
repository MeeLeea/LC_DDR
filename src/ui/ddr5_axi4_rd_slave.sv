// =============================================================================
// Module: ddr5_axi4_rd_slave
// Description: AXI4 Read Channel Slave (AR/R)
//              Handles read address and read data response
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_axi4_rd_slave #(
    parameter int ID_W   = `AXI_ID_W,
    parameter int ADDR_W = `AXI_ADDR_W,
    parameter int DATA_W = `AXI_DATA_W
)(
    input  logic              clk,
    input  logic              rst_n,

    // AR channel
    input  logic [ID_W-1:0]   arid,
    input  logic [ADDR_W-1:0] araddr,
    input  logic [7:0]        arlen,
    input  logic [2:0]        arsize,
    input  logic [1:0]        arburst,
    input  logic [3:0]        arcache,
    input  logic [2:0]        arprot,
    input  logic [3:0]        arqos,
    input  logic              arlock,     // B-02: 1 = exclusive access
    input  logic              arvalid,
    output logic              arready,

    // R channel
    output logic [ID_W-1:0]   rid,
    output logic [DATA_W-1:0] rdata,
    output logic [1:0]        rresp,
    output logic              rlast,
    output logic              rvalid,
    input  logic              rready,

    // Command output to scheduler
    output logic              cmd_valid,
    input  logic              cmd_ready,
    output logic [ID_W-1:0]   cmd_id,
    output logic [ADDR_W-1:0] cmd_addr,
    output logic [7:0]        cmd_len,
    output logic [3:0]        cmd_qos,

    // Read data input from controller
    input  logic [DATA_W-1:0] rd_data,
    input  logic              rd_data_valid,
    output logic              rd_data_ready
);

    // --- State machine ---
    typedef enum logic [1:0] {
        IDLE,
        ADDR,
        DATA
    } rd_state_t;

    rd_state_t state, state_next;

    // --- Registers ---
    logic [ID_W-1:0]   id_reg, id_next;
    logic [ADDR_W-1:0] addr_reg, addr_next;
    logic [7:0]        len_reg, len_next;
    logic [3:0]        qos_reg, qos_next;
    logic [7:0]        beat_cnt, beat_cnt_next;
    logic              ex_read_r, ex_read_n;  // B-02: this txn was exclusive

    // --- Sequential logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            id_reg   <= '0;
            addr_reg <= '0;
            len_reg  <= '0;
            qos_reg  <= '0;
            beat_cnt <= '0;
            ex_read_r <= 1'b0;
        end else begin
            state    <= state_next;
            id_reg   <= id_next;
            addr_reg <= addr_next;
            len_reg  <= len_next;
            qos_reg  <= qos_next;
            beat_cnt <= beat_cnt_next;
            ex_read_r <= ex_read_n;
        end
    end

    // --- Next state and output logic ---
    always_comb begin
        state_next    = state;
        id_next       = id_reg;
        addr_next     = addr_reg;
        len_next      = len_reg;
        qos_next      = qos_reg;
        beat_cnt_next = beat_cnt;
        ex_read_n     = ex_read_r;

        arready       = 1'b0;
        cmd_valid     = 1'b0;
        cmd_id        = id_reg;
        cmd_addr      = addr_reg;
        cmd_len       = len_reg;
        cmd_qos       = qos_reg;

        rid           = id_reg;
        rdata         = rd_data;
        rresp         = `AXI_RESP_OKAY;
        rlast         = (beat_cnt == len_reg);
        rvalid        = 1'b0;
        rd_data_ready = 1'b0;

        case (state)
            IDLE: begin
                arready = 1'b1;
                if (arvalid) begin
                    state_next = ADDR;
                    id_next    = arid;
                    addr_next  = araddr;
                    len_next   = arlen;
                    qos_next   = arqos;
                    ex_read_n  = arlock;   // B-02
                end
            end

            ADDR: begin
                cmd_valid = 1'b1;
                if (cmd_ready) begin
                    state_next    = DATA;
                    beat_cnt_next = '0;
                end
            end

            DATA: begin
                rvalid        = rd_data_valid;
                // B-02: exclusive read returns EXOKAY on its first beat
                rresp         = (ex_read_r && (beat_cnt == 8'd0))
                                ? `AXI_RESP_EXOKAY : `AXI_RESP_OKAY;
                rd_data_ready = rready;
                if (rd_data_valid && rready) begin
                    beat_cnt_next = beat_cnt + 8'd1;
                    if (beat_cnt == len_reg) begin
                        state_next = IDLE;
                    end
                end
            end

            default: begin
                state_next = IDLE;
            end
        endcase
    end

endmodule
