// =============================================================================
// Module: ddr5_cmd_scheduler
// Description: FR-FCFS (First-Ready First-Come-First-Serve) scheduler
//              4-stage pipeline: fetch -> decode -> schedule -> issue
//              Prioritizes page hits, then page empty, then page conflicts
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_cmd_scheduler #(
    parameter int QUEUE_DEPTH = 16,
    parameter int NUM_BANKS   = `DDR5_NUM_BANKS
)(
    input  logic        clk,
    input  logic        rst_n,

    // Command input from UI layer (via CDC FIFO)
    input  logic        cmd_in_valid,
    output logic        cmd_in_ready,
    input  logic [7:0]  cmd_in_id,
    input  logic [33:0] cmd_in_addr,
    input  logic [7:0]  cmd_in_len,
    input  logic        cmd_in_is_write,
    input  logic [1:0]  cmd_in_port_id,
    input  logic [3:0]  cmd_in_qos,

    // Command output to protocol FSM
    output logic        cmd_out_valid,
    input  logic        cmd_out_ready,
    output logic [3:0]  cmd_out_type,
    output logic [7:0]  cmd_out_id,
    output logic [4:0]  cmd_out_bank,
    output logic [2:0]  cmd_out_bg,
    output logic [2:0]  cmd_out_ba,
    output logic [17:0] cmd_out_row,
    output logic [9:0]  cmd_out_col,
    output logic        cmd_out_sub_ch,  // 0=A, 1=B
    output logic [1:0]  cmd_out_port_id,

    // Bank manager interface
    input  logic [2:0]  bank_state [NUM_BANKS],
    input  logic [17:0] open_row   [NUM_BANKS],
    input  logic        row_open   [NUM_BANKS],

    // Refresh interface
    input  logic        ref_req,
    output logic        ref_block,

    // Status
    output logic [3:0]  queue_count
);

    // Command queue entry structure
    typedef struct packed {
        logic [7:0]  id;
        logic [33:0] addr;
        logic [7:0]  len;
        logic        is_write;
        logic [1:0]  port_id;
        logic [3:0]  qos;
        logic        sub_ch;      // 0=A, 1=B
        logic        valid;
    } cmd_entry_t;

    // Command queue
    cmd_entry_t queue [QUEUE_DEPTH];
    logic [3:0] wr_ptr, rd_ptr;
    logic [3:0] count;

    // Address decoder outputs
    logic [17:0] dec_row   [QUEUE_DEPTH];
    logic [2:0]  dec_bg    [QUEUE_DEPTH];
    logic [2:0]  dec_ba    [QUEUE_DEPTH];
    logic [4:0]  dec_bank  [QUEUE_DEPTH];
    logic [9:0]  dec_col   [QUEUE_DEPTH];
    logic        dec_subch [QUEUE_DEPTH];

    // Page status for each queued command
    logic        page_hit      [QUEUE_DEPTH];
    logic        page_miss     [QUEUE_DEPTH];
    logic        page_conflict [QUEUE_DEPTH];

    // Pipeline stage 1: Fetch (write to queue)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            count  <= '0;
            for (int i = 0; i < QUEUE_DEPTH; i++) begin
                queue[i].valid <= 1'b0;
            end
        end else begin
            if (cmd_in_valid && cmd_in_ready) begin
                queue[wr_ptr].id       <= cmd_in_id;
                queue[wr_ptr].addr     <= cmd_in_addr;
                queue[wr_ptr].len      <= cmd_in_len;
                queue[wr_ptr].is_write <= cmd_in_is_write;
                queue[wr_ptr].port_id  <= cmd_in_port_id;
                queue[wr_ptr].qos      <= cmd_in_qos;
                queue[wr_ptr].sub_ch   <= cmd_in_addr[3];  // Extract sub-channel from addr
                queue[wr_ptr].valid    <= 1'b1;
                wr_ptr <= wr_ptr + 4'd1;
                count  <= count + 4'd1;
            end
            // Decrement on read (only when queue entry is actually removed, i.e. RD/WR)
            if (cmd_out_valid && cmd_out_ready && (cmd_out_type == 4'h2 || cmd_out_type == 4'h3)) begin
                count <= count - 4'd1;
            end
        end
    end

    assign cmd_in_ready = (count < QUEUE_DEPTH);

    // Pipeline stage 2: Decode (address mapping)
    generate
        for (genvar i = 0; i < QUEUE_DEPTH; i++) begin : gen_decode
            ddr5_addr_mapper u_mapper (
                .clk       (clk),
                .rst_n     (rst_n),
                .axi_addr  (queue[i].addr),
                .row_addr  (dec_row[i]),
                .bg_addr   (dec_bg[i]),
                .bank_addr (dec_ba[i]),
                .col_addr  (dec_col[i]),
                .rank_addr (),
                .sub_channel (dec_subch[i]),
                .map_mode  (2'b00)
            );
            assign dec_bank[i] = {dec_bg[i][1:0], dec_ba[i]};
            // dec_subch[i] is driven by the addr_mapper .sub_channel output
        end
    endgenerate

    // Pipeline stage 3: Schedule (FR-FCFS arbitration)
    // Determine page status for each queue entry
    generate
        for (genvar i = 0; i < QUEUE_DEPTH; i++) begin : gen_page_status
            always_comb begin
                page_hit[i]      = 1'b0;
                page_miss[i]     = 1'b0;
                page_conflict[i] = 1'b0;

                if (queue[i].valid) begin
                    if (bank_state[dec_bank[i]] == 3'b000) begin
                        // Bank idle -> page miss (need ACT)
                        page_miss[i] = 1'b1;
                    end else if (bank_state[dec_bank[i]] == 3'b001) begin
                        // Bank active
                        if (row_open[dec_bank[i]] && (open_row[dec_bank[i]] == dec_row[i])) begin
                            page_hit[i] = 1'b1;  // Same row -> hit
                        end else begin
                            page_conflict[i] = 1'b1;  // Different row -> conflict
                        end
                    end
                end
            end
        end
    endgenerate

    // FR-FCFS priority encoder
    logic [3:0] winner_idx;
    logic       winner_found;
    logic       winner_is_hit;

    // 仲裁扫描用的临时索引 (原为 for 循环内 `int idx` 声明, Xsim 报
    // VRFC 10-3824 要求显式 automatic/static; 提到模块级避开该问题)
    int         idx;

    always_comb begin
        winner_idx   = '0;
        winner_found = 1'b0;
        winner_is_hit = 1'b0;

        // Priority 1: Page hits (oldest first)
        for (int i = 0; i < QUEUE_DEPTH; i++) begin
            idx = (rd_ptr + i[3:0]) % QUEUE_DEPTH;
            if (queue[idx].valid && page_hit[idx] && !winner_found) begin
                winner_idx    = idx[3:0];
                winner_found  = 1'b1;
                winner_is_hit = 1'b1;
            end
        end

        // Priority 2: Page miss (bank idle)
        if (!winner_found) begin
            for (int i = 0; i < QUEUE_DEPTH; i++) begin
                idx = (rd_ptr + i[3:0]) % QUEUE_DEPTH;
                if (queue[idx].valid && page_miss[idx] && !winner_found) begin
                    winner_idx   = idx[3:0];
                    winner_found = 1'b1;
                end
            end
        end

        // Priority 3: Page conflict (need PRE + ACT)
        if (!winner_found) begin
            for (int i = 0; i < QUEUE_DEPTH; i++) begin
                idx = (rd_ptr + i[3:0]) % QUEUE_DEPTH;
                if (queue[idx].valid && page_conflict[idx] && !winner_found) begin
                    winner_idx   = idx[3:0];
                    winner_found = 1'b1;
                end
            end
        end
    end

    // Pipeline stage 4: Issue
    always_comb begin
        cmd_out_valid   = 1'b0;
        cmd_out_type    = 4'h0;
        cmd_out_id      = '0;
        cmd_out_bank    = '0;
        cmd_out_bg      = '0;
        cmd_out_ba      = '0;
        cmd_out_row     = '0;
        cmd_out_col     = '0;
        cmd_out_sub_ch  = 1'b0;
        cmd_out_port_id = '0;
        ref_block       = 1'b0;

        if (winner_found && !ref_req) begin
            cmd_out_valid   = 1'b1;
            cmd_out_id      = queue[winner_idx].id;
            cmd_out_bank    = dec_bank[winner_idx];
            cmd_out_bg      = dec_bg[winner_idx];
            cmd_out_ba      = dec_ba[winner_idx];
            cmd_out_row     = dec_row[winner_idx];
            cmd_out_col     = dec_col[winner_idx];
            cmd_out_sub_ch  = dec_subch[winner_idx];
            cmd_out_port_id = queue[winner_idx].port_id;

            // Determine command type based on page status
            if (page_hit[winner_idx]) begin
                cmd_out_type = queue[winner_idx].is_write ? 4'h3 : 4'h2;  // WR or RD
            end else if (page_miss[winner_idx]) begin
                cmd_out_type = 4'h1;  // ACT
            end else if (page_conflict[winner_idx]) begin
                cmd_out_type = 4'h4;  // PRE
            end
        end else if (ref_req) begin
            ref_block = 1'b1;
        end
    end

    // Remove issued command from queue (only on RD/WR, not ACT/PRE which are 2-step sequences)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
        end else if (cmd_out_valid && cmd_out_ready) begin
            // Only dequeue on actual RD/WR commands; ACT/PRE/REF are intermediate steps
            if (cmd_out_type == 4'h2 || cmd_out_type == 4'h3) begin
                queue[winner_idx].valid <= 1'b0;
                rd_ptr <= rd_ptr + 4'd1;
            end
        end
    end

    assign queue_count = count;

endmodule
