#!/usr/bin/env python3
"""
inference_fpga_final.py
=======================
Hardware-accurate quantized MLP emulation for Iris classification (4->16->3).

Core Features:
  - Exact fixed-point arithmetic (8-bit MACs, 32-bit accumulators)
  - Tiled weight loading from .mem files (4x4 tiling)
  - 2's complement hex to signed integer conversion
  - Bit-shift dequantization (>> 3 or >> 6)
  - Shift comparison: auto-test both shifts if --shift not specified
  - Batch evaluation with accuracy comparison
  - Multiple input modes: raw measurements, quantized int8, batch, single samples

Key Datapath:
  L1: acc1 = (x_q * W1) + B1  →  h_q = clip(max(0, acc1) >> shift, 0, 127)
  L2: acc2 = (h_q * W2) + B2  →  pred = argmax(acc2)

Usage:
  python inference_fpga_final.py --batch                 # Compare shift=3 vs 6
  python inference_fpga_final.py --batch --shift 6       # Test shift=6 only
  python inference_fpga_final.py                         # Interactive, raw input
  python inference_fpga_final.py --quant-input           # Interactive, pre-quantized
  python inference_fpga_final.py --sample 5 --shift 6    # Test sample #5, shift=6
"""

import argparse
import os
import sys
import numpy as np
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

try:
    import torch
    import torch.nn as nn
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False

# ============================================================================
# Global Config
# ============================================================================
IRIS_CLASSES = ["Iris-setosa", "Iris-versicolor", "Iris-virginica"]
INPUT_DIM = 4
HIDDEN_DIM = 16
OUTPUT_DIM = 3


# ============================================================================
# Quantization & Hex Utilities
# ============================================================================
def hex_to_int8(h):
    """Convert 2's complement hex string to signed int8."""
    v = int(h, 16) if isinstance(h, str) else h
    return v if v < 128 else v - 256


def int8_to_hex(value):
    """Convert signed int8 to 2's complement hex string."""
    value = int(value)
    if value < 0:
        value = 256 + value
    return f"{value:02x}"


def quantize_to_int8(value, scale):
    """Quantize float to 8-bit signed integer [-128, 127]."""
    quantized = np.round(value * scale)
    quantized = np.clip(quantized, -128, 127)
    return quantized.astype(np.int8)


# ============================================================================
# PyTorch Model (Reference Float)
# ============================================================================
if TORCH_AVAILABLE:
    class MLP(nn.Module):
        def __init__(self):
            super().__init__()
            self.fc1 = nn.Linear(INPUT_DIM, HIDDEN_DIM, bias=True)
            self.relu = nn.ReLU()
            self.fc2 = nn.Linear(HIDDEN_DIM, OUTPUT_DIM, bias=True)

        def forward(self, x):
            return self.fc2(self.relu(self.fc1(x)))


# ============================================================================
# Data Loading
# ============================================================================
def load_data():
    """Load Iris, split, standardize, scale by 16."""
    iris = load_iris()
    X, y = iris.data, iris.target
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train) * 16.0
    X_test_scaled = scaler.transform(X_test) * 16.0
    return X_train_scaled, X_test_scaled, y_train, y_test, scaler


# ============================================================================
# Float Inference (Reference)
# ============================================================================
def train_float_model(X_train, y_train):
    """Train PyTorch MLP."""
    if not TORCH_AVAILABLE:
        raise RuntimeError("PyTorch required for float mode.")
    
    import torch.optim as optim
    model = MLP()
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.01)
    
    X_t = torch.FloatTensor(X_train)
    y_t = torch.LongTensor(y_train)
    
    print("  Training float model for 100 epochs…")
    for epoch in range(100):
        model.train()
        optimizer.zero_grad()
        loss = criterion(model(X_t), y_t)
        loss.backward()
        optimizer.step()
    
    model.eval()
    return model


def float_infer_single(model, x_scaled):
    """Single sample float inference."""
    with torch.no_grad():
        t = torch.FloatTensor(x_scaled).unsqueeze(0)
        out = model(t)
        probs = torch.softmax(out, dim=1).squeeze().numpy()
        pred = int(torch.argmax(out, dim=1).item())
    return pred, probs


