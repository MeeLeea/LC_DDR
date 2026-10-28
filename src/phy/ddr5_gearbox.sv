// =============================================================================
// Module: ddr5_gearbox
// Description: Bitwidth conversion between user side (256-bit) and DFI (128-bit)
//              Write path: pack 256-bit into 2x128-bit
//              Read path: unpack 2x128-bit into 256-bit
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_gearbox #(
    parameter int USER_W = 256,
    parameter int DFI_W  = 128
)(
    input  logic              clk,
    input  logic              rst_n,

    // Write path (user -> DFI)
    input  logic              wr_user_valid,
    input  logic [USER_W-1:0] wr_user_data,
    output logic              wr_user_ready,

    output logic              wr_dfi_valid,
    output logic [DFI_W-1:0]  wr_dfi_data,
    input  logic              wr_dfi_ready,

    // Read path (DFI -> user)
    input  logic              rd_dfi_valid,
    input  logic [DFI_W-1:0]  rd_dfi_data,
    output logic              rd_dfi_ready,

    output logic              rd_user_valid,
    output logic [USER_W-1:0] rd_user_data,
    input  logic              rd_user_ready
);

    // =========================================================================
    // Write path: 256-bit -> 2x128-bit
    // =========================================================================
    typedef enum logic {WR_PHASE_0, WR_PHASE_1} wr_phase_t;
    wr_phase_t wr_phase;

    logic [DFI_W-1:0] wr_data_hi;  // Upper 128 bits stored

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_phase  <= WR_PHASE_0;
            wr_data_hi <= '0;
        end else begin
            case (wr_phase)
                WR_PHASE_0: begin
                    if (wr_user_valid && wr_user_ready) begin
                        wr_data_hi <= wr_user_data[USER_W-1:DFI_W];
                        wr_phase   <= WR_PHASE_1;
                    end
                end
                WR_PHASE_1: begin
                    if (wr_dfi_valid && wr_dfi_ready) begin
                        wr_phase <= WR_PHASE_0;
                    end
                end
                default: wr_phase <= WR_PHASE_0;
            endcase
        end
    end

    // Write outputs
    assign wr_user_ready = (wr_phase == WR_PHASE_0);

    always_comb begin
        wr_dfi_valid = 1'b0;
        wr_dfi_data  = '0;
        case (wr_phase)
            WR_PHASE_0: begin
                if (wr_user_valid) begin
                    wr_dfi_valid = 1'b1;
                    wr_dfi_data  = wr_user_data[DFI_W-1:0];
                end
            end
            WR_PHASE_1: begin
                wr_dfi_valid = 1'b1;
                wr_dfi_data  = wr_data_hi;
            end
            default: ;
        endcase
    end

    // =========================================================================
    // Read path: 2x128-bit -> 256-bit
    // =========================================================================
    typedef enum logic {RD_PHASE_0, RD_PHASE_1} rd_phase_t;
    rd_phase_t rd_phase;

    logic [DFI_W-1:0] rd_data_lo;  // Lower 128 bits stored

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_phase  <= RD_PHASE_0;
            rd_data_lo <= '0;
        end else begin
            case (rd_phase)
                RD_PHASE_0: begin
                    if (rd_dfi_valid && rd_dfi_ready) begin
                        rd_data_lo <= rd_dfi_data;
                        rd_phase   <= RD_PHASE_1;
                    end
                end
                RD_PHASE_1: begin
                    if (rd_user_valid && rd_user_ready) begin
                        rd_phase <= RD_PHASE_0;
                    end
                end
                default: rd_phase <= RD_PHASE_0;
            endcase
        end
    end

    // Read outputs
    assign rd_dfi_ready = (rd_phase == RD_PHASE_0);

    always_comb begin
        rd_user_valid = 1'b0;
        rd_user_data  = '0;
        case (rd_phase)
            RD_PHASE_0: begin
                // Waiting for first 128-bit beat
            end
            RD_PHASE_1: begin
                if (rd_dfi_valid) begin
                    rd_user_valid = 1'b1;
                    rd_user_data  = {rd_dfi_data, rd_data_lo};
                end
            end
            default: ;
        endcase
    end

endmodule
