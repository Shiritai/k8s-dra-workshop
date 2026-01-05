#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST="$WORKSHOP_DIR/manifests/demo-mps-limits.yaml"

echo "=== Module 5: Verifying MPS Advanced (Resource Control) ==="
source "$SCRIPT_DIR/run-module0-check-env.sh"

# Cleanup previous run
echo "Step 0: Cleaning up previous resources..."
kubectl delete pod mps-limited --force --grace-period=0 --ignore-not-found 2>/dev/null || true
kubectl delete resourceclaim gpu-claim-limited --ignore-not-found 2>/dev/null || true
sleep 2

echo "Step 1: Deploying MPS Workload with Limits..."
kubectl apply -f "$MANIFEST"

echo "Step 2: Waiting for pod 'mps-limited'..."
kubectl wait --for=condition=Ready pod/mps-limited --timeout=300s

echo "Step 3: Verifying Active Thread Percentage..."
# We expect the env var to be set. Actual enforcement is done by the driver.
THREAD_LIMIT=$(kubectl exec mps-limited -- bash -c "echo \$CUDA_MPS_ACTIVE_THREAD_PERCENTAGE")
if [ "$THREAD_LIMIT" == "20" ]; then
    echo "✅ Success! Thread Percentage set to 20%."
else
    echo "❌ Failed. Thread percentage is '$THREAD_LIMIT' (Expected: 20)."
    exit 1
fi

echo "Step 4: Verifying Memory Limit..."
MEM_LIMIT=$(kubectl exec mps-limited -- bash -c "echo \$CUDA_MPS_PINNED_DEVICE_MEM_LIMIT")
if [[ "$MEM_LIMIT" == *"0=1G"* ]]; then
    echo "✅ Success! Memory Limit set to 1G for Device 0."
else
    echo "❌ Failed. Memory limit is '$MEM_LIMIT' (Expected: 0=1G...)."
    exit 1
fi

echo "=== Module 5 Passed ==="
