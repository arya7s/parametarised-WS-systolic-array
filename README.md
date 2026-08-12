# Parameterized Weight-Stationary Systolic Array

A configurable SystemVerilog systolic-array accelerator for quantized matrix multiplication and small neural-network inference, targeting Xilinx Zynq-7000 FPGAs.

The project explores the hardware/software boundary of ML acceleration: a Python reference model produces quantized parameters, SystemVerilog implements the compute architecture and AXI interfaces, and a cycle-accurate simulation environment checks the resulting datapath and control behavior.

> **Reference configuration:** 4×4 weight-stationary array, signed int8 operands, int32 partial sums, and a 4→16→3 MLP for Iris classification.

---

## Why this project?

Systolic arrays trade large amounts of control and memory traffic for regular, spatially parallel computation. This project implements that idea at RTL rather than treating the FPGA as a black-box accelerator.

The main design questions are:

- How should weights be stored and reused in a **weight-stationary** dataflow?
- How can operand skewing keep a 2-D PE array fed every cycle?
- How should signed **int8 × int8 → int32** arithmetic be represented and pipelined?
- How can the compute core be exposed through standard **AXI4-Lite** and **AXI4-Stream** interfaces?
- How does array size affect latency and resource usage?

---

## Architecture

```text
                         +----------------------+
                         |   ARM / Host / TB     |
                         +----------+-----------+
                                    |
                  +-----------------+-----------------+
                  |                                   |
            AXI4-Lite                           AXI4-Stream
       weights / control                         activations
                  |                                   |
                  v                                   v
          +---------------+                    +-------------+
          | Weight /      |                    | Input       |
          | Config Logic  |                    | Interface   |
          +-------+-------+                    +------+------+ 
                  |                                   |
                  +----------------+------------------+
                                   |
                                   v
                        +----------------------+
                        | Weight-Stationary    |
                        | Systolic Array       |
                        |                      |
                        |  +--+ +--+ +--+ +--+|
                        |  |PE| |PE| |PE| |PE||
                        |  +--+ +--+ +--+ +--+|
                        |  |PE| |PE| |PE| |PE||
                        |  +--+ +--+ +--+ +--+|
                        |  |PE| |PE| |PE| |PE||
                        |  +--+ +--+ +--+ +--+|
                        |  |PE| |PE| |PE| |PE||
                        |  +--+ +--+ +--+ +--+|
                        +----------+-----------+
                                   |
                                   v
                         +-------------------+
                         | ReLU / accumulation|
                         +---------+---------+
                                   |
                                   v
                              AXI4-Stream
                               output logits
```

Each processing element (PE) retains its weight while activations propagate horizontally and partial sums propagate vertically. Input skewing aligns the operands as they enter the array.

See [`docs/architecture.md`](docs/architecture.md) for the datapath, timing model, parameterization, and design trade-offs.

---

## Reference ML workload

| Property | Configuration |
|---|---|
| Dataset | Iris (150 samples, 3 classes) |
| Network | 4 → 16 → 3 MLP |
| Hidden activation | ReLU |
| Weight / activation precision | signed int8 |
| Accumulator precision | signed int32 |
| Bias | Enabled in the current inference path |
| Array | 4 × 4 PEs |
| Dataflow | Weight-stationary |
| Target clock | 100 MHz |

The ML model is a **proof-of-concept workload**, not the primary contribution. The reusable hardware abstraction is the parameterized systolic-array datapath.

---

## Parameterization

The shared package exposes the principal hardware parameters:

```systemverilog
parameter int ACT_W    = 8;
parameter int WEIGHT_W = 8;
parameter int PSUM_W   = 32;
parameter int SA_ROWS  = 4;
parameter int SA_COLS  = 4;
```

The PE grid is generated from `SA_ROWS` and `SA_COLS`, while arithmetic widths are controlled independently. The supplied Iris design uses a 4×4 array; changing array dimensions therefore changes the replicated PE structure rather than requiring a new hand-written array.

The current top-level controller and ML workload remain specialized to the 4→16→3 demonstration. This distinction is intentional: **the compute fabric is parameterized; the reference accelerator integration is workload-specific.**

---

## RTL organization

```text
rtl/
├── params_pkg.sv          Shared widths and array parameters
├── pe.sv                  Processing element: weight register + MAC
├── systolic_array.sv      2-D generated PE array and input skewing
├── controller.sv          Inference control FSM and tiling
├── axi_lite_slave.sv      AXI4-Lite control / weight interface
├── axis_input_slave.sv    AXI4-Stream input interface
├── axis_output_master.sv  AXI4-Stream output interface
├── bram_wrapper.sv        Memory wrapper used by the integration
└── ml_accel_top.sv        Top-level accelerator integration
```

Supporting material:

