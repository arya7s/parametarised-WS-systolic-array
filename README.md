# ML Accelerator — FPGA-Based Neural Network Inference Engine

A parameterized weight-stationary systolic array GEMM engine for quantized neural network inference, implemented in SystemVerilog on a Xilinx Zynq-7000 SoC (ZedBoard).

---

## Overview

The ML Accelerator is a parameterized FPGA-based inference engine built around a weight-stationary systolic array, designed to accelerate forward passes through small quantized MLPs. The current implementation targets Iris flower classification using a 4→16→3 MLP as a proof-of-concept, demonstrating end-to-end hardware ML inference with:

- Parameterized RTL in SystemVerilog
- 4×4 systolic array with 16 parallel int8 MACs
- AXI4-Lite and AXI4-Stream interfaces
- UVM functional verification targeting 85–95% coverage

This project is part of third-year ECE coursework aligned with VLSI Design objectives.

---

## Architecture

```
Host (ARM / Testbench)
        |
        |-- AXI4-Lite --> Weight/Config Registers
        |
        +-- AXI4-Stream --> [ Input Buffer ]
                                    |
                               [ 4x4 Systolic Array ]
                               |  Weight-Stationary   |
                               |  int8 x int8 -> int32 |
                                    |
                              [ ReLU (Hidden Layer) ]
                                    |
                               [ 4x4 Systolic Array ]
                               |   Output Layer       |
                                    |
                          AXI4-Stream --> [ 3 int32 Logits ]
```

### Current MLP Configuration (Iris)

| Layer  | Size | Activation | Precision                     |
|--------|------|------------|-------------------------------|
| Input  | 4    | —          | int8                          |
| Hidden | 16   | ReLU       | int8 (weights), int32 (accum) |
| Output | 3    | —          | int32 logits                  |

- **Dataset**: Iris (150 samples, 3 classes: Setosa / Versicolor / Virginica)
- **Quantization**: Post-training, weights clamped and rounded to int8; features scaled ×20 after StandardScaler
- **Bias**: Not used (`bias=False` throughout)

---

## RTL Module Hierarchy

```
top.sv
├── axi_lite_slave.sv       AXI4-Lite weight/config loading
├── axi_stream_slave.sv     AXI4-Stream input activations
├── axi_stream_master.sv    AXI4-Stream output logits
├── controller.sv           FSM: IDLE -> LOAD_L1 -> COMP_L1 -> RELU -> LOAD_L2 -> COMP_L2 -> DONE
│   └── systolic_array.sv   4×4 generate loop with input stagger flip-flops
│       └── pe.sv           Single PE: int8 MAC, weight register, partial sum pipeline
└── relu.sv                 Parameterized combinational ReLU (standalone module)

params_pkg.sv               Shared parameters and type definitions
```

### Key Design Parameters

| Parameter          | Value               |
|--------------------|---------------------|
| Systolic array     | 4×4                 |
| MACs per cycle     | 16                  |
| Clock target       | 100 MHz             |
| Dataflow           | Weight-Stationary   |
| Weight storage     | Registers (no BRAM) |
| Accumulator width  | 32-bit signed       |
| End-to-end latency | ~200 clock cycles   |

---

## FPGA Target

| Resource    | Specification                  |
|-------------|--------------------------------|
| Board       | Avnet ZedBoard                 |
| SoC         | Xilinx XC7Z020 (Zynq-7000)     |
| LUTs        | 53,200 available               |
| DSP Slices  | 220 available (16 used)        |
| BRAM        | 0 blocks used (140 available)  |
| ARM Core    | Dual Cortex-A9 (PS side)       |
| EDA Tool    | Xilinx Vivado 2023.x / 2024.x  |

---

## Repository Structure

```
parametrised-WS-systolic-array/
├── rtl/                            SystemVerilog RTL source files
│   ├── params_pkg.sv
│   ├── pe.sv
│   ├── systolic_array.sv
│   ├── relu.sv
│   ├── controller.sv
│   ├── axi_lite_slave.sv
│   ├── axi_stream_slave.sv
│   ├── axi_stream_master.sv
│   └── top.sv
├── testbench/                      UVM testbench environment
│   └── tb_top.sv
├── python_train_and_inference/     PyTorch training and inference scripts
│   └── iris_training.py
├── weight_and_biases/              Quantized weight .mem files
│   ├── weights_layer1.mem
│   ├── weights_layer2.mem
│   └── ...
├── screenshots_project/            Architecture diagrams and simulation waveforms
└── README.md
```

