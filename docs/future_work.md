# Future Work

The current implementation is intentionally scoped as a compact FPGA accelerator study. Natural extensions include:

1. Automated parameter sweeps across array dimensions and operand widths.
2. Larger GEMM/MLP workloads with explicit tiling and throughput measurements.
3. BRAM-backed weight storage, buffering, and more deliberate memory hierarchy design.
4. AXI DMA integration to study host-to-accelerator transfer overhead.
5. Mixed-precision experiments such as INT4/INT8 operands with wider accumulation.
6. Formal assertions for controller invariants and AXI protocol behavior.
7. A full constrained-random UVM environment if verification scope is expanded beyond the current cycle-accurate SystemVerilog testbench.
8. Quantization-aware training and accuracy/resource tradeoff analysis.

These are future directions, not capabilities claimed by the present implementation.
