# Verification

The current repository uses a SystemVerilog, cycle-accurate verification environment with a hardware-side reference/golden computation and protocol-level stimulus. The project documentation intentionally does not describe this as UVM.

## Verification scope

- Reset and initialization behavior
- AXI-Lite weight/configuration transactions
- AXI-Stream input/output transactions
- Controller state progression
- Systolic-array output-valid timing
- Quantized arithmetic and signed values
- Expected classification/logit behavior
- Cycle-level latency accounting

## Current evidence

The current testbench (`testbench/testbench.sv`) exercises a single directed test vector: it loads quantized weights and biases, streams the input activations, and compares the resulting hardware classification against a golden expected class computed with the same INT8 arithmetic used in hardware. Cycle-accurate phase counters record timing for weight loading, MAC/drain, and output stages (see [`results.md`](results.md) for the measured cycle breakdown).

Randomized stimulus, a multi-vector regression suite, and corner-case scenarios (back-pressure, reset during inference, repeated inference, exhaustive boundary-value campaigns) are not yet implemented in this testbench. They are identified as future verification extensions rather than claimed as completed coverage.

## Verification philosophy

The verification environment is deliberately separated from the Python model used to train/export the demonstration workload. The Python flow provides the software-side reference, while the RTL testbench observes the hardware protocol and cycle behavior.
