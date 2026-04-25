import params_pkg::*;

module ml_accel_top (
    input logic aclk, aresetn,
    // AXI-Lite
    input  logic [31:0] s_axi_awaddr, input logic s_axi_awvalid, output logic s_axi_awready,
    input  logic [31:0] s_axi_wdata,  input logic s_axi_wvalid,  output logic s_axi_wready,
    output logic s_axi_bvalid,        input logic s_axi_bready,
    input  logic [31:0] s_axi_araddr, input logic s_axi_arvalid, output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,  output logic s_axi_rvalid,  input logic s_axi_rready,
    // AXI-Stream In
    input  logic [31:0] s_axis_tdata, input logic s_axis_tvalid, output logic s_axis_tready,
    // AXI-Stream Out
    output logic [31:0] m_axis_tdata, output logic m_axis_tvalid, output logic m_axis_tlast, input logic m_axis_tready
);
    logic start, infer_done;
    logic signed [ACT_W-1:0] input_acts [0:IN_FEATURES-1];
    logic signed [PSUM_W-1:0] logits [0:OUT_FEATURES-1];
    
    logic [7:0] b_addr; logic b_re; logic signed [WEIGHT_W-1:0] b_dout;
    logic sa_lp, sa_ce, sa_ov;
    logic [$clog2(SA_ROWS)-1:0] sa_lr, sa_lc;
    logic signed [WEIGHT_W-1:0] sa_ld;
    logic signed [ACT_W-1:0] sa_ai [0:SA_ROWS-1];
    logic signed [PSUM_W-1:0] sa_po [0:SA_COLS-1];
    
    // <-- NEW: Internal wire to carry the bias
    logic signed [PSUM_W-1:0] sa_bi [0:SA_COLS-1]; 

    axi_lite_slave u_axil (.*);
    axis_input_slave u_axis_in (.*);
    axis_output_master u_axis_out (.*);

    bram_wrapper u_mem (
        .clk(aclk), .rst_n(aresetn), 
        .re_b(b_re), .addr_b(b_addr), .dout_b(b_dout), 
        .we_a(1'b0), .addr_a(8'h0), .din_a(8'h0)
    );

    controller u_ctrl (
        .clk(aclk), .rst_n(aresetn), .start(start),
        .bram_addr(b_addr), .bram_re(b_re), .bram_dout(b_dout),
        .input_acts(input_acts),
        .sa_load_pulse(sa_lp), .sa_load_row(sa_lr), .sa_load_col(sa_lc), .sa_load_data(sa_ld),
        .sa_compute_en(sa_ce), .sa_act_in(sa_ai),
        .sa_psum_out(sa_po), .sa_output_valid(sa_ov),
        .sa_bias_in(sa_bi),  // <-- NEW: Connected to controller
        .logits(logits), .infer_done(infer_done)
    );

    systolic_array u_sa (
        .clk(aclk), .rst_n(aresetn),
        .load_pulse(sa_lp), .load_row(sa_lr), .load_col(sa_lc), .load_data(sa_ld),
        .compute_en(sa_ce), .act_in(sa_ai),
        .bias_in(sa_bi),     // <-- NEW: Connected to array
        .psum_out(sa_po), .output_valid(sa_ov)
    );

endmodule