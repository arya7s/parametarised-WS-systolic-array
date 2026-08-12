# Reproducibility

## Software flow

1. Install the Python dependencies listed in the repository README.
2. Run the training/export script to produce quantized model parameters.
3. Place the generated memory initialization files in `weight_and_biases/`.
4. Compile the SystemVerilog RTL and testbench with a simulator supporting the required SystemVerilog features.
5. Run the cycle-accurate tests and compare captured results against the expected software-side behavior.
6. For FPGA implementation, import the RTL into Vivado, target the Zynq-7000 XC7Z020, apply the clock constraint, synthesize/implement, and archive the generated timing, utilization, and power reports.

## Design target versus measured result

**Target** values (such as the 100 MHz clock) describe intended configuration. **Measured** values refer only to numbers actually present in the archived implementation reports, keeping design intent separate from implementation results.
