# Verification Notes

## Verification philosophy

The verification goal is not simply to show that one Iris input produces one correct class. The testbench is designed to expose the control/dataflow behavior of the accelerator and make cycle-level behavior observable.

## Current environment

The checked-in environment is a SystemVerilog testbench (`testbench/testbench.sv`). It drives the DUT through its AXI-facing signals and observes selected internal signals for cycle accounting.

The testbench includes:

- Clock/reset generation at a 100 MHz reference rate.
- AXI-Lite write transactions.
- AXI4-Stream input driving.
- Output-logit capture.
- Expected-class checking.
- FSM-state transition monitoring.
- Systolic-array `load_pulse`, `compute_en`, and `output_valid` monitoring.
- Per-phase cycle accounting.
- Tile-level latency accounting.
- Model-bias loading checks.

## Test categories

| Test | Purpose | Current state |
|---|---|---|
| Directed inference | Validate known vectors and expected classes | Implemented |
| Random input vectors | Exercise a broader signed-int8 input space | Implemented |
| Cycle accounting | Measure AXI/control/compute phases | Implemented |
| Boundary-value testing | Exercise signed-int8 extremes | Planned extension |
| Reset during inference | Check recovery from asynchronous control events | Planned extension |
| Weight reload | Verify consecutive model reconfiguration | Planned extension |
| AXI back-pressure | Exercise `valid/ready` stalls | Planned extension |
| Repeated inference | Detect state/data retention bugs | Planned extension |

## Golden-model principle

The software flow in `python_train_and_inference/` provides the numerical reference. The hardware uses the exported quantized parameters and signed integer arithmetic. This makes it possible to compare:

```text
Python reference
      |
      +---- quantized parameters ----+
                                     |
                                     v
                              RTL simulation
                                     |
                                     v
                              output logits
                                     |
                                     v
                           expected classification
```

The goal is to keep quantization and fixed-point behavior explicit rather than comparing floating-point neural-network outputs directly with integer RTL outputs.

## What should be added next

For a stronger research-quality verification environment, the next steps are:

1. Build a reusable UVM agent for AXI4-Lite.
2. Build a reusable UVM agent for AXI4-Stream.
3. Add a scoreboard against a Python-generated transaction/reference dataset.
4. Add constrained-random signed-int8 corner cases.
5. Add SystemVerilog assertions for AXI handshakes and FSM invariants.
6. Add functional coverage for array dimensions, operand ranges, FSM transitions, and protocol stalls.
7. Run the same test suite across several `SA_ROWS × SA_COLS` configurations.
8. Add automated simulator execution to CI.

This roadmap is more valuable than reporting an unsupported coverage percentage: each metric should come from an actual reproducible run.
