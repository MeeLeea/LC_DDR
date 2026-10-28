// =============================================================================
// Module: ddr5_axi4_wr_slave
// Description: AXI4 Write Channel Slave (AW/W/B)
//              Handles write address, write data, and write response
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_axi4_wr_slave #(
    parameter int ID_W   = `AXI_ID_W,
    parameter int ADDR_W = `AXI_ADDR_W,
    parameter int DATA_W = `AXI_DATA_W,
    parameter int STRB_W = `AXI_STRB_W
)(
    input  logic              clk,
    input  logic              rst_n,

    // AW channel
    input  logic [ID_W-1:0]   awid,
    input  logic [ADDR_W-1:0] awaddr,
    input  logic [7:0]        awlen,
    input  logic [2:0]        awsize,
    input  logic [1:0]        awburst,
    input  logic [3:0]        awcache,
    input  logic [2:0]        awprot,
    input  logic [3:0]        awqos,
    input  logic              awlock,     // B-02: 1 = exclusive access
    input  logic              awvalid,
    output logic              awready,

    // B-02: exclusive-write grant from the exclusive monitor (valid at AW handshake)
    input  logic              ex_aw_ok,

    // W channel
    input  logic [DATA_W-1:0] wdata,
    input  logic [STRB_W-1:0] wstrb,
    input  logic              wlast,
    input  logic              wvalid,
    output logic              wready,

    // B channel
    output logic [ID_W-1:0]   bid,
    output logic [1:0]        bresp,
    output logic              bvalid,
    input  logic              bready,

    // Command output to scheduler
    output logic              cmd_valid,
    input  logic              cmd_ready,
    output logic [ID_W-1:0]   cmd_id,
    output logic [ADDR_W-1:0] cmd_addr,
    output logic [7:0]        cmd_len,
    output logic [3:0]        cmd_qos,

    // Write data output to FIFO
    output logic              wr_data_valid,
    input  logic              wr_data_ready,
    output logic [DATA_W-1:0] wr_data,
    output logic [STRB_W-1:0] wr_strb,
    output logic              wr_last
);

    // --- State machine for write transaction ---
    typedef enum logic [1:0] {
        IDLE,
        ADDR,
        DATA,
        RESP
    } wr_state_t;

    wr_state_t state, state_next;

    // --- Registers ---
    logic [ID_W-1:0]   id_reg, id_next;
    logic [ADDR_W-1:0] addr_reg, addr_next;
    logic [7:0]        len_reg, len_next;
    logic [3:0]        qos_reg, qos_next;
    logic [7:0]        beat_cnt, beat_cnt_next;
    logic              ex_write_r, ex_write_n;  // B-02: this txn was exclusive
    logic              ex_ok_r,    ex_ok_n;     // B-02: exclusive grant captured

    // --- State transition ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            id_reg   <= '0;
            addr_reg <= '0;
            len_reg  <= '0;
            qos_reg  <= '0;
            beat_cnt <= '0;
            ex_write_r <= 1'b0;
            ex_ok_r    <= 1'b0;
        end else begin
            state    <= state_next;
            id_reg   <= id_next;
            addr_reg <= addr_next;
            len_reg  <= len_next;
            qos_reg  <= qos_next;
            beat_cnt <= beat_cnt_next;
            ex_write_r <= ex_write_n;
            ex_ok_r    <= ex_ok_n;
        end
    end

    // --- Next state logic ---
    always_comb begin
        state_next    = state;
        id_next       = id_reg;
        addr_next     = addr_reg;
        len_next      = len_reg;
        qos_next      = qos_reg;
        beat_cnt_next = beat_cnt;
        ex_write_n    = ex_write_r;
        ex_ok_n       = ex_ok_r;

        awready       = 1'b0;
        wready        = 1'b0;
        bvalid        = 1'b0;
        bid           = id_reg;
        bresp         = `AXI_RESP_OKAY;
        cmd_valid     = 1'b0;
        cmd_id        = id_reg;
        cmd_addr      = addr_reg;
        cmd_len       = len_reg;
        cmd_qos       = qos_reg;
        wr_data_valid = 1'b0;
        wr_data       = wdata;
        wr_strb       = wstrb;
        wr_last       = wlast;

        case (state)
            IDLE: begin
                awready = 1'b1;
                if (awvalid) begin
                    state_next = ADDR;
                    id_next    = awid;
                    addr_next  = awaddr;
                    len_next   = awlen;
                    qos_next   = awqos;
                    ex_write_n = awlock;                 // B-02
                    ex_ok_n    = awlock & ex_aw_ok;      // B-02
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
                wready        = 1'b1;
                wr_data_valid = wvalid;
                if (wvalid && wready) begin
                    beat_cnt_next = beat_cnt + 8'd1;
                    if (wlast) begin
                        state_next = RESP;
                    end
                end
            end

            RESP: begin
                bvalid = 1'b1;
                // B-02: EXOKAY only for a granted exclusive write
                bresp  = (ex_write_r & ex_ok_r) ? `AXI_RESP_EXOKAY
                                                : `AXI_RESP_OKAY;
                if (bready) begin
                    state_next = IDLE;
                end
            end

            default: begin
                state_next = IDLE;
            end
        endcase
    end

endmodule
