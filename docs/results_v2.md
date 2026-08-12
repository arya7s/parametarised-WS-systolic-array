# Implementation Results

The repository contains archived Vivado evidence under `screenshots_project/`. The current documentation deliberately distinguishes **design targets** from **measured results**.

## Design target

| Metric | Target / configuration |
|---|---|
| FPGA | AMD/Xilinx Zynq-7000 XC7Z020 |
| Board | Avnet ZedBoard |
| Array | 4×4 weight-stationary systolic array |
| Operands | signed INT8 × INT8 |
| Accumulator | INT32 |
| Clock | 100 MHz target |
| Parallel MAC capacity | 16 MACs/cycle |

## Archived implementation evidence

| Evidence | File |
|---|---|
| Resource utilization | [`utilization_rpt.jpeg`](../screenshots_project/utilization_rpt.jpeg) |
| Timing analysis | [`timing_rpt.jpeg`](../screenshots_project/timing_rpt.jpeg) |
| Power estimate | [`power_rpt.jpeg`](../screenshots_project/power_rpt.jpeg) |
| Implementation view | [`implementation.jpeg`](../screenshots_project/implementation.jpeg) |
| Synthesized schematic | [`schematic.jpeg`](../screenshots_project/schematic.jpeg) |
| Cycle-accurate simulation | [`simulation.jpeg`](../screenshots_project/simulation.jpeg) |

Exact numerical values should be read from the archived Vivado reports above. They are not repeated here from memory or estimated from screenshots.
