// =============================================================================
// Module: ddr5_dfi_bridge
// Description: DFI 5.1 bridge between controller core and PHY
//              Handles frequency ratio conversion (1:2 or 1:4)
//              Manages command/data multiplexing and training interface
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_dfi_bridge #(
    parameter int FREQ_RATIO = 2  // 1:2 frequency ratio
)(
    input  logic        ctrl_clk,
    input  logic        dfi_clk,
    input  logic        rst_n,

    // Controller core interface (ctrl_clk domain)
    input  logic        ctrl_cmd_valid,
    output logic        ctrl_cmd_ready,
    input  logic [17:0] ctrl_address,
    input  logic [5:0]  ctrl_bank,
    input  logic [1:0]  ctrl_cs_n,
    input  logic        ctrl_act_n,
    input  logic        ctrl_ras_n,
    input  logic        ctrl_cas_n,
    input  logic        ctrl_we_n,
    input  logic [127:0] ctrl_wrdata,
    input  logic [15:0]  ctrl_wrdata_mask,
    input  logic         ctrl_wrdata_en,
    output logic [127:0] ctrl_rddata,
    output logic         ctrl_rddata_valid,

    // PHY interface (dfi_clk domain)
    output logic        dfi_cmd_valid,
    input  logic        dfi_cmd_ready,
    output logic [17:0] dfi_address,
    output logic [5:0]  dfi_bank,
    output logic [1:0]  dfi_cs_n,
    output logic        dfi_act_n,
    output logic        dfi_ras_n,
    output logic        dfi_cas_n,
    output logic        dfi_we_n,
    output logic [127:0] dfi_wrdata,
    output logic [15:0]  dfi_wrdata_mask,
    output logic         dfi_wrdata_en,
    input  logic [127:0] dfi_rddata,
    input  logic         dfi_rddata_valid,

    // --- DFI 5.1 additional control/status signals (B-04) ---
    output logic [`DFI_PHYCSEL_W-1:0]      dfi_phycsel,          // PHY instance select
    output logic [`DFI_PARITY_W-1:0]       dfi_parity_in,        // CA parity (driven by MC)
    output logic [`DFI_DRAM_CLK_DIS_W-1:0] dfi_dram_clk_disable, // DRAM clock disable per sub-ch
    output logic [`DFI_FREQ_RATIO_W-1:0]   dfi_freq_ratio,       // Frequency-ratio indication
    input  logic [`DFI_RDDATA_DNV_W-1:0]   dfi_rddata_dnv,       // Read data not-valid per sub-ch

    // Training interface
    input  logic        train_start,
    output logic        train_complete,
    output logic        train_error,
    input  logic        phy_init_complete,

    // Configuration
    input  logic [1:0]  cfg_freq_ratio,
    input  logic        cfg_dual_channel
);

    // Command FIFO (ctrl_clk -> dfi_clk CDC)
    logic        cmd_fifo_wr;
    logic        cmd_fifo_rd;
    logic        cmd_fifo_full;
    logic        cmd_fifo_empty;
    logic [17:0] cmd_fifo_addr_in;
    logic [5:0]  cmd_fifo_bank_in;
    logic [1:0]  cmd_fifo_cs_in;
    logic        cmd_fifo_act_in;
    logic        cmd_fifo_ras_in;
    logic        cmd_fifo_cas_in;
    logic        cmd_fifo_we_in;
    logic [17:0] cmd_fifo_addr_out;
    logic [5:0]  cmd_fifo_bank_out;
    logic [1:0]  cmd_fifo_cs_out;
    logic        cmd_fifo_act_out;
    logic        cmd_fifo_ras_out;
    logic        cmd_fifo_cas_out;
    logic        cmd_fifo_we_out;

    // Pack command for FIFO
    logic [34:0] cmd_fifo_din;
    logic [34:0] cmd_fifo_dout;

    assign cmd_fifo_din = {ctrl_address, ctrl_bank, ctrl_cs_n, ctrl_act_n, ctrl_ras_n, ctrl_cas_n, ctrl_we_n};
    assign {cmd_fifo_addr_out, cmd_fifo_bank_out, cmd_fifo_cs_out, cmd_fifo_act_out, 
            cmd_fifo_ras_out, cmd_fifo_cas_out, cmd_fifo_we_out} = cmd_fifo_dout;

    // Command FIFO instance
    ddr5_cdc_fifo #(
        .DATA_W (35),
        .ADDR_W (4)  // Depth 16
    ) u_cmd_fifo (
        .wr_clk   (ctrl_clk),
        .wr_rst_n (rst_n),
        .wr_en    (ctrl_cmd_valid && !cmd_fifo_full),
        .wr_data  (cmd_fifo_din),
        .wr_full  (cmd_fifo_full),
        .rd_clk   (dfi_clk),
        .rd_rst_n (rst_n),
        .rd_en    (cmd_fifo_rd),
        .rd_data  (cmd_fifo_dout),
        .rd_empty (cmd_fifo_empty)
    );

    assign cmd_fifo_wr = ctrl_cmd_valid && !cmd_fifo_full;
    assign cmd_fifo_rd = !cmd_fifo_empty && dfi_cmd_ready;
    assign ctrl_cmd_ready = !cmd_fifo_full;

    // DFI command output
    assign dfi_cmd_valid = !cmd_fifo_empty;
    assign dfi_address   = cmd_fifo_addr_out;
    assign dfi_bank      = cmd_fifo_bank_out;
    assign dfi_cs_n      = cmd_fifo_cs_out;
    assign dfi_act_n     = cmd_fifo_act_out;
    assign dfi_ras_n     = cmd_fifo_ras_out;
    assign dfi_cas_n     = cmd_fifo_cas_out;
    assign dfi_we_n      = cmd_fifo_we_out;

    // Write data FIFO (ctrl_clk -> dfi_clk CDC)
    logic        wdata_fifo_full;
    logic        wdata_fifo_empty;
    logic [143:0] wdata_fifo_din;
    logic [143:0] wdata_fifo_dout;

    assign wdata_fifo_din = {ctrl_wrdata, ctrl_wrdata_mask};
    assign {dfi_wrdata, dfi_wrdata_mask} = wdata_fifo_dout;

    ddr5_cdc_fifo #(
        .DATA_W (144),
        .ADDR_W (4)
    ) u_wdata_fifo (
        .wr_clk   (ctrl_clk),
        .wr_rst_n (rst_n),
        .wr_en    (ctrl_wrdata_en && !wdata_fifo_full),
        .wr_data  (wdata_fifo_din),
        .wr_full  (wdata_fifo_full),
        .rd_clk   (dfi_clk),
        .rd_rst_n (rst_n),
        .rd_en    (dfi_wrdata_en),
        .rd_data  (wdata_fifo_dout),
        .rd_empty (wdata_fifo_empty)
    );

    assign dfi_wrdata_en = !wdata_fifo_empty;

    // Read data FIFO (dfi_clk -> ctrl_clk CDC)
    logic        rdata_fifo_full;
    logic        rdata_fifo_empty;

    ddr5_cdc_fifo #(
        .DATA_W (128),
        .ADDR_W (4)
    ) u_rdata_fifo (
        .wr_clk   (dfi_clk),
        .wr_rst_n (rst_n),
        .wr_en    (dfi_rddata_valid),
        .wr_data  (dfi_rddata),
        .wr_full  (rdata_fifo_full),
        .rd_clk   (ctrl_clk),
        .rd_rst_n (rst_n),
        .rd_en    (ctrl_rddata_valid),
        .rd_data  (ctrl_rddata),
        .rd_empty (rdata_fifo_empty)
    );

    assign ctrl_rddata_valid = !rdata_fifo_empty;

    // -------------------------------------------------------------------------
    // DFI 5.1 static control/status signal drivers (B-04)
    // These are configuration-time signals (stable during traffic), so they are
    // driven combinationally without a CDC synchronizer. dfi_rddata_dnv is
    // captured for parity/error reporting by the read path.
    // -------------------------------------------------------------------------
    assign dfi_phycsel          = 1'b0;          // single PHY instance
    assign dfi_parity_in        = 1'b0;          // CA parity disabled (opt-in later)
    assign dfi_dram_clk_disable = 2'b00;         // DRAM clocks enabled
    assign dfi_freq_ratio       = cfg_freq_ratio; // reflect configured ratio

    // Read-data not-valid (dnv) is exposed to the read path; tie-off for now
    // so downstream logic can be wired without changing the FIFO datapath.
    logic [1:0] dfi_rddata_dnv_sync;
    always_ff @(posedge ctrl_clk or negedge rst_n) begin
        if (!rst_n) dfi_rddata_dnv_sync <= 2'b00;
        else        dfi_rddata_dnv_sync <= dfi_rddata_dnv;
    end

    // Training state machine
    typedef enum logic [2:0] {
        TRAIN_IDLE,
        TRAIN_WAIT_INIT,
        TRAIN_START,
        TRAIN_RUNNING,
        TRAIN_COMPLETE,
        TRAIN_ERROR
    } train_state_t;

    train_state_t train_state;

    always_ff @(posedge ctrl_clk or negedge rst_n) begin
        if (!rst_n) begin
            train_state    <= TRAIN_IDLE;
            train_complete <= 1'b0;
            train_error    <= 1'b0;
        end else begin
            case (train_state)
                TRAIN_IDLE: begin
                    if (train_start) begin
                        train_state <= TRAIN_WAIT_INIT;
                    end
                end
                TRAIN_WAIT_INIT: begin
                    if (phy_init_complete) begin
                        train_state <= TRAIN_START;
                    end
                end
                TRAIN_START: begin
                    train_state <= TRAIN_RUNNING;
                end
                TRAIN_RUNNING: begin
                    // Simplified - assume training completes after some cycles
                    train_state <= TRAIN_COMPLETE;
                end
                TRAIN_COMPLETE: begin
                    train_complete <= 1'b1;
                    train_state    <= TRAIN_IDLE;
                end
                TRAIN_ERROR: begin
                    train_error <= 1'b1;
                    train_state <= TRAIN_IDLE;
                end
                default: train_state <= TRAIN_IDLE;
            endcase
        end
    end

endmodule
