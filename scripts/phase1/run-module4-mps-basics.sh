#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST="$WORKSHOP_DIR/manifests/demo-mps-basics.yaml"

echo "=== Module 4: Verifying MPS Basics (Spatial Sharing) ==="
source "$SCRIPT_DIR/run-module0-check-env.sh"

# Cleanup previous run
# Cleanup previous run and ANY leftover claims from previous modules
echo "Step 0: Cleaning up previous resources..."
kubectl delete pod --all --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim --all 2>/dev/null || true
sleep 2

echo "Step 1: Deploying MPS Basic Workload..."
kubectl apply -f "$MANIFEST"

echo "Step 2: Waiting for pod..."
kubectl wait --for=condition=Ready pod/mps-basic --timeout=300s

echo "Step 3: Verifying MPS Connection..."
# Attempt to locate nvidia-cuda-mps-control
MPS_CMD="nvidia-cuda-mps-control"
if kubectl exec mps-basic -- which nvidia-cuda-mps-control >/dev/null 2>&1; then
    MPS_CMD="nvidia-cuda-mps-control"
elif kubectl exec mps-basic -- ls /usr/local/cuda/bin/nvidia-cuda-mps-control >/dev/null 2>&1; then
    MPS_CMD="/usr/local/cuda/bin/nvidia-cuda-mps-control"
else
    echo "⚠️  Warning: nvidia-cuda-mps-control not found in standard paths."
    echo "    Checking /tmp/nvidia-mps pipe existence as fallback..."
    if kubectl exec mps-basic -- ls /tmp/nvidia-mps/control >/dev/null 2>&1; then
       echo "✅ Success! MPS Control Pipe found."
       exit 0
    else
       echo "❌ Failed. MPS Control Pipe NOT found."
       exit 1
    fi
fi

if kubectl exec mps-basic -- timeout 5s bash -c "echo ps | $MPS_CMD"; then
    echo "✅ Success! Pod is connected to Host MPS Daemon."
else
    echo "❌ Failed to communicate with MPS Daemon."
    exit 1
fi

echo "=== Module 4 Passed ==="
