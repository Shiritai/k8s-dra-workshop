#!/bin/bash
# Module 5: DRA-Managed MPS Advanced
# Resource limits via GpuConfig, enforced by driver (not Pod env vars).
# For the legacy Host MPS approach, see run-module5-mps-advanced.archive.sh.
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST_A="$WORKSHOP_DIR/manifests/module5/demo-dra-mps-limits.yaml"
MANIFEST_B="$WORKSHOP_DIR/manifests/module5/demo-dra-mps-shared.yaml"

echo "=== Module 5: DRA-Managed MPS Advanced (Experimental) ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

# ─── Part A: Single Pod with MPS Limits ───
echo ""
echo "=== Part A: DRA-MPS with Resource Limits (20% thread, 1Gi mem) ==="

echo "Step 2: Deploying limited MPS workload..."
kubectl apply -f "$MANIFEST_A"

echo "Step 3: Waiting for pod..."
if kubectl wait --for=condition=Ready pod/dra-mps-limited --timeout=120s; then
    echo "  ✅ dra-mps-limited is Ready."
else
    echo "  ❌ Failed to start."
    kubectl describe pod dra-mps-limited | tail -15
    exit 1
fi

echo "Step 4: Verifying DRA-injected MPS config..."
echo "  4a. Claim config:"
kubectl get resourceclaim gpu-claim-dra-mps-limited -o jsonpath='{.status.allocation.devices.config[0].opaque.parameters}' 2>/dev/null | jq .

echo "  4b. MPS env vars (injected by CDI):"
kubectl exec dra-mps-limited -- env 2>&1 | grep "CUDA_MPS" || echo "    (not found)"

echo "  4c. MPS pipe directory:"
kubectl exec dra-mps-limited -- ls -la /tmp/nvidia-mps/ 2>&1 || echo "    (not found)"

echo "Step 5: CUDA memory allocation test..."
kubectl exec dra-mps-limited -- bash -c "cat <<'CUDAEOF' > /tmp/mps_test.cu
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
        return 0;
    } else {
        std::cout << \"Allocation failed: \" << cudaGetErrorString(err) << std::endl;
        return 1;
    }
}
CUDAEOF"
kubectl exec dra-mps-limited -- nvcc /tmp/mps_test.cu -o /tmp/mps_test 2>&1

echo "  Allocating 100MB (sanity check)..."
if kubectl exec dra-mps-limited -- /tmp/mps_test 100; then
    echo "  ✅ 100MB succeeded."
else
    echo "  ❌ 100MB failed — MPS or GPU not functional."
fi

echo "  Allocating 2GB (stress test)..."
if ! kubectl exec dra-mps-limited -- /tmp/mps_test 2048; then
    echo "  ✅ 2GB rejected (limit enforced)."
else
    echo "  ⚠️  2GB succeeded. defaultPinnedDeviceMemoryLimit only restricts cudaMallocHost, not cudaMalloc."
fi

echo "  Comparing with Module 5:"
echo "    Module 5: limits set via CUDA_MPS_ACTIVE_THREAD_PERCENTAGE env var in Pod spec"
echo "    Module 5: limits declared in GpuConfig.sharing.mpsConfig (driver-managed)"

# Cleanup Part A
echo ""
echo "Step 6: Cleaning up Part A..."
kubectl delete -f "$MANIFEST_A" --ignore-not-found --wait=true 2>/dev/null || true
sleep 2

# ─── Part B: 3 Pods Sharing 1 Claim ───
echo ""
echo "=== Part B: 3 Pods Sharing 1 DRA-MPS Claim (30% thread each) ==="

echo "Step 7: Deploying shared MPS workload..."
kubectl apply -f "$MANIFEST_B"

echo "Step 8: Waiting for pods..."
ALL_OK=true
for pod in dra-mps-s1 dra-mps-s2 dra-mps-s3; do
    if kubectl wait --for=condition=Ready "pod/$pod" --timeout=120s 2>/dev/null; then
        echo "  ✅ $pod is Ready."
    else
        echo "  ❌ $pod failed."
        kubectl describe pod "$pod" 2>/dev/null | tail -10
        ALL_OK=false
    fi
done

if $ALL_OK; then
    echo "Step 9: Verifying all pods share the same GPU..."
    for pod in dra-mps-s1 dra-mps-s2 dra-mps-s3; do
        GPU=$(kubectl exec "$pod" -- nvidia-smi -L 2>&1 | head -1)
        echo "  $pod: $GPU"
    done

    echo "  Comparing with Module 5 scheme-b:"
    echo "    Module 5: 3 pods with hostIPC=true, manual hostPath, manual env vars"
    echo "    Module 5: 3 pods with zero special config — DRA handles everything"
fi

echo "Step 10: Cleanup..."
kubectl delete -f "$MANIFEST_B" --ignore-not-found --wait=false 2>/dev/null || true

echo "=== Module 5 Complete ==="
