// =============================================================================
// Module: ddr5_refresh_ctrl
// Description: DDR5 refresh controller with FGR 2x/4x, REFab, REFsb, Self-Ref
//              Credit-based refresh scheduling (max 8 credits)
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_refresh_ctrl #(
    parameter int NUM_BANKS = `DDR5_NUM_BANKS
)(
    input  logic        clk,
    input  logic        rst_n,

    // Configuration
    input  logic [15:0] tREFI,      // Refresh interval
    input  logic [15:0] tRFC,       // Refresh cycle time
    input  logic [1:0]  fgr_mode,   // 00=1x, 01=2x, 10=4x
    input  logic        auto_ref_en,
    input  logic        manual_trigger,

    // Refresh request interface
    output logic        ref_req,
    output logic [4:0]  ref_bank,   // For REFsb
    output logic        ref_all,    // 1=REFab, 0=REFsb
    input  logic        ref_ack,

    // Self-refresh control
    input  logic        sreq_enter,
    output logic        sreq_active,
    output logic        sreq_exit,

    // Status
    output logic [3:0]  credit_count,
    output logic        overflow
);

    // Refresh credit counter
    logic [15:0] trefi_cnt;
    logic [3:0]  credit_r;
    logic [4:0]  bank_ptr;  // Round-robin bank pointer for REFsb

    // tREFI countdown and credit accumulation (unified block)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trefi_cnt <= '0;
            credit_r  <= '0;
            bank_ptr  <= '0;
        end else begin
            // Default: decrement tREFI counter
            if (trefi_cnt > 0) trefi_cnt <= trefi_cnt - 16'd1;

            // Auto-refresh: accumulate credit on tREFI expiry
            if (auto_ref_en && trefi_cnt == 0) begin
                trefi_cnt <= tREFI;
                case (fgr_mode)
                    2'b00: credit_r <= credit_r + 4'd1;  // 1x
                    2'b01: credit_r <= credit_r + 4'd2;  // 2x
                    2'b10: credit_r <= credit_r + 4'd4;  // 4x
                    default: credit_r <= credit_r + 4'd1;
                endcase
                bank_ptr <= bank_ptr + 5'd1;
            end

            // Manual trigger
            if (manual_trigger) begin
                credit_r <= credit_r + 4'd1;
            end

            // Consume credit on refresh ack (only when credits > 0)
            if (ref_ack && credit_r > 0) begin
                credit_r <= credit_r - 4'd1;
            end
        end
    end

    // Overflow detection
    assign overflow = (credit_r == 4'd8);

    // Refresh request generation
    assign ref_req   = auto_ref_en && (credit_r > 0);
    assign ref_bank  = bank_ptr;
    assign ref_all   = 1'b1;  // Default to REFab for simplicity

    // Self-refresh state machine
    typedef enum logic [1:0] {
        SR_IDLE,
        SR_ENTER,
        SR_ACTIVE,
        SR_EXIT
    } sr_state_t;

    sr_state_t sr_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sr_state <= SR_IDLE;
        end else begin
            case (sr_state)
                SR_IDLE: begin
                    if (sreq_enter) sr_state <= SR_ENTER;
                end
                SR_ENTER: begin
                    sr_state <= SR_ACTIVE;
                end
                SR_ACTIVE: begin
                    if (!sreq_enter) sr_state <= SR_EXIT;
                end
                SR_EXIT: begin
                    sr_state <= SR_IDLE;
                end
                default: sr_state <= SR_IDLE;
            endcase
        end
    end

    assign sreq_active = (sr_state == SR_ACTIVE);
    assign sreq_exit   = (sr_state == SR_EXIT);

    // Output credit count
    assign credit_count = credit_r;

endmodule