---

## Inference Latency Breakdown

End-to-end latency from input submission to output logit reception is **200 clock cycles** at 100 MHz (~2 µs):

| Phase                         | Cycles  |
|-------------------------------|---------|
| AXI-Lite start handshake      | 2       |
| AXI-Stream input capture      | 1       |
| IDLE (FSM initialisation)     | 1       |
| Layer 1 GEMM (4 tiles × 24)   | 96      |
| ReLU                          | 1       |
| Layer 2 GEMM (4 tiles × 24)   | 96      |
| DONE state                    | 1       |
| AXI-Stream output (3 logits)  | 3       |
| **Total**                     | **200** |

---

## Verification

Simulation is performed using **Questa Intel FPGA Starter Edition 2024.3** with **UVM-1.2**.

### Test Suite

| Test Class                    | Description                                   | Status   |
|-------------------------------|-----------------------------------------------|----------|
| `ml_accel_multi_test`         | 3 directed vectors, one per output class      | Pass     |
| `ml_accel_random_test`        | 10 random int8 input vectors                  | Pass     |
| `ml_accel_edge_test`          | Boundary values (0x00, 0x7F, 0x80, 0xFF)      | Planned  |
| `ml_accel_stress_test`        | 100+ back-to-back inferences                  | Planned  |
| `ml_accel_reset_test`         | Mid-inference reset assertion                 | Planned  |
| `ml_accel_weight_reload_test` | Weight reload between consecutive inferences  | Planned  |
| `ml_accel_backpressure_test`  | AXI-Stream output back-pressure stall         | Planned  |
| `ml_accel_input_stall_test`   | AXI-Stream input stall mid-transfer           | Planned  |
| `ml_accel_protocol_test`      | AXI handshake protocol corner cases           | Planned  |
| `ml_accel_repeat_test`        | Repeated identical input vector               | Planned  |

### Coverage Goals

| Covergroup                 | Target                     |
|----------------------------|----------------------------|
| Input feature bins (int8)  | All 8 bins exercised       |
| Output argmax distribution | All 3 classes observed     |
| FSM state transitions      | 100%                       |
| AXI handshake conditions   | All valid/ready combinations |
| **Overall functional**     | **85–95%**                 |

---

## Getting Started

### Dependencies

```bash
pip install torch scikit-learn numpy
```

### Training and Weight Export

```bash
cd python_train_and_inference/
python iris_training.py
```

The script loads the Iris dataset, applies StandardScaler with ×20 feature scaling to int8, trains a 4→16→3 MLP with `bias=False`, quantizes weights via clamp and round, and exports `.mem` files with one int8 value per line.

### Running Simulation

```bash
# From the testbench/ directory
vlog -sv +incdir+../rtl ../rtl/*.sv tb_top.sv
vsim -c tb_top -do "run -all; quit"
```

Questa Intel FPGA Starter Edition is available at no cost with a standard Intel account registration.

---

## Design Decisions

| Decision           | Choice                    | Rationale                                          |
|--------------------|---------------------------|----------------------------------------------------|
| Dataflow           | Weight-Stationary         | Minimises weight re-loading overhead for small models |
| Accumulator width  | 32-bit signed             | Prevents overflow across int8×int8 accumulation chains |
| BRAM usage         | None (register arrays)    | Model footprint under 200 bytes; BRAM unnecessary  |
| Bias terms         | Omitted                   | Reduces hardware complexity; sufficient accuracy on Iris MLP |
| ReLU implementation| Inline in FSM S_RELU state| Reduces inter-module wiring at this design scale   |
| Synthesis tool     | Xilinx Vivado             | Native support for Zynq-7000 target                |
| Simulation tool    | Questa FSE                | Full UVM-1.2 support; no institutional licence required |

---

## Reference Material

Architecture diagrams, simulation waveforms, and synthesis results are available in the [`screenshots_project/`](screenshots_project/) directory.

---

## References

- Fisher, R.A. (1936). Iris dataset, via `sklearn.datasets`
- Accellera Systems Initiative. UVM-1.2 Class Reference
- Xilinx / AMD. Zynq-7000 SoC Technical Reference Manual
- Avnet. ZedBoard Hardware User Guide

---

*ECE Third Year — VLSI Design Track*
