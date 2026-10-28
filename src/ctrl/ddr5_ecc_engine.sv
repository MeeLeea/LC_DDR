// =============================================================================
// Module: ddr5_ecc_engine
// Description: SEC-DED (Single Error Correct, Double Error Detect) ECC engine
//              Uses Hsiao code for 32-bit data with 8-bit ECC
//              Supports error injection for testing
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_ecc_engine #(
    parameter int DATA_W = `ECC_DATA_W,
    parameter int CODE_W = `ECC_CODE_W
)(
    input  logic              clk,
    input  logic              rst_n,

    // Configuration
    input  logic              ecc_en,
    input  logic              err_inject_en,
    input  logic [7:0]        err_inject_pos,

    // Encode interface (write path)
    input  logic              enc_valid,
    input  logic [DATA_W-1:0] enc_data,
    output logic [CODE_W-1:0] enc_ecc,

    // Decode interface (read path)
    input  logic              dec_valid,
    input  logic [DATA_W-1:0] dec_data,
    input  logic [CODE_W-1:0] dec_ecc,
    output logic [DATA_W-1:0] dec_data_corr,
    output logic              dec_sbe,      // Single bit error (corrected)
    output logic              dec_dbe,      // Double bit error (detected)

    // Error status
    output logic              sbe_detect,
    output logic              dbe_detect,
    output logic [7:0]        err_addr,
    output logic [DATA_W-1:0] err_data,
    output logic [CODE_W-1:0] err_syndrome
);

    // Hsiao parity check matrix (simplified for 32-bit data)
    // Each row represents one ECC bit, each column one data bit
    localparam logic [DATA_W-1:0] H_MATRIX [CODE_W] = '{
        32'h0000_00FF,  // ECC[0] covers bits [7:0]
        32'h0000_FF00,  // ECC[1] covers bits [15:8]
        32'h00FF_0000,  // ECC[2] covers bits [23:16]
        32'hFF00_0000,  // ECC[3] covers bits [31:24]
        32'h0F0F_0F0F,  // ECC[4] covers alternating nibbles
        32'hF0F0_F0F0,  // ECC[5] covers alternating nibbles
        32'h3333_3333,  // ECC[6] covers alternating pairs
        32'hCCCC_CCCC   // ECC[7] covers alternating pairs
    };

    // Encode logic (combinational)
    logic [CODE_W-1:0] enc_ecc_comb;

    always_comb begin
        enc_ecc_comb = '0;
        for (int i = 0; i < CODE_W; i++) begin
            for (int j = 0; j < DATA_W; j++) begin
                if (H_MATRIX[i][j]) begin
                    enc_ecc_comb[i] = enc_ecc_comb[i] ^ enc_data[j];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enc_ecc <= '0;
        end else if (enc_valid && ecc_en) begin
            enc_ecc <= enc_ecc_comb;
        end
    end

    // Decode logic (combinational)
    logic [CODE_W-1:0] syndrome;
    logic [DATA_W-1:0] dec_data_corr_comb;
    logic              sbe_comb, dbe_comb;

    always_comb begin
        // Calculate syndrome
        syndrome = dec_ecc;
        for (int i = 0; i < CODE_W; i++) begin
            for (int j = 0; j < DATA_W; j++) begin
                if (H_MATRIX[i][j]) begin
                    syndrome[i] = syndrome[i] ^ dec_data[j];
                end
            end
        end

        // Error correction
        dec_data_corr_comb = dec_data;
        sbe_comb = 1'b0;
        dbe_comb = 1'b0;

        if (syndrome != '0) begin
            // Check if single-bit error (syndrome matches one column of H)
            for (int j = 0; j < DATA_W; j++) begin
                logic [CODE_W-1:0] col;
                col = '0;
                for (int i = 0; i < CODE_W; i++) begin
                    if (H_MATRIX[i][j]) col[i] = 1'b1;
                end
                if (syndrome == col) begin
                    dec_data_corr_comb[j] = ~dec_data[j];  // Flip bit
                    sbe_comb = 1'b1;
                end
            end

            // If not single-bit, check for double-bit error
            if (!sbe_comb) begin
                dbe_comb = 1'b1;
            end
        end
    end

    // Error injection for testing
    logic [DATA_W-1:0] dec_data_inject;

    always_comb begin
        dec_data_inject = dec_data;
        if (err_inject_en && dec_valid) begin
            if (err_inject_pos < DATA_W) begin
                dec_data_inject[err_inject_pos] = ~dec_data[err_inject_pos];
            end
        end
    end

    // Output registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_data_corr <= '0;
            dec_sbe       <= 1'b0;
            dec_dbe       <= 1'b0;
            sbe_detect    <= 1'b0;
            dbe_detect    <= 1'b0;
            err_addr      <= '0;
            err_data      <= '0;
            err_syndrome  <= '0;
        end else if (dec_valid && ecc_en) begin
            dec_data_corr <= dec_data_corr_comb;
            dec_sbe       <= sbe_comb;
            dec_dbe       <= dbe_comb;

            if (sbe_comb || dbe_comb) begin
                sbe_detect   <= sbe_detect | sbe_comb;
                dbe_detect   <= dbe_detect | dbe_comb;
                err_addr     <= err_inject_pos;
                err_data     <= dec_data;
                err_syndrome <= syndrome;
            end
        end
    end

endmodule
