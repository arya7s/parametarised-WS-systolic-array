import params_pkg::*;

module axis_input_slave (
    input  logic aclk, aresetn,
    input  logic [31:0] s_axis_tdata, input logic s_axis_tvalid, output logic s_axis_tready,
    output logic signed [ACT_W-1:0] input_acts [0:IN_FEATURES-1]
);
    assign s_axis_tready = 1'b1;
    always_ff @(posedge aclk) begin
        if (!aresetn) for (int i=0; i<IN_FEATURES; i++) input_acts[i] <= 0;
        else if (s_axis_tvalid) begin
            input_acts[0] <= signed'(s_axis_tdata[7:0]);
            input_acts[1] <= signed'(s_axis_tdata[15:8]);
            input_acts[2] <= signed'(s_axis_tdata[23:16]);
            input_acts[3] <= signed'(s_axis_tdata[31:24]);
        end
    end
endmodule