def float_infer_batch(model, X_scaled):
    """Batch float inference."""
    with torch.no_grad():
        t = torch.FloatTensor(X_scaled)
        out = model(t)
        pred = torch.argmax(out, dim=1).numpy()
    return pred


# ============================================================================
# Hardware Quantized Inference
# ============================================================================
def load_mem_file(path):
    """Load hex values from .mem file."""
    if not os.path.isfile(path):
        raise FileNotFoundError(f"File not found: {path}")
    with open(path) as f:
        return [hex_to_int8(line.strip()) for line in f if line.strip()]


def load_quantized_weights(w1_path="weights_layer1.mem",
                           w2_path="weights_layer2.mem",
                           b_path="biases.mem"):
    """Load and reconstruct tiled weights from .mem files."""
    raw1 = load_mem_file(w1_path)   # 64 values
    raw2 = load_mem_file(w2_path)   # 64 values
    rawb = load_mem_file(b_path)    # 20 values
    
    # Reconstruct L1 weights (16x4)
    w1 = np.zeros((HIDDEN_DIM, INPUT_DIM), dtype=np.int32)
    idx = 0
    for tile in range(4):
        for row in range(4):
            for col in range(4):
                w1[tile * 4 + col, row] = raw1[idx]
                idx += 1
    
    # Reconstruct L2 weights (3x16)
    w2 = np.zeros((OUTPUT_DIM, HIDDEN_DIM), dtype=np.int32)
    idx = 0
    for tile in range(4):
        for row in range(4):
            for col in range(4):
                if col < OUTPUT_DIM:
                    w2[col, tile * 4 + row] = raw2[idx]
                idx += 1
    
    # Biases
    b1 = np.array(rawb[:HIDDEN_DIM], dtype=np.int32)
    b2 = np.array(rawb[HIDDEN_DIM:HIDDEN_DIM+OUTPUT_DIM], dtype=np.int32)
    
    return w1, b1, w2, b2


def quant_forward(x_q, w1, b1, w2, b2, shift_amt=3):
    """
    Hardware-accurate quantized forward pass.
    
    Parameters
    ----------
    x_q : array of int32, shape (4,)
        Quantized input (8-bit values as int32)
    w1, b1, w2, b2 : quantized weights and biases
    shift_amt : int
        Bit-shift for layer-1 dequantization (3 or 6)
    
    Returns
    -------
    pred : int
        Predicted class (0, 1, or 2)
    acc2 : array of int32, shape (3,)
        Layer-2 accumulator (raw scores)
    h_q : array of int32, shape (16,)
        Layer-1 hidden output after shift
    """
    # Layer 1: MAC + ReLU + Shift
    acc1 = x_q @ w1.T + b1                        # (16,) int32
    relu1 = np.maximum(acc1, 0)                   # ReLU
    h_q = np.clip(relu1 >> shift_amt, 0, 127).astype(np.int32)  # Shift & clip
    
    # Layer 2: MAC
    acc2 = h_q @ w2.T + b2                        # (3,) int32
    
    pred = int(np.argmax(acc2))
    return pred, acc2, h_q


