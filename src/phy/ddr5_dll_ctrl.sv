// =============================================================================
// Module: ddr5_dll_ctrl
// Description: Digital DLL (Delay-Locked Loop) controller
//              Provides 256-step delay control for clock/data alignment
//              Supports coarse and fine locking modes
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_dll_ctrl #(
    parameter int DLL_BITS = `PHY_DLL_BITS,
    parameter int DLL_STEPS = `PHY_DLL_STEPS
)(
    input  logic        clk,
    input  logic        rst_n,

    // Control interface
    input  logic        dll_en,
    input  logic        dll_reset,
    output logic        dll_locked,
    output logic [DLL_BITS-1:0] dll_delay_code,

    // Phase detector input (from PHY analog)
    input  logic        phase_early,
    input  logic        phase_late,

    // Status
    output logic [7:0]  dll_lock_count,
    output logic        dll_lock_fail
);

    // DLL state machine
    typedef enum logic [2:0] {
        DLL_IDLE,
        DLL_COARSE,
        DLL_FINE,
        DLL_LOCK_CHECK,
        DLL_LOCKED,
        DLL_TRACKING
    } dll_state_t;

    dll_state_t state;

    // Delay code register
    logic [DLL_BITS-1:0] delay_code;
    logic [DLL_BITS-1:0] delay_code_next;

    // Lock counter
    logic [7:0] lock_cnt;
    logic [7:0] lock_cnt_next;

    // Coarse search counter
    logic [DLL_BITS-1:0] coarse_cnt;

    // Fine search offset
    logic signed [4:0] fine_offset;

    // Phase error detection
    logic phase_error;
    assign phase_error = phase_early ^ phase_late;

    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= DLL_IDLE;
            delay_code     <= '0;
            lock_cnt       <= '0;
            coarse_cnt     <= '0;
            fine_offset    <= '0;
            dll_locked     <= 1'b0;
            dll_lock_fail  <= 1'b0;
        end else begin
            case (state)
                DLL_IDLE: begin
                    if (dll_en && !dll_reset) begin
                        state       <= DLL_COARSE;
                        coarse_cnt  <= '0;
                        delay_code  <= 8'h80;  // Start at midpoint
                    end
                end

                DLL_COARSE: begin
                    // Binary search for coarse lock
                    if (coarse_cnt < 7) begin
                        if (phase_early) begin
                            delay_code <= delay_code + (8'h80 >> coarse_cnt);
                        end else begin
                            delay_code <= delay_code - (8'h80 >> coarse_cnt);
                        end
                        coarse_cnt <= coarse_cnt + 1;
                    end else begin
                        state       <= DLL_FINE;
                        fine_offset <= -5'sd16;
                    end
                end

                DLL_FINE: begin
                    // Linear search for fine lock
                    if (fine_offset <= 5'sd16) begin
                        delay_code  <= delay_code + fine_offset[4:0];
                        fine_offset <= fine_offset + 5'sd1;
                    end else begin
                        state    <= DLL_LOCK_CHECK;
                        lock_cnt <= '0;
                    end
                end

                DLL_LOCK_CHECK: begin
                    // Verify lock stability
                    if (!phase_error) begin
                        if (lock_cnt == 8'h64) begin  // 100 cycles stable
                            state      <= DLL_LOCKED;
                            dll_locked <= 1'b1;
                        end else begin
                            lock_cnt <= lock_cnt + 1;
                        end
                    end else begin
                        lock_cnt <= '0;
                        if (lock_cnt == 8'hFF) begin
                            state         <= DLL_IDLE;
                            dll_lock_fail <= 1'b1;
                        end
                    end
                end

                DLL_LOCKED: begin
                    state <= DLL_TRACKING;
                end

                DLL_TRACKING: begin
                    // Continuous tracking mode
                    if (phase_early && delay_code > 0) begin
                        delay_code <= delay_code - 1;
                    end else if (phase_late && delay_code < 8'hFF) begin
                        delay_code <= delay_code + 1;
                    end

                    if (dll_reset || !dll_en) begin
                        state      <= DLL_IDLE;
                        dll_locked <= 1'b0;
                    end
                end

                default: state <= DLL_IDLE;
            endcase

            // Reset handling
            if (dll_reset) begin
                state         <= DLL_IDLE;
                delay_code    <= '0;
                dll_locked    <= 1'b0;
                dll_lock_fail <= 1'b0;
            end
        end
    end

    assign dll_delay_code = delay_code;
    assign dll_lock_count = lock_cnt;

endmodule
