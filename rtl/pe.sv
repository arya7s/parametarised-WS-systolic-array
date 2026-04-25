import params_pkg::*;

module pe (
    input logic clk,
    input logic rst_n,
    input logic load_weight,
    input logic signed [WEIGHT_W-1:0] weight_in,
    input logic signed [ACT_W-1:0] act_in,
    input logic signed [PSUM_W-1:0] psum_in,
    output logic signed [ACT_W-1:0] act_out,
    output logic signed [PSUM_W-1:0] psum_out
);
    logic signed [WEIGHT_W-1:0] weight_reg;

    always_ff @(posedge clk) begin
        if (!rst_n) weight_reg <= '0;
        else if (load_weight) weight_reg <= weight_in;
    end

    // Force DSP usage for ZedBoard efficiency
    (* use_dsp = "yes" *)
    logic signed [PSUM_W-1:0] mac_product;
    assign mac_product = PSUM_W'(weight_reg) * PSUM_W'(act_in);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            psum_out <= '0;
            act_out  <= '0;
        end else begin
            psum_out <= psum_in + mac_product;
            act_out  <= act_in;
        end
    end
endmodule