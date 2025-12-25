#!/bin/bash
set -e

NAMESPACE="nvidia-system"
RELEASE_NAME="nvidia-dra-driver"

echo "=== NVIDIA DRA Workshop: Driver Installation ==="

# 1. Add Helm Repo
echo "Step 1: Adding NVIDIA Helm repository..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# 2. Install Driver
echo "Step 2: Installing NVIDIA DRA Driver (Structured Parameters)..."
# Note: gpuResourcesEnabledOverride=true is required for v0.25.0+ to enable experimental features
# Note: kubeletPlugin.enabled=true is required to run the Node Agent
helm upgrade -i "$RELEASE_NAME" nvidia/nvidia-dra-driver-gpu \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set gpuResourcesEnabledOverride=true \
  --set kubeletPlugin.enabled=true \
  --wait

echo "✅ Driver installed successfully."

# 3. Verify Components
echo "Step 3: Verifying driver components..."
kubectl get pods -n "$NAMESPACE"
echo "-----------------------------------"
kubectl get ds -n "$NAMESPACE"

# 4. Check ResourceSlice
echo "Step 4: Checking ResourceSlice creation..."
echo "Waiting for Node Agent to publish resources..."
sleep 5
SLC_COUNT=$(kubectl get resourceslices --no-headers 2>/dev/null | wc -l)
if [ "$SLC_COUNT" -gt 0 ]; then
    echo "✅ Success: $SLC_COUNT ResourceSlice(s) found."
    kubectl get resourceslices
else
    echo "⚠️ Warning: No ResourceSlices found yet. Please check DaemonSet logs."
fi

echo "=== Driver Installation Complete! ==="
