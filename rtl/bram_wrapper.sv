import params_pkg::*;

module bram_wrapper (
    input logic clk,
    input logic rst_n,
    input logic re_b,
    input logic [7:0] addr_b,
    output logic signed [WEIGHT_W-1:0] dout_b,
    input logic we_a,
    input logic [7:0] addr_a,
    input logic signed [WEIGHT_W-1:0] din_a
);
    logic signed [WEIGHT_W-1:0] ram [0:255];

    always_ff @(posedge clk) begin
        if (we_a) ram[addr_a] <= din_a;
    end

    always_ff @(posedge clk) begin
        if (re_b) dout_b <= ram[addr_b];
    end

    initial begin
        // Ensure weights are exported as hex strings from Python
        $readmemh("weights_layer1.mem", ram, 0, 63);
        $readmemh("weights_layer2.mem", ram, 64, 127);
    end
endmodule