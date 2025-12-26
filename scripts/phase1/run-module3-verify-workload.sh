#!/bin/bash

# Implement run-module3-verify-workload.sh to automate the testing
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST="$WORKSHOP_DIR/manifests/demo-gpu.yaml"

echo "=== NVIDIA DRA Workshop: Verification ==="

echo "Step 1: Deploying workloads..."
kubectl apply -f "$MANIFEST"

echo "Step 2: Waiting for scheduling..."
# 簡單的等待迴圈
for i in {1..30}; do
    POD_STATUS=$(kubectl get pod pod-gpu-1 -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$POD_STATUS" == "Running" ]; then
        echo "✅ pod-gpu-1 is Running!"
        break
    fi
    echo "Waiting for pod-gpu-1 (Current status: $POD_STATUS)..."
    sleep 2
done

# Check execution result inside the pod
echo "Step 3: Checking nvidia-smi inside the pod..."
if kubectl exec pod-gpu-1 -- nvidia-smi; then
    echo "✅ Success! Workload can access the GPU."
else
    echo "❌ Failed to execute nvidia-smi in pod."
fi

# Check status of pod 2 (Expected Pending for Single GPU)
echo "Step 4: Checking pod-gpu-2 status (Expect Pending if you only have 1 GPU)..."
kubectl get pod pod-gpu-2

echo "=== Verification Complete ==="
