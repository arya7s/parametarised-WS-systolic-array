import params_pkg::*;

module controller (
    input logic clk,
    input logic rst_n,
    input logic start,

    // BRAM Interface (Weights)
    output logic [7:0] bram_addr,
    output logic bram_re,
    input  logic signed [WEIGHT_W-1:0] bram_dout,

    // AXI Stream Input Buffer
    input logic signed [ACT_W-1:0] input_acts [0:IN_FEATURES-1],

    // Systolic Array Control & Data
    output logic sa_load_pulse,
    output logic [$clog2(SA_ROWS)-1:0] sa_load_row,
    output logic [$clog2(SA_COLS)-1:0] sa_load_col,
    output logic signed [WEIGHT_W-1:0] sa_load_data,
    
    output logic sa_compute_en,
    output logic signed [ACT_W-1:0] sa_act_in [0:SA_ROWS-1],
    input  logic signed [PSUM_W-1:0] sa_psum_out [0:SA_COLS-1],
    input  logic sa_output_valid,
    
    // --> NEW: Bias Routing Port
    output logic signed [PSUM_W-1:0] sa_bias_in [0:SA_COLS-1], 

    // Final Outputs
    output logic signed [PSUM_W-1:0] logits [0:OUT_FEATURES-1],
    output logic infer_done
);

    // FSM States
    typedef enum logic [2:0] {IDLE, LOAD_L1, COMP_L1, RELU, LOAD_L2, COMP_L2, DONE} state_t;
    state_t state, next_state;

    logic [2:0] tile_idx;
    logic [4:0] w_cnt;
    logic signed [ACT_W-1:0] hid_acts [0:HID_FEATURES-1];

    // =========================================================================
    //  BIAS ROM & ROUTING LOGIC
    // =========================================================================
    logic signed [PSUM_W-1:0] bias_rom [0:19];
    
    initial begin
        // Loads exactly 20 lines (16 for L1 + 4 padded for L2)
        $readmemh("biases.mem", bias_rom);
    end

    always_comb begin
        for (int i=0; i<4; i++) begin
            if (state == COMP_L1) 
                // L1 tiles change both input rows and output columns, so bias shifts per tile
                sa_bias_in[i] = bias_rom[tile_idx * 4 + i];
            else if (state == COMP_L2) 
                // FIXED: L2 outputs to stationary columns (0,1,2). Bias stays locked to indices 16-19
                sa_bias_in[i] = bias_rom[16 + i]; 
            else 
                // Clamp to zero during IDLE and LOAD to prevent garbage accumulation
                sa_bias_in[i] = '0;
        end
    end
    // =========================================================================

    // FSM State Register
    always_ff @(posedge clk) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    // FSM Next State Logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE:    if (start) next_state = LOAD_L1;
            LOAD_L1: if (w_cnt == 15) next_state = COMP_L1;
            COMP_L1: if (sa_output_valid) next_state = (tile_idx == 3) ? RELU : LOAD_L1;
            RELU:    next_state = LOAD_L2;
            LOAD_L2: if (w_cnt == 15) next_state = COMP_L2;
            COMP_L2: if (sa_output_valid) next_state = (tile_idx == 3) ? DONE : LOAD_L2;
            DONE:    next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // Counter Logic
    always_ff @(posedge clk) begin
        if (state == IDLE || state == RELU) begin 
            tile_idx <= 0; 
            w_cnt <= 0; 
        end
        else if (state == LOAD_L1 || state == LOAD_L2) begin
            w_cnt <= w_cnt + 1;
        end
        else if (sa_output_valid) begin 
            w_cnt <= 0; 
            tile_idx <= tile_idx + 1; 
        end
    end

    // BRAM Control (Layer 2 weights start at address 64)
    assign bram_re = (state == LOAD_L1 || state == LOAD_L2) && (w_cnt < 16);
    assign bram_addr = (state == LOAD_L1) ? (tile_idx * 16 + w_cnt) : (64 + tile_idx * 16 + w_cnt);

    // Systolic Array Weight Loading Pipeline
    always_ff @(posedge clk) begin
        sa_load_pulse <= bram_re;
        sa_load_data  <= bram_dout;
        sa_load_row   <= w_cnt[3:2];
        sa_load_col   <= w_cnt[1:0];
    end

    // Systolic Array Compute Control
    assign sa_compute_en = (state == COMP_L1 || state == COMP_L2);

    // Route Inputs to Array
    always_comb begin
        for (int i=0; i<SA_ROWS; i++) begin
            if (state == COMP_L1) sa_act_in[i] = input_acts[i];
            else if (state == COMP_L2) sa_act_in[i] = hid_acts[tile_idx * 4 + i];
            else sa_act_in[i] = '0;
        end
    end

    // Capture Layer 1 Outputs & Apply ReLU + Scaling
    always_ff @(posedge clk) begin
        if (state == COMP_L1 && sa_output_valid) begin
            for (int i=0; i<4; i++) begin
                logic signed [PSUM_W-1:0] scaled = sa_psum_out[i] >>> SHIFT_AMT;
                if (scaled < 0) hid_acts[tile_idx * 4 + i] <= 0;
                else if (scaled > 127) hid_acts[tile_idx * 4 + i] <= 127;
                else hid_acts[tile_idx * 4 + i] <= scaled[ACT_W-1:0];
            end
        end
    end

    // Capture Final Logits (Layer 2)
    always_ff @(posedge clk) begin
        if (state == COMP_L2 && sa_output_valid) begin
            for (int i=0; i<4; i++) begin
                if ((tile_idx * 4 + i) < OUT_FEATURES) begin
                    logits[tile_idx * 4 + i] <= sa_psum_out[i];
                end
            end
        end
    end

    assign infer_done = (state == DONE);

endmodule