# Admissions-facing interpretation

This repository is best presented as a hardware architecture and RTL implementation project rather than as an application-specific machine-learning project.

The strongest technical themes are:

- parameterized RTL and generate-based hardware construction;
- weight-stationary systolic dataflow;
- signed fixed-point/int8 arithmetic with wider accumulation;
- AXI4-Lite and AXI4-Stream interface integration;
- cycle-level control and latency accounting;
- FPGA synthesis/implementation evidence;
- software-to-hardware model export and verification.

The Iris classifier exists only to provide a compact end-to-end workload through which those hardware concepts can be exercised and measured.
