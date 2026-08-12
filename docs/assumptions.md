# Scope and assumptions

## Demonstration model

The repository's Iris 4→16→3 MLP is used purely as a compact demonstration workload for exercising the hardware datapath. It is not intended to imply that Iris classification is the target application of the accelerator architecture.

## Bias

Bias is enabled in the demonstrated MLP and represented in the exported model parameters. Hardware verification includes bias loading/application; therefore the documentation treats the accelerator as bias-capable rather than describing it as a bias-free network.

## Claims discipline

Only completed implementation and verification behavior is described as current capability. Planned stress tests, protocol corner cases, larger workloads, and UVM expansion are explicitly labeled as future work.
