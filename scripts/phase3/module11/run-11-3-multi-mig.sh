#!/bin/bash
# M11.3: Multi-MIG MPS per Pod
# Goal: Test whether a single Pod can consume MPS-shared resources from multiple MIG devices.
#
# Test 11-3a: Equal split — 2 MIG slices, both MPS 50% (with CUDA benchmark)
# Test 11-3b: Asymmetric — 1 MIG exclusive + 1 MIG MPS 30% (with CUDA benchmark)
#
# PREREQUISITE: Cluster must have at least 2 MIG devices.

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST_A="$WORKSHOP_DIR/manifests/module11/11-3a-dual-mig-equal.yaml"
MANIFEST_B="$WORKSHOP_DIR/manifests/module11/11-3b-asymmetric-mig.yaml"

echo "=== Module 11.3: Multi-MIG MPS per Pod ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

# Check device counts (need at least 2 MIG devices)
MIG_COUNT=$(kubectl get resourceslices -o json | jq '[.items[] | select(.spec.driver=="gpu.nvidia.com") | .spec.devices[] | select(.attributes.type.string=="mig")] | length' 2>/dev/null || echo "0")
echo "Detected $MIG_COUNT MIG device(s) in ResourceSlices."
if [ "$MIG_COUNT" -lt 2 ]; then
    echo "WARNING: This test requires at least 2 MIG devices. Results may be incomplete."
fi

# ─────────────────────────────────────────────────────────────────
# Cleanup: delete ALL known resources by name (bulletproof)
# ─────────────────────────────────────────────────────────────────
echo ""
echo "Step 0: Cleaning up ALL previous Module 11 resources..."

# Delete ALL module 11 pods (11-1, 11-2, 11-3 + old naming)
for pod in \
    m11-1a-stress-pod-1 m11-1a-stress-pod-2 m11-1a-stress-pod-3 \
    m11-1a-thread-pod-1 m11-1a-thread-pod-2 m11-1a-thread-pod-3 \
    m11-1a-pod-1 m11-1a-pod-2 m11-1a-pod-3 \
    m11-1b-pod-1 m11-1b-pod-2 m11-1b-pod-3 \
    m11-1b-limit-pod-1 m11-1b-limit-pod-2 m11-1b-limit-pod-3 \
    m11-1b-mps-pod-1 m11-1b-mps-pod-2 m11-1b-mps-pod-3 \
    m11-1c-mps-pod-1 m11-1c-mps-pod-2 m11-1c-mps-pod-3 \
    m11-2a-pod-1 m11-2a-pod-2 m11-2a-pod-3 \
    m11-2b-pod-1 m11-2b-pod-2 m11-2b-pod-3 \
    m11-2a-dual-mig-cuda-stress m11-2a-dual-gpu \
    m11-2b-asymmetric-cuda-stress m11-2b-asymmetric \
    m11-3a-pod m11-3b-pod; do
    kubectl delete pod "$pod" --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
done

sleep 3

# Delete ALL claims
for claim in \
    m11-1a-stress-claim m11-1a-thread-claim m11-1a-claim \
    m11-1b-claim m11-1b-limit-claim m11-1b-mps-limit-claim m11-1c-mps-limit-claim \
    m11-2a-claim m11-2b-claim \
    m11-2a-stress-mig0 m11-2a-stress-mig1 m11-2a-claim-gpu0 m11-2a-claim-gpu1 \
    m11-2b-stress-exclusive m11-2b-stress-mps30 m11-2b-claim-exclusive m11-2b-claim-mps \
    m11-3a-claim-mig0 m11-3a-claim-mig1 \
    m11-3b-claim-exclusive m11-3b-claim-mps30; do
    kubectl delete resourceclaim "$claim" --ignore-not-found --wait=true 2>/dev/null || true
done

# Delete ALL configmaps
for cm in \
    m11-1a-stress-cuda m11-1a-thread-cuda m11-1a-cuda m11-1b-cuda \
    m11-1b-limit-test m11-1b-mps-limit-cuda m11-1c-mps-limit-cuda m11-1b-vram-stress \
    m11-2a-cuda m11-2b-cuda \
    m11-1-cuda m11-2-cuda \
    m11-2a-cuda-stress-src m11-2b-cuda-stress-src m11-3a-cuda m11-3b-cuda; do
    kubectl delete configmap "$cm" --ignore-not-found 2>/dev/null || true
done

sleep 1
echo "  Cleanup done."

# ─── Test 11-3a: Equal Split ───
echo ""
echo "================================================================"
echo "  Test 11-3a: Dual-MIG Equal Split (2 × MPS 50%, CUDA benchmark)"
echo "================================================================"
CUDA_DIR="$WORKSHOP_DIR/manifests/module11/cuda"

