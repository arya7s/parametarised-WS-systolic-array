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

The testbench includes directed and randomized input tests plus cycle/phase monitors. Additional corner cases such as back-pressure, reset during inference, repeated inference, and exhaustive boundary-value campaigns are identified as future verification extensions rather than claimed as completed coverage.

## Verification philosophy

The verification environment is deliberately separated from the Python model used to train/export the demonstration workload. The Python flow provides the software-side reference, while the RTL testbench observes the hardware protocol and cycle behavior.
