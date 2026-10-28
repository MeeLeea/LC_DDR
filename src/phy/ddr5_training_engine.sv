// =============================================================================
// Module: ddr5_training_engine
// Description: DDR5 PHY training engine with 7-step FSM
//              Steps: CA -> WL -> RGT -> RDQ -> WDQ -> Vref -> DFE
//              Each step sweeps delay/voltage, finds valid window, sets center
// =============================================================================
`include "ddr5_defines.svh"

module ddr5_training_engine #(
    parameter int DLL_BITS = `PHY_DLL_BITS,
    parameter int NUM_STEPS = `PHY_TRAIN_STEPS
)(
    input  logic        clk,
    input  logic        rst_n,

    // Control interface
    input  logic        train_start,
    input  logic        train_abort,
    input  logic [2:0]  step_select,   // 0=all, 1=CA, 2=WL, ...
    input  logic [15:0] timeout_ms,

    // DLL interface
    output logic [DLL_BITS-1:0] dll_delay_code,
    input  logic        dll_locked,

    // PHY pattern interface (simplified)
    output logic        pattern_wr_en,
    output logic [31:0] pattern_data,
    input  logic        pattern_rd_valid,
    input  logic [31:0] pattern_rd_data,
    input  logic        pattern_pass,

    // Training result registers
    output logic [7:0]  ca_delay_result,
    output logic [7:0]  wl_delay_result [8],
    output logic [7:0]  rgt_delay_result [8],
    output logic [7:0]  rdq_delay_result [32],
    output logic [7:0]  wdq_delay_result [32],
    output logic [6:0]  vref_code_result,
    output logic [7:0]  dfe_tap_result [4],

    // Status
    output logic        train_in_progress,
    output logic        train_complete,
    output logic        train_error,
    output logic [2:0]  cur_step,
    output logic [7:0]  progress_pct,
    output logic [7:0]  error_code
);

    // Training FSM states
    typedef enum logic [4:0] {
        ST_IDLE,
        ST_CA_SWEEP,
        ST_CA_DONE,
        ST_WL_SWEEP,
        ST_WL_DONE,
        ST_RGT_SWEEP,
        ST_RGT_DONE,
        ST_RDQ_SWEEP,
        ST_RDQ_DONE,
        ST_WDQ_SWEEP,
        ST_WDQ_DONE,
        ST_VREF_SWEEP,
        ST_VREF_DONE,
        ST_DFE_SWEEP,
        ST_DFE_DONE,
        ST_COMPLETE,
        ST_ERROR
    } train_state_t;

    train_state_t state, state_next;

    // Sweep counter and window tracking
    logic [DLL_BITS-1:0] sweep_cnt;
    logic [DLL_BITS-1:0] window_min, window_max;
    logic                window_found;
    logic [15:0]         timeout_cnt;
    logic [2:0]          byte_lane;
    logic [4:0]          bit_idx;

    // Timeout counter (approximate ms counting at ctrl_clk)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timeout_cnt <= '0;
        else if (state == ST_IDLE)
            timeout_cnt <= '0;
        else if (state_next != state)
            timeout_cnt <= '0;
        else
            timeout_cnt <= timeout_cnt + 16'd1;
    end

    // Timeout detection
    logic timeout_flag;
    assign timeout_flag = (timeout_cnt >= (timeout_ms * 16'd600)); // Approximate

    // Main FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= state_next;
        end
    end

    // Sweep counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sweep_cnt    <= '0;
            window_min   <= 8'hFF;
            window_max   <= '0;
            window_found <= 1'b0;
        end else if (state != state_next) begin
            sweep_cnt    <= '0;
            window_min   <= 8'hFF;
            window_max   <= '0;
            window_found <= 1'b0;
        end else if (pattern_pass && !window_found) begin
            if (sweep_cnt < window_min) window_min <= sweep_cnt;
            window_max   <= sweep_cnt;
            window_found <= 1'b1;
            sweep_cnt    <= sweep_cnt + 1;
        end else begin
            sweep_cnt <= sweep_cnt + 1;
        end
    end

    // Next state logic
    always_comb begin
        state_next = state;
        case (state)
            ST_IDLE: begin
                if (train_start) state_next = ST_CA_SWEEP;
            end
            ST_CA_SWEEP: begin
                if (sweep_cnt == 8'hFF || timeout_flag)
                    state_next = timeout_flag ? ST_ERROR : ST_CA_DONE;
            end
            ST_CA_DONE:   state_next = ST_WL_SWEEP;
            ST_WL_SWEEP: begin
                if (sweep_cnt == 8'hFF || timeout_flag)
                    state_next = timeout_flag ? ST_ERROR : ST_WL_DONE;
            end
            ST_WL_DONE:   state_next = ST_RGT_SWEEP;
            ST_RGT_SWEEP: begin
                if (sweep_cnt == 8'hFF || timeout_flag)
                    state_next = timeout_flag ? ST_ERROR : ST_RGT_DONE;
            end
            ST_RGT_DONE:  state_next = ST_RDQ_SWEEP;
            ST_RDQ_SWEEP: begin
                if (sweep_cnt == 8'hFF || timeout_flag)
                    state_next = timeout_flag ? ST_ERROR : ST_RDQ_DONE;
            end
            ST_RDQ_DONE:  state_next = ST_WDQ_SWEEP;
            ST_WDQ_SWEEP: begin
                if (sweep_cnt == 8'hFF || timeout_flag)
                    state_next = timeout_flag ? ST_ERROR : ST_WDQ_DONE;
            end
            ST_WDQ_DONE:  state_next = ST_VREF_SWEEP;
            ST_VREF_SWEEP: begin
                if (sweep_cnt == 8'h7F || timeout_flag)
                    state_next = timeout_flag ? ST_ERROR : ST_VREF_DONE;
            end
            ST_VREF_DONE: state_next = ST_DFE_SWEEP;
            ST_DFE_SWEEP: begin
                if (sweep_cnt == 8'hFF || timeout_flag)
                    state_next = timeout_flag ? ST_ERROR : ST_DFE_DONE;
            end
            ST_DFE_DONE:  state_next = ST_COMPLETE;
            ST_COMPLETE:  state_next = ST_IDLE;
            ST_ERROR:     state_next = ST_IDLE;
            default:      state_next = ST_IDLE;
        endcase
        if (train_abort) state_next = ST_IDLE;
    end

    // DLL delay code output (sweep value)
    assign dll_delay_code = sweep_cnt;

    // Pattern generation
    assign pattern_wr_en = (state >= ST_CA_SWEEP && state <= ST_DFE_SWEEP);
    assign pattern_data  = 32'hDEAD_BEEF; // Training pattern

    // Result registers (simplified - store center of window)
    logic [DLL_BITS-1:0] center_val;
    assign center_val = (window_min + window_max) >> 1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ca_delay_result <= '0;
            vref_code_result <= '0;
            for (int i = 0; i < 8; i++) begin
                wl_delay_result[i]  <= '0;
                rgt_delay_result[i] <= '0;
            end
            for (int i = 0; i < 32; i++) begin
                rdq_delay_result[i] <= '0;
                wdq_delay_result[i] <= '0;
            end
            for (int i = 0; i < 4; i++)
                dfe_tap_result[i] <= '0;
        end else begin
            if (state == ST_CA_DONE)  ca_delay_result <= center_val;
            if (state == ST_VREF_DONE) vref_code_result <= center_val[6:0];
        end
    end

    // Status outputs
    assign train_in_progress = (state != ST_IDLE) && (state != ST_COMPLETE) && (state != ST_ERROR);
    assign train_complete    = (state == ST_COMPLETE);
    assign train_error       = (state == ST_ERROR);
    assign error_code        = timeout_flag ? 8'h01 : 8'h00;

    // Progress calculation
    always_comb begin
        case (state)
            ST_IDLE:       progress_pct = 8'd0;
            ST_CA_SWEEP:   progress_pct = 8'd5;
            ST_CA_DONE:    progress_pct = 8'd14;
            ST_WL_SWEEP:   progress_pct = 8'd20;
            ST_WL_DONE:    progress_pct = 8'd28;
            ST_RGT_SWEEP:  progress_pct = 8'd35;
            ST_RGT_DONE:   progress_pct = 8'd42;
            ST_RDQ_SWEEP:  progress_pct = 8'd50;
            ST_RDQ_DONE:   progress_pct = 8'd57;
            ST_WDQ_SWEEP:  progress_pct = 8'd65;
            ST_WDQ_DONE:   progress_pct = 8'd72;
            ST_VREF_SWEEP: progress_pct = 8'd80;
            ST_VREF_DONE:  progress_pct = 8'd87;
            ST_DFE_SWEEP:  progress_pct = 8'd93;
            ST_DFE_DONE:   progress_pct = 8'd98;
            ST_COMPLETE:   progress_pct = 8'd100;
            default:       progress_pct = 8'd0;
        endcase
    end

    assign cur_step = state[2:0];

endmodule
