# Parameterized Weight-Stationary Systolic Array

This repository contains the RTL design and verification environment for a parameterizable, weight-stationary systolic array designed for hardware-accelerated General Matrix Multiplication (GEMM). 

## Architecture Overview
The design implements a weight-stationary dataflow, minimizing memory accesses by pre-loading and holding weight matrices within the Processing Elements (PEs) while streaming input activations. 

* **Hardware Target:** Designed and synthesized for the ZedBoard (Zynq-7000 SoC).
* **Tools Used:** Xilinx Vivado, [Verilog/SystemVerilog]
* **Key Features:** Parameterized RTL allows scaling of the array dimensions (e.g., 4x4, 8x8) without modifying the core logic.

## Directory Structure
* `rtl/`: Contains the source code for the Processing Elements and the top-level array.
* `tb/`: Contains the testbenches used to verify partial product accumulation and overall GEMM functionality.

## Simulation & Verification
The design was extensively verified using Vivado's simulator. 


