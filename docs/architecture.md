# Architecture Notes

## 1. Compute model

The accelerator implements matrix multiplication using a 2-D weight-stationary systolic array.

For a processing element `(r,c)`:

```text
psum_out(r,c) = psum_in(r,c) + weight(r,c) × activation(r,c)
```

Weights are loaded into PE-local registers and remain stationary during a compute phase. Activations move horizontally through the array, while partial sums move vertically.

## 2. Processing element

Each PE contains:

1. A signed weight register.
2. A signed multiply datapath.
3. A 32-bit signed partial-sum register.
4. A registered activation forwarding path.

The PE is intentionally small so that a regular grid can be generated with nested `generate` loops.

## 3. Input skewing

A conventional systolic array requires the activation streams to arrive at different PEs at different times. The array therefore inserts row-dependent delays before the first PE of each row.

For row `r`, the activation entering column 0 is delayed by `r` cycles. This creates the diagonal wavefront required for synchronized multiply-accumulate operations.

The skew depth is derived from `SA_ROWS`, rather than being manually written for the 4×4 reference design.

## 4. Array parameterization

The main hardware parameters are defined in `rtl/params_pkg.sv`:

| Parameter | Meaning | Reference |
|---|---|---:|
| `ACT_W` | Activation width | 8 |
| `WEIGHT_W` | Weight width | 8 |
| `PSUM_W` | Partial-sum width | 32 |
| `SA_ROWS` | Number of PE rows | 4 |
| `SA_COLS` | Number of PE columns | 4 |

The PE array is instantiated with nested generate loops, so the hardware structure scales with the selected dimensions.

The reference neural-network integration remains workload-specific. This is an important architectural distinction: **the compute fabric is reusable even though the surrounding inference controller is currently specialized.**

## 5. Data movement

```text
                    AXI4-Lite
               weights / control
                       |
                       v
                +-------------+
                | Weight load |
                +------+------+ 
                       |
                       v
Input activations --> [ PE ][ PE ][ PE ][ PE ] -->
                      [ PE ][ PE ][ PE ][ PE ]
                      [ PE ][ PE ][ PE ][ PE ]
                      [ PE ][ PE ][ PE ][ PE ]
                         |
                         v
                    partial sums
```

AXI4-Lite is used for configuration/weight transactions in the reference integration. AXI4-Stream carries input activations and output logits.

## 6. Layer execution

The reference MLP is:

```text
4 input features
      |
      v
4×16 matrix multiply
      |
      v
ReLU
      |
      v
16×3 matrix multiply
      |
      v
3 output logits
```

Because the array is 4×4, the 16-wide hidden layer can be mapped naturally onto four-column/row tiles. The controller sequences weight loading, compute, activation, and output phases.

## 7. Latency model

For the reference array, the systolic datapath latency is related to the row/column dimensions rather than being an arbitrary constant. The RTL uses:

```systemverilog
localparam int LATENCY = SA_ROWS + SA_COLS;
```

The surrounding controller and AXI transactions add additional cycles. Therefore, end-to-end latency should be measured from simulation rather than inferred solely from the PE-array pipeline depth.

## 8. Design trade-offs

### Why weight-stationary?

The workload repeatedly reuses model weights while activations change between inferences. Keeping weights in PE-local registers reduces repeated movement through the compute fabric.

### Why int8?

Int8 arithmetic is a practical starting point for quantized neural-network inference and keeps the multiplier and storage requirements substantially below wider fixed-point representations.

### Why int32 accumulation?

A dot product accumulates multiple products. Keeping the accumulator substantially wider than the operands reduces overflow risk and makes the numerical behavior easier to reason about.

### Why no hand-written PE grid?

A generated array makes the design intent explicit and allows architectural experiments with different array dimensions without rewriting every PE instance.

## 9. Current limitations

The present implementation is intentionally a reference accelerator rather than a production NPU. In particular:

- The top-level MLP dimensions are workload-specific.
- The repository does not yet provide automated synthesis sweeps across array sizes.
- Verification is currently a SystemVerilog testbench rather than a complete reusable UVM environment.
- Resource/performance numbers are tied to the supplied Zynq-7000 implementation and should not be generalized to other FPGA families.

These limitations define the most useful next experiments rather than being hidden from the reader.
