#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST="$WORKSHOP_DIR/manifests/demo-mps-limits.yaml"

echo "=== Module 5: Verifying MPS Advanced (Resource Control) ==="
source "$SCRIPT_DIR/run-module0-check-env.sh"

# Cleanup previous run
# Cleanup previous run and ANY leftover claims from previous modules
echo "Step 0: Cleaning up previous resources..."
kubectl delete pod --all --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim --all 2>/dev/null || true
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


# Create a test CUDA program
echo "Step 3: Creating CUDA Test Program..."
kubectl exec mps-limited -- bash -c "cat <<EOF > /tmp/mps_test.cu
#include <cuda_runtime.h>
#include <iostream>
#include <string>

int main(int argc, char* argv[]) {
    size_t size_mb = std::stoul(argv[1]);
    size_t size = size_mb * 1024 * 1024;
    void* d_ptr;
    cudaError_t err = cudaMalloc(&d_ptr, size);
    
    if (err == cudaSuccess) {
        std::cout << \"Allocated \" << size_mb << \"MB successfully\" << std::endl;
        cudaFree(d_ptr);
        return 0; // Success
    } else {
        std::cout << \"Allocation failed: \" << cudaGetErrorString(err) << std::endl;
        return 1; // Failed
    }
}
EOF"


echo "Step 4: Compiling CUDA Test..."
kubectl exec mps-limited -- nvcc /tmp/mps_test.cu -o /tmp/mps_test

echo "Step 5: Running Sanity Check (100MB)..."
echo "Step 5: Running Sanity Check (100MB)..."
if kubectl exec mps-limited -- /tmp/mps_test 100; then
    echo "✅ Sanity Check Passed: MPS is alive."
    
    echo "Step 6: Running OOM Stress Test (2GB)..."
    if ! kubectl exec mps-limited -- /tmp/mps_test 2048; then
        echo "✅ Success! Memory limit enforced (Allocation failed as expected)."
    else
        echo "❌ Failed. Allocated 2GB despite 1GB limit."
        exit 1
    fi
else
    echo "❌ Sanity Check Failed: Could not allocate 100MB. MPS might be broken."
    exit 1
fi

echo "Step 7: Verifying Config Injection (Driver Functionality)..."
MEM_LIMIT=$(kubectl exec mps-limited -- bash -c "echo \$CUDA_MPS_PINNED_DEVICE_MEM_LIMIT")
if [[ "$MEM_LIMIT" == *"0=1G"* ]]; then
    echo "✅ Success! Memory Limit Env Var injected correctly."
else
    echo "❌ Failed. Env Var missing."
    exit 1
fi



echo "=== Module 5 Passed ==="
