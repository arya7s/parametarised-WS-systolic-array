import params_pkg::*;

module controller (
    input logic clk,
    input logic rst_n,
    input logic start,

    output logic [7:0] bram_addr,
    output logic bram_re,
    input  logic signed [WEIGHT_W-1:0] bram_dout,

    input logic signed [ACT_W-1:0] input_acts [0:IN_FEATURES-1],

    output logic sa_load_pulse,
    output logic [$clog2(SA_ROWS)-1:0] sa_load_row,
    output logic [$clog2(SA_COLS)-1:0] sa_load_col,
    output logic signed [WEIGHT_W-1:0] sa_load_data,
    output logic sa_compute_en,
    output logic signed [ACT_W-1:0] sa_act_in [0:SA_ROWS-1],

    input logic signed [PSUM_W-1:0] sa_psum_out [0:SA_COLS-1],
    input logic sa_output_valid,

    output logic signed [PSUM_W-1:0] logits [0:OUT_FEATURES-1],
    output logic infer_done
);

    typedef enum logic [2:0] {IDLE, LOAD_L1, COMP_L1, RELU, LOAD_L2, COMP_L2, DONE} state_t;
    state_t state, next_state;

    logic [2:0] tile_idx; 
    logic [4:0] w_cnt; 
    
    logic signed [PSUM_W-1:0] hid_psum  [0:HID_FEATURES-1];
    logic signed [ACT_W-1:0]  hid_acts  [0:HID_FEATURES-1];
    logic signed [PSUM_W-1:0] logit_acc [0:OUT_FEATURES-1];

    // Bias ROM: 16 L1 biases + 3 L2 biases + 1 pad = 20 entries
    logic signed [WEIGHT_W-1:0] bias_rom [0:19];
    initial $readmemh("biases.mem", bias_rom);

    // Align load signals with BRAM read latency (1 clock cycle)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sa_load_pulse <= 0;
            sa_load_row   <= 0;
            sa_load_col   <= 0;
        end else begin
            sa_load_pulse <= bram_re;
            sa_load_row   <= w_cnt[3:2];
            sa_load_col   <= w_cnt[1:0];
        end
    end
    assign sa_load_data = bram_dout;

    // Capture Logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i=0; i<HID_FEATURES; i++) hid_psum[i] <= 0;
            for (int i=0; i<OUT_FEATURES; i++) logit_acc[i] <= 0;
        end else begin
            if (state == COMP_L1 && sa_output_valid) begin
                for (int i=0; i<4; i++)
                    hid_psum[tile_idx*4 + i] <= sa_psum_out[i]
                        + {{(PSUM_W-WEIGHT_W){bias_rom[tile_idx*4 + i][WEIGHT_W-1]}},
                           bias_rom[tile_idx*4 + i]};
            end
            if (state == COMP_L2 && sa_output_valid) begin
                for (int i=0; i<OUT_FEATURES; i++) logit_acc[i] <= logit_acc[i] + sa_psum_out[i];
            end
            if (state == IDLE && start) begin
                for (int i=0; i<OUT_FEATURES; i++)
                    logit_acc[i] <= {{(PSUM_W-WEIGHT_W){bias_rom[HID_FEATURES+i][WEIGHT_W-1]}},
                                     bias_rom[HID_FEATURES+i]};
            end
        end
    end

    // Scaling + ReLU + Saturation
    always_ff @(posedge clk) begin
        if (state == RELU) begin
            for (int i=0; i<HID_FEATURES; i++) begin
                automatic logic signed [31:0] scaled = hid_psum[i] >>> SHIFT_AMT;
                if (scaled <= 0) hid_acts[i] <= 8'sd0;
                else if (scaled > 127) hid_acts[i] <= 8'sd127;
                else hid_acts[i] <= 8'(scaled);
            end
        end
    end

    always_ff @(posedge clk) state <= (!rst_n) ? IDLE : next_state;

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

    always_ff @(posedge clk) begin
        if (state == IDLE || state == RELU) begin tile_idx <= 0; w_cnt <= 0; end
        else if (state == LOAD_L1 || state == LOAD_L2) w_cnt <= w_cnt + 1;
        else if (sa_output_valid) begin w_cnt <= 0; tile_idx <= tile_idx + 1; end
    end

    assign bram_re = (state == LOAD_L1 || state == LOAD_L2) && (w_cnt < 16);
    assign bram_addr = (state == LOAD_L1) ? (tile_idx * 16 + w_cnt) : (64 + tile_idx * 16 + w_cnt);

    always_comb begin
        sa_compute_en = (state == COMP_L1 || state == COMP_L2);
        for (int i=0; i<4; i++) begin
            if (state == COMP_L1) sa_act_in[i] = input_acts[i];
            else if (state == COMP_L2) sa_act_in[i] = hid_acts[tile_idx*4 + i];
            else sa_act_in[i] = 0;
        end
    end

    assign logits = logit_acc;
    assign infer_done = (state == DONE);

endmodule
