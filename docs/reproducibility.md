# Reproducibility

## Software flow

1. Install the Python dependencies listed in the repository README.
2. Run the training/export script to produce quantized model parameters.
3. Place the generated memory initialization files in `weight_and_biases/`.
4. Compile the SystemVerilog RTL and testbench with a simulator supporting the required SystemVerilog features.
5. Run the cycle-accurate tests and compare captured results against the expected software-side behavior.
6. For FPGA implementation, import the RTL into Vivado, target the Zynq-7000 XC7Z020, apply the clock constraint, synthesize/implement, and archive the generated timing, utilization, and power reports.

## Design target versus measured result

The README uses the term **target** for intended values such as 100 MHz. It uses **measured** only for values actually present in archived implementation reports. This distinction is maintained to avoid presenting assumptions as experimental results.
