import torch
import torch.nn as nn
import torch.optim as optim
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import numpy as np

# Deterministic seeding for reproducibility
torch.manual_seed(42)
np.random.seed(42)

# ============================================================================
# Model Definition
# ============================================================================
class MLP(nn.Module):
    def __init__(self):
        super(MLP, self).__init__()
        self.fc1 = nn.Linear(4, 16, bias=True)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(16, 3, bias=True)
    
    def forward(self, x):
        x = self.fc1(x)
        x = self.relu(x)
        x = self.fc2(x)
        return x

# ============================================================================
# Quantization Helper Functions
# ============================================================================
def quantize_to_int8(value, scale):
    """Quantize float to 8-bit signed integer [-128, 127]"""
    quantized = np.round(value * scale)
    quantized = np.clip(quantized, -128, 127)
    return quantized.astype(np.int8)

def int8_to_hex(value):
    """Convert signed int8 to 2's complement hex string"""
    value = int(value)  # Cast from numpy int8 to Python int to avoid overflow
    if value < 0:
        # 2's complement for negative numbers
        value = 256 + value
    return f"{value:02x}"

# ============================================================================
# Load and Preprocess Data
# ============================================================================
print("Loading Iris dataset...")
iris = load_iris()
X, y = iris.data, iris.target

# Split data
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# Standardize and scale by 16.0
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train) * 16.0
X_test_scaled = scaler.transform(X_test) * 16.0

# Convert to PyTorch tensors
X_train_tensor = torch.FloatTensor(X_train_scaled)
y_train_tensor = torch.LongTensor(y_train)
X_test_tensor = torch.FloatTensor(X_test_scaled)
y_test_tensor = torch.LongTensor(y_test)

print(f"Training samples: {len(X_train)}")
print(f"Test samples: {len(X_test)}")

# ============================================================================
# Train Model
# ============================================================================
print("\nTraining model...")
model = MLP()
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=0.01)

for epoch in range(500):
    model.train()
    optimizer.zero_grad()
    
    outputs = model(X_train_tensor)
    loss = criterion(outputs, y_train_tensor)
    
    loss.backward()
    optimizer.step()
    
    if (epoch + 1) % 100 == 0:
        model.eval()
        with torch.no_grad():
            train_outputs = model(X_train_tensor)
            train_pred = torch.argmax(train_outputs, dim=1)
            train_acc = (train_pred == y_train_tensor).float().mean()
            
            test_outputs = model(X_test_tensor)
            test_pred = torch.argmax(test_outputs, dim=1)
            test_acc = (test_pred == y_test_tensor).float().mean()
        
        print(f"Epoch {epoch+1}/500 - Loss: {loss.item():.4f} - "
              f"Train Acc: {train_acc:.4f} - Test Acc: {test_acc:.4f}")

# Final evaluation
model.eval()
with torch.no_grad():
    test_outputs = model(X_test_tensor)
    test_pred = torch.argmax(test_outputs, dim=1)
    test_acc = (test_pred == y_test_tensor).float().mean()
    print(f"\nFinal Test Accuracy: {test_acc:.4f}")

# ============================================================================
# Export Quantized Weights
# ============================================================================
print("\nExporting quantized weights and biases...")

# Get weights and biases
w1 = model.fc1.weight.detach().cpu().numpy()  # Shape: (16, 4)
b1 = model.fc1.bias.detach().cpu().numpy()    # Shape: (16,)
w2 = model.fc2.weight.detach().cpu().numpy()  # Shape: (3, 16)
b2 = model.fc2.bias.detach().cpu().numpy()    # Shape: (3,)

# Quantize weights (scale by 64 for better int8 resolution)
WEIGHT_SCALE = 64
w1_q = quantize_to_int8(w1, WEIGHT_SCALE)
w2_q = quantize_to_int8(w2, WEIGHT_SCALE)

