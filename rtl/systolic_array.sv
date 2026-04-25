import params_pkg::*;

module systolic_array (
    input logic clk,
    input logic rst_n,
    input logic load_pulse,
    input logic [$clog2(SA_ROWS)-1:0] load_row,
    input logic [$clog2(SA_COLS)-1:0] load_col,
    input logic signed [WEIGHT_W-1:0] load_data,
    input logic compute_en,
    input logic signed [ACT_W-1:0] act_in [0:SA_ROWS-1],
    input logic signed [PSUM_W-1:0] bias_in [0:SA_COLS-1], // <-- NEW PORT
    output logic signed [PSUM_W-1:0] psum_out [0:SA_COLS-1],
    output logic output_valid
);
    logic signed [ACT_W-1:0]  act_h  [0:SA_ROWS-1][0:SA_COLS];
    logic signed [PSUM_W-1:0] psum_v [0:SA_ROWS][0:SA_COLS-1];
    logic signed [ACT_W-1:0]  stagger [0:SA_ROWS-1][0:SA_ROWS-1];

    // Input Staggering (Skewing)
    generate
        for (genvar r = 0; r < SA_ROWS; r++) begin : gen_stagger
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    for (int s = 0; s < SA_ROWS; s++) stagger[r][s] <= '0;
                end else begin
                    stagger[r][0] <= compute_en ? act_in[r] : '0;
                    for (int s = 1; s < SA_ROWS; s++) begin
                        stagger[r][s] <= stagger[r][s-1];
                    end
                end
            end
            assign act_h[r][0] = stagger[r][r];
        end
    endgenerate

    // PE Grid Instantiation
    generate
        for (genvar r = 0; r < SA_ROWS; r++) begin : rows
            for (genvar c = 0; c < SA_COLS; c++) begin : cols
                pe u_pe (
                    .clk(clk), .rst_n(rst_n),
                    .load_weight(load_pulse && (load_row == r) && (load_col == c)),
                    .weight_in(load_data),
                    .act_in(act_h[r][c]),
                    .act_out(act_h[r][c+1]),
                    .psum_in(psum_v[r][c]),
                    .psum_out(psum_v[r+1][c])
                );
            end
        end
    endgenerate

    // Output and Bias Routing
    for (genvar c = 0; c < SA_COLS; c++) begin
        assign psum_v[0][c] = bias_in[c]; // <-- NEW: Feed bias instead of '0
        assign psum_out[c] = psum_v[SA_ROWS][c];
    end

    // Pipeline Latency Tracker
    localparam int LATENCY = SA_ROWS + SA_COLS;
    logic [LATENCY-1:0] v_pipe;

    always_ff @(posedge clk) begin
        if (!rst_n) v_pipe <= '0;
        else v_pipe <= {v_pipe[LATENCY-2:0], compute_en};
    end
    assign output_valid = v_pipe[LATENCY-1];

endmodule