# ============================================================================
# Batch Evaluation
# ============================================================================
def eval_batch(X_test_s, y_test, w1, b1, w2, b2, shifts_to_test, model=None):
    """Evaluate on full test set."""
    print(f"\n{'='*80}")
    print("BATCH EVALUATION on test set (30 samples)")
    print(f"{'='*80}")
    
    # Float inference
    if model is not None:
        print("\n[FLOAT MODE]")
        preds_f = float_infer_batch(model, X_test_s)
        acc_f = np.mean(preds_f == y_test)
        correct_f = int(acc_f * len(y_test))
        print(f"  Accuracy: {acc_f:.4f}  ({correct_f}/{len(y_test)} correct)")
    
    # Quantized inference with different shifts
    print("\n[QUANTIZED MODE - Shift Comparison]")
    results = {}
    
    for shift in shifts_to_test:
        preds_q = []
        for x in X_test_s:
            x_q = quantize_to_int8(x, 1.0).astype(np.int32)
            pred, _, _ = quant_forward(x_q, w1, b1, w2, b2, shift_amt=shift)
            preds_q.append(pred)
        preds_q = np.array(preds_q)
        
        acc_q = np.mean(preds_q == y_test)
        correct_q = int(acc_q * len(y_test))
        results[shift] = (preds_q, acc_q)
        
        shift_desc = f"÷{2**shift}"
        print(f"\n  Shift={shift} ({shift_desc}):")
        print(f"    Accuracy: {acc_q:.4f}  ({correct_q}/{len(y_test)} correct)")
    
    # Comparison if testing both shifts
    if len(shifts_to_test) > 1 and 3 in results and 6 in results:
        preds_3, acc_3 = results[3]
        preds_6, acc_6 = results[6]
        
        agree = np.mean(preds_3 == preds_6)
        disagree_count = np.sum(preds_3 != preds_6)
        
        print(f"\n{'─'*80}")
        print("SHIFT COMPARISON (3 vs 6):")
        print(f"  Agreement rate: {agree:.4f}  ({disagree_count} samples disagree)")
        
        if acc_3 > acc_6:
            print(f"  ✓ SHIFT=3 is BETTER (acc {acc_3:.4f} > {acc_6:.4f})")
            print(f"    → Training scales (÷8) match the data better")
        elif acc_6 > acc_3:
            print(f"  ✓ SHIFT=6 is BETTER (acc {acc_6:.4f} > {acc_3:.4f})")
            print(f"    → FPGA SHIFT_AMT=6 (÷64) is correct")
        else:
            print(f"  → Both shifts give IDENTICAL accuracy ({acc_3:.4f})")
        
        print(f"{'─'*80}")
    
    # Float vs Quant agreement
    if model is not None and len(shifts_to_test) > 0:
        preds_q, _ = results[shifts_to_test[0]]
        float_vs_quant_agree = np.mean(preds_f == preds_q)
        print(f"\nFloat vs Quant (shift={shifts_to_test[0]}) agreement: {float_vs_quant_agree:.4f}")
    
    print()


# ============================================================================
# Single Sample Evaluation
# ============================================================================
def print_result(label, x_raw, pred, acc2, h_q=None, label_true=None):
    """Pretty-print inference result."""
    print(f"\n{'─'*80}")
    print(f"  {label}")
    print(f"{'─'*80}")
    if x_raw is not None:
        print(f"  Raw input      : {np.round(x_raw, 4)}")
    print(f"  L2 scores      : {acc2}")
    print(f"  Prediction     : {pred}  ({IRIS_CLASSES[pred]})")
    if h_q is not None:
        print(f"  L1 hidden (q)  : {h_q}")
    if label_true is not None:
        match = "✓" if pred == label_true else "✗"
        print(f"  True label     : {label_true}  ({IRIS_CLASSES[label_true]})  {match}")
    print(f"{'─'*80}\n")


