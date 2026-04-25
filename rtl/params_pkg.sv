package params_pkg;
    // Data widths
    parameter int ACT_W      = 8;
    parameter int WEIGHT_W   = 8;
    parameter int PSUM_W     = 32;

    // Systolic array dimensions
    parameter int SA_ROWS = 4;
    parameter int SA_COLS = 4;

    // Model dimensions (Iris: 4 -> 16 -> 3)
    parameter int IN_FEATURES  = 4;
    parameter int HID_FEATURES = 16;
    parameter int OUT_FEATURES = 3;

    // Scaling: Divide by 2^6 (64) to bring PSums back to 8-bit range
    parameter int SHIFT_AMT = 6; 

    // Memory Depths (Total weights = 64 for L1 + 64 for L2 padded)
    parameter int WEIGHT_MEM_DEPTH = 128; 
endpackage : params_pkg