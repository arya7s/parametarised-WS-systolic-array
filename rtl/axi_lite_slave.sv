import params_pkg::*;

module axi_lite_slave (
    input  logic aclk, aresetn,
    input  logic [31:0] s_axi_awaddr, input logic s_axi_awvalid, output logic s_axi_awready,
    input  logic [31:0] s_axi_wdata,  input logic s_axi_wvalid,  output logic s_axi_wready,
    output logic s_axi_bvalid,        input logic s_axi_bready,
    input  logic [31:0] s_axi_araddr, input logic s_axi_arvalid, output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,  output logic s_axi_rvalid,  input logic s_axi_rready,
    output logic start, input logic infer_done
);
    logic [31:0] ctrl_reg;
    logic aw_ready_reg, w_ready_reg;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            ctrl_reg <= 32'h0;
            s_axi_bvalid <= 1'b0;
            aw_ready_reg <= 1'b1;
            w_ready_reg  <= 1'b1;
        end else begin
            if (s_axi_awvalid && s_axi_awready) aw_ready_reg <= 1'b0;
            if (s_axi_wvalid && s_axi_wready)   w_ready_reg  <= 1'b0;

            if (!aw_ready_reg && !w_ready_reg) begin
                if (s_axi_awaddr[7:0] == 8'h00) ctrl_reg <= s_axi_wdata;
                s_axi_bvalid <= 1'b1;
                aw_ready_reg <= 1'b1;
                w_ready_reg  <= 1'b1;
            end else if (s_axi_bready) s_axi_bvalid <= 1'b0;

            if (ctrl_reg[0]) ctrl_reg[0] <= 1'b0; 
        end
    end
    assign s_axi_awready = aw_ready_reg;
    assign s_axi_wready  = w_ready_reg;

    assign s_axi_arready = 1'b1;
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'h0;
        end else if (s_axi_arvalid) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rdata <= (s_axi_araddr[7:0] == 8'h04) ? {31'h0, infer_done} : ctrl_reg;
        end else if (s_axi_rready) s_axi_rvalid <= 1'b0;
    end
    assign start = ctrl_reg[0];
endmodule