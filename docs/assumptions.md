# Scope and assumptions

## Demonstration model

The repository's Iris 4→16→3 MLP is used purely as a compact demonstration workload for exercising the hardware datapath. It is not intended to imply that Iris classification is the target application of the accelerator architecture.

## Bias

Bias is enabled in the demonstrated MLP and represented in the exported model parameters. Hardware verification includes bias loading and application, so the accelerator is bias-capable rather than a bias-free network.
