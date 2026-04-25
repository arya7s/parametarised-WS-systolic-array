import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np
import joblib
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

# =============================================================================
# 1. SETUP & DATA PREPARATION
# =============================================================================
# Setting seeds ensures you get the same high accuracy every time you run this
torch.manual_seed(42)
np.random.seed(42)

iris = load_iris()
X, y = iris.data, iris.target

# Split into 80% Training and 20% Test (30 flowers)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled  = scaler.transform(X_test)

# SYNC: Save the scaler for streamer.py to use later
joblib.dump(scaler, 'iris_scaler.bin')
print("✅ Scaler saved to 'iris_scaler.bin'")

# Fixed-Point Scaling for Hardware (Factor of 16)
SCALE_FACTOR = 16
X_train_t = torch.tensor(X_train_scaled * SCALE_FACTOR, dtype=torch.float32)
y_train_t = torch.tensor(y_train, dtype=torch.long)
X_test_t  = torch.tensor(X_test_scaled * SCALE_FACTOR,  dtype=torch.float32)
# ====================== EXPORT REAL INPUT FOR TESTBENCH ======================
print("\n=== REAL INPUTS FOR HARDWARE TESTBENCH (copy-paste) ===")
for i in range(min(5, len(X_test_t))):   # first 5 test samples
    acts = X_test_t[i].round().int().tolist()           # already *16 + rounded
    packed = (acts[0] & 0xFF) | ((acts[1] & 0xFF)<<8) | ((acts[2] & 0xFF)<<16) | ((acts[3] & 0xFF)<<24)
    print(f"send_input(32'h{packed:08X});   # sample {i} → acts={acts}")
y_test_t  = torch.tensor(y_test,  dtype=torch.long)

# =============================================================================
# 2. MODEL DEFINITION (4-16-3, No Bias)
# =============================================================================
class TinyMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(4, 16, bias=False)
        self.fc2 = nn.Linear(16, 3,  bias=False)
    
    def forward(self, x):
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x

model = TinyMLP()
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=0.005)

# =============================================================================
# 3. TRAINING LOOP
# =============================================================================
print("\nStarting Training (180 Epochs)...")
for epoch in range(180):
    optimizer.zero_grad()
    outputs = model(X_train_t)
    loss = criterion(outputs, y_train_t)
    loss.backward()
    optimizer.step()
    
    if (epoch + 1) % 50 == 0:
        # Calculate Training Accuracy for monitoring
        _, predicted_train = torch.max(outputs, 1)
        train_acc = (predicted_train == y_train_t).sum().item() / len(y_train_t)
        print(f"Epoch [{epoch+1}/180] | Loss: {loss.item():.4f} | Train Acc: {train_acc*100:.2f}%")

# =============================================================================
# 4. FINAL TEST ACCURACY (The section you requested)
# =============================================================================
model.eval() # Set model to evaluation mode
with torch.no_grad():
    # Run the 30 test samples through the model
    test_outputs = model(X_test_t)
    
    # Get the index of the highest logit (the prediction)
    _, predicted_test = torch.max(test_outputs, 1)
    
    # Calculate how many match the true labels (y_test_t)
    correct = (predicted_test == y_test_t).sum().item()
    total = y_test_t.size(0)
    test_accuracy = (correct / total) * 100

    print("\n" + "="*30)
    print(f"       TEST EVALUATION")
    print("="*30)
    print(f"Total Test Samples: {total}")
    print(f"Correct Predictions: {correct}")
    print(f"Final Test Accuracy: {test_accuracy:.2f}%")
    print("="*30)

# =============================================================================
# 5. EXPORT WEIGHTS FOR SYSTOLIC ARRAY
# =============================================================================
def export_systolic_weights(filename, weights, in_f, out_f, is_layer2=False):
    # Scale weights by 8 to preserve precision
    q_weights = (weights * 8).clamp(-128, 127).round().detach().numpy().astype(int)
    hex_entries = []
    
    for tile_idx in range(4):
        for row in range(4):
            for col in range(4):
                val = 0
                if not is_layer2:
                    out_idx, in_idx = (tile_idx * 4 + col), row
                    if out_idx < out_f and in_idx < in_f: val = q_weights[out_idx, in_idx]
                else:
                    out_idx, in_idx = col, (tile_idx * 4 + row)
                    if out_idx < out_f and in_idx < in_f: val = q_weights[out_idx, in_idx]
                hex_entries.append(format(val & 0xFF, '02x'))
    
    with open(filename, "w") as f:
        f.write("\n".join(hex_entries))
    print(f"📦 Exported {filename}")

export_systolic_weights("weights_layer1.mem", model.fc1.weight, 4, 16)
export_systolic_weights("weights_layer2.mem", model.fc2.weight, 16, 3, is_layer2=True)