# Quantize biases (scale must match MAC output scale at each layer)
# L1 MAC scale = input_scale(16) * weight_scale(64) = 1024
L1_MAC_SCALE = 16 * WEIGHT_SCALE  # 1024
b1_q = quantize_to_int8(b1, L1_MAC_SCALE)
# After SHIFT_AMT=6: hidden_scale = 1024/64 = 16
# L2 MAC scale = hidden_scale(16) * weight_scale(64) = 1024
L2_MAC_SCALE = (L1_MAC_SCALE >> 6) * WEIGHT_SCALE  # 1024
b2_q = quantize_to_int8(b2, L2_MAC_SCALE)

# ============================================================================
# Export Layer 1 Weights with 4x4 Tiling
# ============================================================================
# L1 mapping: out_idx = tile*4 + col, in_idx = row
# w1 shape: (16, 4) -> 16 outputs, 4 inputs
# We have 4 tiles (tile 0-3), each covering 4 outputs

with open('weights_layer1.mem', 'w') as f:
    for tile in range(4):  # 4 tiles
        for row in range(4):  # 4 rows (input dimension)
            for col in range(4):  # 4 cols (within tile)
                out_idx = tile * 4 + col
                in_idx = row
                weight_val = w1_q[out_idx, in_idx]
                f.write(int8_to_hex(weight_val) + '\n')

print(f"Exported weights_layer1.mem ({4*4*4} lines)")

# ============================================================================
# Export Layer 2 Weights with 4x4 Tiling
# ============================================================================
# L2 mapping: out_idx = col, in_idx = tile*4 + row
# w2 shape: (3, 16) -> 3 outputs, 16 inputs
# We have 4 tiles (tile 0-3), each covering 4 inputs

with open('weights_layer2.mem', 'w') as f:
    for tile in range(4):  # 4 tiles
        for row in range(4):  # 4 rows (within tile)
            for col in range(4):  # 4 cols (but only 3 are valid outputs)
                out_idx = col
                in_idx = tile * 4 + row
                if out_idx < 3:  # Only 3 outputs exist
                    weight_val = w2_q[out_idx, in_idx]
                else:
                    weight_val = 0  # Padding for col=3
                f.write(int8_to_hex(weight_val) + '\n')

print(f"Exported weights_layer2.mem ({4*4*4} lines)")

# ============================================================================
# Export Biases
# ============================================================================
# 16 L1 biases + 3 L2 biases + 1 padded "00" = 20 lines
with open('biases.mem', 'w') as f:
    # Layer 1 biases (16 values)
    for i in range(16):
        f.write(int8_to_hex(b1_q[i]) + '\n')
    
    # Layer 2 biases (3 values)
    for i in range(3):
        f.write(int8_to_hex(b2_q[i]) + '\n')
    
    # Padding (1 value)
    f.write('00\n')

print(f"Exported biases.mem (20 lines)")

# ============================================================================
# Generate Test Sample for Verilog Testbench
# ============================================================================
print("\n" + "="*80)
print("VERILOG TESTBENCH DATA")
print("="*80)

# Use the first test sample
test_sample = X_test_scaled[0]
expected_class = y_test[0]

# Quantize test sample (inputs are already scaled by 16.0, quantize to int8)
# For inputs, we don't scale further - they're already 16x
test_sample_q = quantize_to_int8(test_sample, 1.0)  # Scale by 1 since already 16x

print(f"\nTest Sample (quantized, 8-bit signed int):")
print(f"Input values (hex):")
for i, val in enumerate(test_sample_q):
    print(f"  input[{i}] = 8'h{int8_to_hex(val)} ({val:4d} decimal)")

print(f"\nExpected class: {expected_class}")

# Verify with model
model.eval()
with torch.no_grad():
    sample_tensor = torch.FloatTensor(test_sample).unsqueeze(0)
    output = model(sample_tensor)
    predicted_class = torch.argmax(output, dim=1).item()
    print(f"Model prediction: {predicted_class}")
    print(f"Match: {'YES' if predicted_class == expected_class else 'NO'}")

print("\n" + "="*80)
print("Files created:")
print("  - weights_layer1.mem (64 lines)")
print("  - weights_layer2.mem (64 lines)")
print("  - biases.mem (20 lines)")
print("="*80)
