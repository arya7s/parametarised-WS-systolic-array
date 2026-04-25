import time

# =============================================================================
# 1. HELPER FUNCTIONS
# =============================================================================
def hex_to_signed_8bit(hex_str):
    val = int(hex_str, 16)
    return val - 256 if val > 127 else val

def unpack_input(hex_input):
    hex_input = hex_input.strip()
    if hex_input.lower().startswith('0x'):
        hex_input = hex_input[2:]
        
    hex_input = hex_input.zfill(8)
    
    return [
        hex_to_signed_8bit(hex_input[6:8]),
        hex_to_signed_8bit(hex_input[4:6]),
        hex_to_signed_8bit(hex_input[2:4]),
        hex_to_signed_8bit(hex_input[0:2])
    ]

# =============================================================================
# 2. LOAD WEIGHTS (as pure Python lists)
# =============================================================================
def load_layer1_weights(filename="weights_layer1.mem"):
    with open(filename, 'r') as f:
        lines = f.read().splitlines()

    W = [[0]*4 for _ in range(16)]
    for i, line in enumerate(lines):
        tile_idx, rem = divmod(i, 16)
        row, col = divmod(rem, 4)
        out_idx = (tile_idx * 4) + col
        if out_idx < 16 and row < 4:
            W[out_idx][row] = hex_to_signed_8bit(line)
    return W

def load_layer2_weights(filename="weights_layer2.mem"):
    with open(filename, 'r') as f:
        lines = f.read().splitlines()

    W = [[0]*16 for _ in range(3)]
    for i, line in enumerate(lines):
        tile_idx, rem = divmod(i, 16)
        row, col = divmod(rem, 4)
        in_idx = (tile_idx * 4) + row
        if col < 3 and in_idx < 16:
            W[col][in_idx] = hex_to_signed_8bit(line)
    return W

# =============================================================================
# 3. MAIN EXECUTION LOOP
# =============================================================================
def main():
    SHIFT_AMT = 6

    try:
        W1 = load_layer1_weights('weights_layer1.mem')
        W2 = load_layer2_weights('weights_layer2.mem')
    except FileNotFoundError as e:
        print(f"❌ Error: {e}")
        return

    print("✅ Optimized system ready.")

    while True:
        user_input = input("\nEnter 32-bit hex input (or 'q' to quit): ")
        if user_input.lower() == 'q':
            break

        try:
            x = unpack_input(user_input)

            # Preallocate
            z1 = [0]*16
            a1 = [0]*16
            logits = [0]*3

            start_time = time.perf_counter()

            # -----------------------------
            # Layer 1: Manual dot product
            # -----------------------------
            for i in range(16):
                s = 0
                w = W1[i]
                s += w[0]*x[0]
                s += w[1]*x[1]
                s += w[2]*x[2]
                s += w[3]*x[3]
                z1[i] = s

            # -----------------------------
            # Shift + ReLU (fused)
            # -----------------------------
            for i in range(16):
                val = z1[i] >> SHIFT_AMT
                if val < 0:
                    val = 0
                elif val > 127:
                    val = 127
                a1[i] = val

            # -----------------------------
            # Layer 2: Manual dot product
            # -----------------------------
            for i in range(3):
                s = 0
                w = W2[i]
                for j in range(16):
                    s += w[j] * a1[j]
                logits[i] = s

            end_time = time.perf_counter()

            # Output
            print("-" * 40)
            print(f"Input Vector:              {x}")
            print(f"Layer1 Output:             {z1}")
            print(f"Post-ReLU Activations:     {a1}")
            print(f"Final Logits:              {logits}")

            inference_time = (end_time - start_time) * 1e6
            print(f"⚡ Inference Time: {inference_time:.2f} µs")

            pred_class = logits.index(max(logits))
            print("-" * 40)
            print(f"🌟 Predicted Class: {pred_class}")

        except Exception as e:
            print(f"⚠️ Error: {e}")

if __name__ == '__main__':
    main()