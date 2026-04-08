#!/bin/bash

# Implement run-module3-verify-workload.sh to automate the testing
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST="$WORKSHOP_DIR/manifests/module3/demo-gpu.yaml"

echo "=== NVIDIA DRA Workshop: Verification ==="

# Preamble: Cleanup to ensure clean state
echo "Step 0: Cleaning up previous Module 3 workloads..."
kubectl delete pod pod-gpu-1 pod-gpu-2 --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim gpu-claim-1 gpu-claim-2 --ignore-not-found 2>/dev/null || true
sleep 2

echo "Step 1: Deploying workloads..."
kubectl apply -f "$MANIFEST"

echo "Step 2: Waiting for scheduling..."
if kubectl wait --for=condition=Ready pod/pod-gpu-1 --timeout=120s 2>/dev/null; then
    echo "✅ pod-gpu-1 is Running!"
else
    echo "❌ pod-gpu-1 failed to become Ready within 120s."
    kubectl describe pod pod-gpu-1 | tail -10
    exit 1
fi

# Check execution result inside the pod
echo "Step 3: Checking nvidia-smi inside the pod..."
OUTPUT=$(kubectl exec pod-gpu-1 -- nvidia-smi 2>&1) || true
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q "NVIDIA-SMI"; then
    echo "✅ Success! Workload can access the GPU."
else
    echo "❌ Failed to execute nvidia-smi in pod."
    exit 1
fi

# Check status of pod 2 (Expected Pending for Single GPU)
echo "Step 4: Checking pod-gpu-2 status (Expect Pending if you only have 1 GPU)..."
kubectl get pod pod-gpu-2

echo "Step 5: Cleanup..."
kubectl delete pod pod-gpu-1 pod-gpu-2 --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim gpu-claim-1 gpu-claim-2 --ignore-not-found 2>/dev/null || true

echo "=== Verification Complete ==="