echo "Step 1: Creating ConfigMap and deploying 11-3a..."
kubectl create configmap m11-3a-cuda --from-file="$CUDA_DIR/dual_mig_stress.cu" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$MANIFEST_A"

echo "Step 2: Waiting for pod (180s timeout, includes nvcc compile)..."
TEST_A_OK=true
if kubectl wait --for=condition=Ready pod/m11-3a-pod --timeout=180s 2>/dev/null; then
    echo "  [+] m11-3a-pod is Running."
else
    STATUS=$(kubectl get pod m11-3a-pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    echo "  [-] m11-3a-pod status: $STATUS"
    kubectl describe pod m11-3a-pod 2>/dev/null | tail -10
    TEST_A_OK=false
fi

if $TEST_A_OK; then
    echo ""
    echo "Step 3: Waiting for CUDA output (up to 90s)..."
    for attempt in $(seq 1 45); do
        if kubectl logs m11-3a-pod 2>/dev/null | grep -q 'SAXPY\|cudaGetDeviceCount\|Done'; then
            break
        fi
        sleep 2
    done

    echo ""
    echo "Step 4: CUDA Benchmark Results"
    echo "  ─────────────────────────────────────────────────"
    kubectl logs m11-3a-pod 2>/dev/null || echo "  (no output)"
    echo "  ─────────────────────────────────────────────────"

    echo ""
    echo "Step 5: Claim allocations"
    for claim in m11-3a-claim-mig0 m11-3a-claim-mig1; do
        DEVICE=$(kubectl get resourceclaim "$claim" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
        echo "    $claim -> $DEVICE"
    done
fi

echo ""
echo "Step 6: Cleaning up 11-3a..."
kubectl delete pod m11-3a-pod --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
sleep 2
for claim in m11-3a-claim-mig0 m11-3a-claim-mig1; do
    kubectl delete resourceclaim "$claim" --ignore-not-found --wait=true 2>/dev/null || true
done
kubectl delete configmap m11-3a-cuda --ignore-not-found 2>/dev/null || true
sleep 2

# ─── Test 11-3b: Asymmetric Split ───
echo ""
echo "================================================================"
echo "  Test 11-3b: Asymmetric Split (Exclusive + MPS 30%, CUDA benchmark)"
echo "================================================================"
echo "Step 7: Creating ConfigMap and deploying 11-3b..."
kubectl create configmap m11-3b-cuda --from-file="$CUDA_DIR/asymmetric_stress.cu" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$MANIFEST_B"

echo "Step 8: Waiting for pod (180s timeout, includes nvcc compile)..."
TEST_B_OK=true
if kubectl wait --for=condition=Ready pod/m11-3b-pod --timeout=180s 2>/dev/null; then
    echo "  [+] m11-3b-pod is Running."
else
    STATUS=$(kubectl get pod m11-3b-pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    echo "  [-] m11-3b-pod status: $STATUS"
    kubectl describe pod m11-3b-pod 2>/dev/null | tail -10
    TEST_B_OK=false
fi

if $TEST_B_OK; then
    echo ""
    echo "Step 9: Waiting for CUDA output (up to 90s)..."
    for attempt in $(seq 1 45); do
        if kubectl logs m11-3b-pod 2>/dev/null | grep -q 'SAXPY\|cudaGetDeviceCount\|Done'; then
            break
        fi
        sleep 2
    done

    echo ""
    echo "Step 10: CUDA Benchmark Results"
    echo "  ─────────────────────────────────────────────────"
    kubectl logs m11-3b-pod 2>/dev/null || echo "  (no output)"
    echo "  ─────────────────────────────────────────────────"

    echo ""
    echo "Step 11: Claim allocations"
    for claim in m11-3b-claim-exclusive m11-3b-claim-mps30; do
        DEVICE=$(kubectl get resourceclaim "$claim" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
        echo "    $claim -> $DEVICE"
    done
fi

echo ""
echo "Step 12: Cleaning up 11-3b..."
kubectl delete pod m11-3b-pod --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
sleep 2
for claim in m11-3b-claim-exclusive m11-3b-claim-mps30; do
    kubectl delete resourceclaim "$claim" --ignore-not-found --wait=true 2>/dev/null || true
done
kubectl delete configmap m11-3b-cuda --ignore-not-found 2>/dev/null || true

echo ""
if $TEST_A_OK && $TEST_B_OK; then
    echo "=== Module 11.3 Complete ==="
else
    echo "=== Module 11.3 Complete (with warnings) ==="
fi
echo ""
echo "Summary:"
echo "  11-3a — Dual-MIG equal MPS: CUDA sees only 1 device (MPS = single-device context)"
echo "  11-3b — Exclusive + MPS mix: only MPS device visible (exclusive claim wasted)"
