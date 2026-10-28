// =============================================================================
// Module: ddr5_cdc_fifo
// Description: Parameterized async FIFO with Gray-code pointers
//              Used for uclk<->cclk, cclk<->uclk CDC paths
// =============================================================================
module ddr5_cdc_fifo #(
    parameter int DATA_W    = 256,
    parameter int ADDR_W    = 6,     // Depth = 2^ADDR_W
    parameter int DEPTH     = 1 << ADDR_W
)(
    // Write domain
    input  logic              wr_clk,
    input  logic              wr_rst_n,
    input  logic              wr_en,
    input  logic [DATA_W-1:0] wr_data,
    output logic              wr_full,

    // Read domain
    input  logic              rd_clk,
    input  logic              rd_rst_n,
    input  logic              rd_en,
    output logic [DATA_W-1:0] rd_data,
    output logic              rd_empty,
    output logic              rd_valid  // registered, synchronized with data
);

    // --- Memory array ---
    logic [DATA_W-1:0] mem [DEPTH];

    // --- Binary pointers ---
    logic [ADDR_W:0] wr_ptr_bin;
    logic [ADDR_W:0] rd_ptr_bin;

    // --- Gray-code pointers ---
    logic [ADDR_W:0] wr_ptr_gray;
    logic [ADDR_W:0] rd_ptr_gray;

    // --- Synchronized pointers (cross-domain) ---
    logic [ADDR_W:0] wr_ptr_gray_sync_rd;  // wr_gray synced to rd_clk
    logic [ADDR_W:0] rd_ptr_gray_sync_wr;  // rd_gray synced to wr_clk

    // --- Binary to Gray conversion ---
    function automatic logic [ADDR_W:0] bin2gray(input logic [ADDR_W:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    // =========================================================================
    // Write pointer logic (wr_clk domain)
    // =========================================================================
    logic [ADDR_W:0] wr_ptr_bin_next;
    logic            wr_full_comb;

    assign wr_ptr_bin_next  = wr_ptr_bin + (wr_en & ~wr_full);
    assign wr_ptr_gray      = bin2gray(wr_ptr_bin);
    assign wr_full_comb     = (bin2gray(wr_ptr_bin_next) == {~rd_ptr_gray_sync_wr[ADDR_W:ADDR_W-1],
                                                    rd_ptr_gray_sync_wr[ADDR_W-2:0]});

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin <= '0;
            wr_full    <= 1'b0;
        end else begin
            if (wr_en && !wr_full) begin
                wr_ptr_bin <= wr_ptr_bin_next;
            end
            wr_full <= wr_full_comb;
        end
    end

    // Write to memory
    always_ff @(posedge wr_clk) begin
        if (wr_en && !wr_full) begin
            mem[wr_ptr_bin[ADDR_W-1:0]] <= wr_data;
        end
    end

    // =========================================================================
    // Read pointer logic (rd_clk domain)
    // =========================================================================
    logic [ADDR_W:0] rd_ptr_bin_next;
    logic            rd_empty_comb;

    assign rd_ptr_bin_next  = rd_ptr_bin + (rd_en & ~rd_empty);
    assign rd_ptr_gray      = bin2gray(rd_ptr_bin);
    assign rd_empty_comb    = (bin2gray(rd_ptr_bin_next) == wr_ptr_gray_sync_rd);

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin <= '0;
            rd_empty   <= 1'b1;
        end else begin
            if (rd_en && !rd_empty) begin
                rd_ptr_bin <= rd_ptr_bin_next;
            end
            rd_empty <= rd_empty_comb;
        end
    end

    // Read from memory (combinational read for async FIFO)
    assign rd_data = mem[rd_ptr_bin[ADDR_W-1:0]];

    // Registered read valid signal (synchronized with rd_data pipeline)
    // This solves the 1-cycle lag between combinational rd_data and registered rd_empty
    logic rd_valid_r;
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)
            rd_valid_r <= 1'b0;
        else
            rd_valid_r <= !rd_empty_comb;
    end
    assign rd_valid = rd_valid_r;

    // =========================================================================
    // Cross-domain pointer synchronization (2-stage sync)
    // =========================================================================

    // Sync wr_gray -> rd_clk domain
    logic [ADDR_W:0] wr_gray_sync_0, wr_gray_sync_1;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync_0       <= '0;
            wr_gray_sync_1       <= '0;
            wr_ptr_gray_sync_rd  <= '0;
        end else begin
            wr_gray_sync_0       <= wr_ptr_gray;
            wr_gray_sync_1       <= wr_gray_sync_0;
            wr_ptr_gray_sync_rd  <= wr_gray_sync_1;
        end
    end

    // Sync rd_gray -> wr_clk domain
    logic [ADDR_W:0] rd_gray_sync_0, rd_gray_sync_1;

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync_0       <= '0;
            rd_gray_sync_1       <= '0;
            rd_ptr_gray_sync_wr  <= '0;
        end else begin
            rd_gray_sync_0       <= rd_ptr_gray;
            rd_gray_sync_1       <= rd_gray_sync_0;
            rd_ptr_gray_sync_wr  <= rd_gray_sync_1;
        end
    end

endmodule