# ============================================================================
# Main
# ============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="Hardware emulation: quantized 4→16→3 MLP with shift comparison",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python inference_fpga_final.py --batch
      → Test both shift=3 and shift=6, show accuracy and comparison

  python inference_fpga_final.py --batch --shift 6
      → Test only shift=6

  python inference_fpga_final.py
      → Interactive, input raw measurements (with preprocessing)

  python inference_fpga_final.py --quant-input
      → Interactive, input pre-quantized 8-bit values (skip preprocessing)

  python inference_fpga_final.py --sample 5 --shift 6
      → Single test sample #5, shift=6 only
        """
    )
    
    parser.add_argument("--batch", action="store_true",
                        help="Evaluate full test set")
    parser.add_argument("--sample", type=int, default=None,
                        help="Index into test set (0-29)")
    parser.add_argument("--shift", type=int, choices=[3, 6], default=None,
                        help="Bit-shift: 3 (÷8) or 6 (÷64). "
                             "Omit to test BOTH and compare.")
    parser.add_argument("--quant-input", action="store_true",
                        help="Input pre-quantized int8 (skip preprocessing)")
    parser.add_argument("--mode", choices=["float", "quant", "both"],
                        default="both",
                        help="Inference mode")
    parser.add_argument("--w1", default="weights_layer1.mem")
    parser.add_argument("--w2", default="weights_layer2.mem")
    parser.add_argument("--b", default="biases.mem")
    
    args = parser.parse_args()
    
    # ── Load data ──────────────────────────────────────────────────────────
    print("Loading Iris dataset…")
    X_train_s, X_test_s, y_train, y_test, scaler = load_data()
    print(f"  Train: {len(X_train_s)}, Test: {len(X_test_s)}")
    
    # ── Load / train float model ───────────────────────────────────────────
    model = None
    if args.mode in ("float", "both"):
        if not TORCH_AVAILABLE:
            print("WARNING: PyTorch not available; skipping float mode.")
            args.mode = "quant"
        else:
            model = train_float_model(X_train_s, y_train)
    
    # ── Load quantized weights ─────────────────────────────────────────────
    w1 = w2 = b1 = b2 = None
    if args.mode in ("quant", "both"):
        print("Loading quantized weights from .mem files…")
        w1, b1, w2, b2 = load_quantized_weights(args.w1, args.w2, args.b)
    
    # ── Determine shifts to test ───────────────────────────────────────────
    shifts_to_test = [args.shift] if args.shift else [3, 6]
    
    # ======================================================================
    # BATCH MODE
    # ======================================================================
    if args.batch:
        if args.mode in ("quant", "both"):
            eval_batch(X_test_s, y_test, w1, b1, w2, b2, 
                      shifts_to_test, model=model)
        else:
            print("\n[FLOAT BATCH MODE]")
            preds_f = float_infer_batch(model, X_test_s)
            acc_f = np.mean(preds_f == y_test)
            print(f"  Accuracy: {acc_f:.4f}  ({int(acc_f*len(y_test))}/{len(y_test)} correct)\n")
        return
    
    # ======================================================================
    # SINGLE SAMPLE MODE
    # ======================================================================
    
    # Get input data
    if args.sample is not None:
        x_s = X_test_s[args.sample]
        x_raw = scaler.inverse_transform([x_s / 16.0])[0]
        label_true = y_test[args.sample]
        idx = args.sample
        print(f"\n[SAMPLE #{idx}]")
    elif args.quant_input:
        print("\nEnter quantized 8-bit signed integers (range: -128 to 127):")
        try:
            x_q_list = []
            for i in range(INPUT_DIM):
                val = int(input(f"  input[{i}]: "))
                if not (-128 <= val <= 127):
                    print(f"ERROR: Value must be in [-128, 127]")
                    sys.exit(1)
                x_q_list.append(val)
            x_q = np.array(x_q_list, dtype=np.int32)
        except (ValueError, EOFError):
            print("Invalid input.")
            sys.exit(1)
        
        x_s = None
        x_raw = None
        label_true = None
        idx = None
        
        print(f"\nQuantized input (int8): {x_q}")
        print(f"Quantized input (hex) : {' '.join(f'0x{int8_to_hex(v)}' for v in x_q)}\n")
    else:
        print("\nEnter raw Iris features (not standardized):")
        try:
            x_raw = np.array([
                float(input("  Sepal length (cm): ")),
                float(input("  Sepal width  (cm): ")),
                float(input("  Petal length (cm): ")),
                float(input("  Petal width  (cm): ")),
            ])
        except (ValueError, EOFError):
            print("Invalid input.")
            sys.exit(1)
        
        x_s = scaler.transform([x_raw])[0] * 16.0
        label_true = None
        idx = None
    
    # Float inference
    if args.mode in ("float", "both") and model and x_s is not None:
        pred_f, probs_f = float_infer_single(model, x_s)
        print_result("FLOAT INFERENCE", x_raw, pred_f, 
                    np.round(probs_f, 4), label_true=label_true)
    
    # Quantized inference - ALWAYS TEST BOTH SHIFTS IN INTERACTIVE MODE
    if args.mode in ("quant", "both") and w1 is not None:
        if x_s is not None:
            x_q = quantize_to_int8(x_s, 1.0).astype(np.int32)
        
        # In interactive mode, always test both shifts for comparison
        shifts_to_compare = [3, 6] if not args.batch else shifts_to_test
        
        results = {}
        for shift in shifts_to_compare:
            pred_q, acc2, h_q = quant_forward(x_q, w1, b1, w2, b2, shift_amt=shift)
            results[shift] = (pred_q, acc2, h_q)
            
            label_shift = f"QUANT (shift={shift}, >> {shift}, ÷{2**shift})"
            print_result(label_shift, x_raw, pred_q, acc2, h_q=h_q, 
                        label_true=label_true)
        
        # Always show shift comparison in interactive mode
        if 3 in results and 6 in results:
            pred_3, acc2_3, _ = results[3]
            pred_6, acc2_6, _ = results[6]
            
            print(f"\n{'='*80}")
            print("SHIFT COMPARISON ANALYSIS:")
            print(f"{'='*80}")
            print(f"  Shift=3 (>> 3, ÷ 8)   → Class {pred_3} ({IRIS_CLASSES[pred_3]})")
            print(f"                        → Logits: {acc2_3}")
            print()
            print(f"  Shift=6 (>> 6, ÷ 64)  → Class {pred_6} ({IRIS_CLASSES[pred_6]})")
            print(f"                        → Logits: {acc2_6}")
            print(f"{'─'*80}")
            
            if pred_3 == pred_6:
                print(f"\n  ✅ Both shifts AGREE on prediction: {pred_3} ({IRIS_CLASSES[pred_3]})")
                print(f"     This sample is robust to scaling changes.")
            else:
                print(f"\n  ⚠️  Shifts DISAGREE:")
                print(f"     Shift=3 predicts: {pred_3} ({IRIS_CLASSES[pred_3]})")
                print(f"     Shift=6 predicts: {pred_6} ({IRIS_CLASSES[pred_6]})")
                print(f"\n  Which one is more likely correct?")
                print(f"  - Check your training script's SHIFT_AMT setting")
                print(f"  - Run --batch to see which shift has higher accuracy on test set")
            
            # Determine which logit has higher max score (confidence)
            max_3 = max(acc2_3)
            max_6 = max(acc2_6)
            confidence_3 = max_3 - min(acc2_3)
            confidence_6 = max_6 - min(acc2_6)
            
            print(f"\n  Confidence metrics:")
            print(f"    Shift=3: max logit = {max_3}, spread = {confidence_3}")
            print(f"    Shift=6: max logit = {max_6}, spread = {confidence_6}")
            
            if confidence_6 > confidence_3:
                print(f"\n  ✓ Shift=6 has higher confidence (better separation)")
            elif confidence_3 > confidence_6:
                print(f"\n  ✓ Shift=3 has higher confidence (better separation)")
            else:
                print(f"\n  → Both have similar confidence")
            
            print(f"{'='*80}\n")
        
        print(f"Quantized input (hex): {' '.join(f'0x{int8_to_hex(v)}' for v in x_q)}\n")
    
    # Float vs Quant agreement
    if args.mode == "both" and model and w1 is not None and x_s is not None:
        x_q = quantize_to_int8(x_s, 1.0).astype(np.int32)
        shift_to_use = args.shift if args.shift else 3
        pred_f, _ = float_infer_single(model, x_s)
        pred_q, _, _ = quant_forward(x_q, w1, b1, w2, b2, shift_amt=shift_to_use)
        
        print(f"{'─'*80}")
        if pred_f == pred_q:
            print(f"✓ Float and Quant (shift={shift_to_use}) AGREE\n")
        else:
            print(f"✗ Float and Quant (shift={shift_to_use}) DISAGREE\n")
        print(f"{'─'*80}\n")


if __name__ == "__main__":
    main()