# Design Tradeoffs

## Weight-stationary dataflow

Weights are loaded into PE-local registers and reused while activations traverse the array. For the small dense MLP demonstration, this keeps the dataflow simple and makes the reuse pattern explicit.

## Register storage versus BRAM

The demonstration model is small enough that weight storage can remain in registers without requiring a BRAM-backed hierarchy. This reduces control and memory-interface complexity at the current scale. A larger workload would motivate BRAM/URAM-backed storage and buffering.

## INT8 operands, INT32 accumulation

Signed INT8 operands reduce datapath and storage cost, while INT32 partial sums provide substantially more headroom during accumulation. The precision choice is a deliberate hardware/software interface decision rather than merely a software quantization setting.

## Small array versus larger array

A larger array increases parallel MAC capacity but also increases PE count, routing pressure, weight storage, and the amount of input staggering/control. The parameterized dimensions expose this tradeoff without hard-coding a single physical array size.

## Bias support

Bias terms are enabled in the current implementation. They are applied in the controller/data path rather than omitted from the model, so the software reference and hardware inference remain aligned.
