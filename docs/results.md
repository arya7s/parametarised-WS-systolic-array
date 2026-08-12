# Implementation Results

Target/configuration values are listed separately from measured/reported values. All numbers below are taken directly from the archived Vivado reports in [`screenshots_project/`](../screenshots_project/) or from the cycle-accurate RTL simulation log.

## Target / configuration

| Parameter | Value |
|---|---:|
| FPGA | AMD/Xilinx Zynq-7000 XC7Z020 (xc7z020clg484-1) |
| Board | Avnet ZedBoard |
| Array | 4×4 weight-stationary systolic array (16 PEs) |
| Parallel MAC capacity | 16 MACs/cycle |
| Operand precision | signed INT8 × INT8 |
| Accumulator | signed INT32 |
| Clock target | 100 MHz (10.0 ns period) |

## Post-implementation resource utilization (Vivado)

Source: [`utilization_rpt.jpeg`](../screenshots_project/utilization_rpt.jpeg)

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 1,119 | 53,200 | 2.10% |
| — LUT as Logic | 1,095 | 53,200 | 2.06% |
| — LUT as Distributed RAM | 24 | 17,400 | 0.14% |
| Slice Registers (FF) | 934 | 106,400 | 0.88% |
| Slices | 378 | 13,300 | 2.84% |
| CARRY4 | 184 | 13,300 | 1.38% |
| DSP48E1 | 16 | 220 | 7.27% |
| Block RAM | 0 | 140 | 0.00% |
| Bonded IOBs | 161 | 200 | 80.5% |
| BUFG (Clock) | 1 | 32 | 3.13% |

Notes from the report: the design is register-only (no BRAM is used for weight storage at this scale), and the high IOB utilization reflects a standalone synthesis rather than integration behind the Zynq PS–PL interconnect — both IOB count and power would change once integrated with the processing system.

## Timing (Vivado, post-implementation static timing analysis)

Source: [`timing_rpt.jpeg`](../screenshots_project/timing_rpt.jpeg)

| Check | Worst slack | Failing endpoints | Status |
|---|---:|---:|---|
| Setup (WNS) | +2.488 ns | 0 / 3,118 | PASS |
| Hold (WHS) | +0.117 ns | 0 / 3,118 | PASS |
| Pulse width (WPWS) | +3.750 ns | 0 / 975 | PASS |

Target clock period: 10.0 ns (100 MHz). All checks pass with positive slack; the tool-reported achievable F_max is ~133 MHz. **This is a static-timing-analysis result from Vivado, not a frequency measured on physical hardware** — no bitstream-on-board characterization has been performed.

- Critical setup path: `u_ctrl/FSM_sequential_state_reg[2]_rep/C` → `u_ctrl/hid_psum_reg[1][11]/CE`, 7.133 ns data path delay (14% logic / 86% route), 2 logic levels (LUT5 + LUT3).
- Tightest hold path: `hid_psum_reg[11][6]` → LUT2 (ReLU) → `hid_acts_reg[11][0]`, 0.251 ns data delay, +0.117 ns slack.

## Power (Vivado, post-implementation estimate)

Source: [`power_rpt.jpeg`](../screenshots_project/power_rpt.jpeg)

Total on-chip power: **131 mW** (26 mW dynamic + 105 mW static) at a 26.5°C junction temperature. This is a Vivado power estimate, not a measured on-board figure.

| Component | Power | Share of dynamic |
|---|---:|---:|
| I/O | 15 mW | 57.7% |
| Signals | 5 mW | 19.2% |
| Clocks | 4 mW | 15.4% |
| Slice logic | 2 mW | 7.7% |
| DSPs | <1 mW | <3.8% |
| Static (device) | 105 mW | — |

By hierarchy (dynamic power): `u_ctrl` (controller/FSM/ReLU) 8 mW, `u_sa` (4×4 systolic array) 2 mW, AXI-Lite/AXI-Stream/IOBs 16 mW.

## Simulation-derived latency (demonstration workload)

Source: cycle-accurate RTL testbench (`testbench/testbench.sv`), phase-level cycle counting for one 4→16→3 MLP inference.

| Phase | Cycles | Time @ 100 MHz |
|---|---:|---:|
| AXI-Stream input capture | 2 | 20 ns |
| AXI-Lite start handshake | 4 | 40 ns |
| Layer-1 weight load (4 tiles × 16) | 64 | 640 ns |
| Layer-1 MAC + drain (4 tiles × 9) | 36 | 360 ns |
| ReLU + scale/saturate + bias | 1 | 10 ns |
| Layer-2 weight + bias load (4 tiles × 16) | 64 | 640 ns |
| Layer-2 MAC + drain (4 tiles × 9) | 36 | 360 ns |
| Done state | 1 | 10 ns |
| AXI-Stream output (3 logit beats) | 3 | 30 ns |
| **Total** | **211** | **2.11 μs** |

This is a demonstration-workload latency figure for the tiled 4→16→3 MLP running on the 4×4 array — it is not a general accelerator throughput specification, and it has not been measured on physical hardware.

## Software reference model

The Python/PyTorch/NumPy reference MLP reaches 96.67% test accuracy on a 30-sample held-out Iris split, prior to INT8 quantization and export. This is a software-only metric describing the reference model used to generate weights and expected outputs — it is not a hardware-measured figure.

## Scope of current evidence

- All timing and power figures above come from Vivado static timing analysis / power estimation, not from a bitstream running on physical hardware.
- The RTL testbench currently exercises a single directed test vector with a golden-model comparison (see [`verification.md`](verification.md)); it does not yet include a multi-vector regression suite or randomized stimulus.
