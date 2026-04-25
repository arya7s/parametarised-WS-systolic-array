import params_pkg::*;

module axis_output_master (
    input  logic aclk, aresetn,
    output logic [31:0] m_axis_tdata, output logic m_axis_tvalid, output logic m_axis_tlast,
    input  logic m_axis_tready,
    input  logic signed [PSUM_W-1:0] logits [0:OUT_FEATURES-1],
    input  logic infer_done
);
    logic [1:0] count;
    logic sending;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            count <= 0; sending <= 0; m_axis_tvalid <= 0;
        end else if (infer_done) begin
            sending <= 1; m_axis_tvalid <= 1; count <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            if (count == 2) begin
                sending <= 0; m_axis_tvalid <= 0;
            end else count <= count + 1;
        end
    end

    assign m_axis_tdata = logits[count];
    assign m_axis_tlast = (count == 2);
endmodule