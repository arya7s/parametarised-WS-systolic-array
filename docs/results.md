# Implementation Results

Measured implementation reports are preserved in `screenshots_project/`. This page is the index for the corresponding evidence.

## Current target

- FPGA: Zynq-7000 XC7Z020 / Avnet ZedBoard
- Clock target: 100 MHz
- Systolic array: 4×4
- Datapath: signed INT8 × INT8 → INT32
- Dataflow: weight-stationary

## Evidence

| Artifact | Purpose |
|---|---|
| `utilization_rpt.jpeg` | Vivado resource utilization summary |
| `timing_rpt.jpeg` | Vivado timing/clock report |
| `power_rpt.jpeg` | Vivado power estimate |
| `implementation.jpeg` | Implementation result / design view |
| `schematic.jpeg` | Synthesized schematic |
| `simulation.jpeg` | Cycle-accurate RTL simulation |
| `uvm_tests.jpeg` | Verification/test evidence retained from project development |

Numeric values are intentionally reported from the archived reports rather than inferred from screenshots. The README distinguishes design targets from measured implementation results.