```text
python_train_and_inference/   Quantization, training and software reference
weight_and_biases/            Exported model parameters
 testbench/                   Cycle-accurate SystemVerilog verification
screenshots_project/          Architecture, simulation and implementation evidence
docs/                         Design and verification notes
```

---

## Verification

The repository contains a **self-checking, cycle-aware SystemVerilog testbench** that drives AXI transactions, observes internal control/array events, captures output logits, and compares the hardware result against an expected classification.

Verification currently includes:

- Directed inference vectors
- Random input-vector testing
- AXI-Lite register transactions
- AXI4-Stream input/output activity
- FSM phase and cycle accounting
- PE-array output-valid monitoring
- Bias loading and application checks
- Reset and protocol behavior exercised in simulation

The repository also contains saved verification/implementation evidence in [`screenshots_project/`](screenshots_project/).

**Important:** the current checked-in testbench is SystemVerilog-based rather than a complete UVM class hierarchy. UVM-related screenshots from earlier development are retained as project evidence, but this README deliberately does not claim that the current source tree is a full UVM environment.

See [`docs/verification.md`](docs/verification.md) for the verification strategy and what is currently implemented versus planned.

---

## FPGA target

| Item | Target |
|---|---|
| Board | Avnet ZedBoard |
| FPGA | Xilinx XC7Z020 |
| Device family | Zynq-7000 |
| Clock | 100 MHz target |
| EDA | AMD/Xilinx Vivado |
| Processing system | Dual Cortex-A9 |

Implementation screenshots for utilization, timing, power, and synthesized structure are available under [`screenshots_project/`](screenshots_project/).

---

## Software reference flow

The Python side provides a reproducible reference for training/quantization and inference:

```text
Iris dataset
     |
     v
Standardization / scaling
     |
     v
4 → 16 → 3 MLP
     |
     v
Quantization to int8
     |
     +------> reference inference
     |
     +------> .mem parameter export
                         |
                         v
                 SystemVerilog simulation
```

Install the Python dependencies:

```bash
pip install torch scikit-learn numpy
```

Then inspect the scripts under [`python_train_and_inference/`](python_train_and_inference/) for the training/export and reference-inference flow.

---

## Running RTL simulation

A typical Questa/ModelSim flow is:

```bash
vlog -sv +incdir+rtl rtl/*.sv testbench/testbench.sv
vsim -c tb_cycle_accurate -do "run -all; quit"
```

The exact command may need adjustment for the simulator installation and working directory. The testbench expects the exported `.mem` files at the paths used by the simulation sources.

---

## Design trade-offs

| Decision | Rationale |
|---|---|
| Weight-stationary dataflow | Keeps weights local to PEs and exposes regular spatial reuse |
| 2-D generated PE grid | Makes array dimensions explicit and scalable |
| int8 operands | Reduces datapath/storage cost for quantized inference |
| int32 accumulation | Provides substantially more headroom than the operand width during dot products |
| Input skewing | Aligns operands with the systolic pipeline |
| AXI4-Lite + AXI4-Stream | Separates configuration/control from streaming datapath traffic |
| Zynq-7000 target | Provides a realistic SoC-FPGA platform for hardware/software integration |

---

## Project status

| Component | Status |
|---|---|
| Parameterized PE | Complete |
| Parameterized 2-D systolic array | Complete |
| Weight-stationary dataflow | Complete |
| AXI interfaces | Complete for reference integration |
| Iris inference workload | Complete |
| Cycle-accurate simulation | Complete |
| FPGA implementation evidence | Included |
| Full reusable UVM environment | Future work |
| Automated CI simulation | Future work |
| Performance/resource sweep across array sizes | Future work |

The **next logical research step** is to automate synthesis/simulation sweeps over `(SA_ROWS, SA_COLS, ACT_W, PSUM_W)` and report latency, LUT/FF/DSP/BRAM utilization, Fmax, and energy/per-inference. That would turn the project from a single accelerator implementation into a small architectural study.

---

## Repository guide

- **Architecture:** [`docs/architecture.md`](docs/architecture.md)
- **Verification:** [`docs/verification.md`](docs/verification.md)
- **RTL:** [`rtl/`](rtl/)
- **Python reference:** [`python_train_and_inference/`](python_train_and_inference/)
- **Model parameters:** [`weight_and_biases/`](weight_and_biases/)
- **Simulation:** [`testbench/`](testbench/)
- **Implementation evidence:** [`screenshots_project/`](screenshots_project/)

---

## References

- R. A. Fisher, *The use of multiple measurements in taxonomic problems*, 1936 — source of the Iris dataset.
- Accellera Systems Initiative, **UVM 1.2 User's Guide / Class Reference**.
- AMD/Xilinx, **Zynq-7000 SoC Technical Reference Manual**.
- Avnet, **ZedBoard Hardware User Guide**.

---

### Author

**Arya Saha** — Electronics & Communication Engineering

This project was developed as an independent RTL/FPGA study focused on digital design, hardware acceleration, and verification.
