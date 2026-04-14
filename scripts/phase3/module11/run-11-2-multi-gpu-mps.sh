#!/bin/bash
# M11.2: Multi-Device MPS per Pod
# Goal: Test whether a single Pod can consume MPS-shared resources from multiple devices.
#
# Test 11.2a: Equal split — 2 MIG slices, both MPS 50%
# Test 11.2b: Asymmetric — 1 MIG exclusive + 1 MIG MPS 30%
#
# PREREQUISITE: Cluster must have at least 2 MIG devices.

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST_A="$WORKSHOP_DIR/manifests/module11/11.2a-dual-gpu-equal.yaml"
MANIFEST_B="$WORKSHOP_DIR/manifests/module11/11.2b-dual-gpu-asymmetric.yaml"

echo "=== Module 11.2: Multi-MIG-Device MPS per Pod ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

# Check device counts (need at least 2 MIG devices)
MIG_COUNT=$(kubectl get resourceslices -o json | jq '[.items[] | select(.spec.driver=="gpu.nvidia.com") | .spec.devices[] | select(.attributes.type.string=="mig")] | length' 2>/dev/null || echo "0")
echo "Detected $MIG_COUNT MIG device(s) in ResourceSlices."
if [ "$MIG_COUNT" -lt 2 ]; then
    echo "WARNING: This test requires at least 2 MIG devices. Results may be incomplete."
fi

# Cleanup
echo "Step 1: Cleaning up previous resources..."
kubectl delete -f "$MANIFEST_B" --ignore-not-found --wait=true --grace-period=5 2>/dev/null || true
kubectl delete -f "$MANIFEST_A" --ignore-not-found --wait=true --grace-period=5 2>/dev/null || true
sleep 1

# ─── Test 11.2a: Equal Split ───
echo ""
echo "=== Test 11.2a: Dual-MIG Equal Split (2 x 50% MPS) ==="
echo "Step 2: Deploying 11.2a..."
kubectl apply -f "$MANIFEST_A"

echo "Step 3: Waiting for pod (90s timeout)..."
TEST_A_OK=true
if kubectl wait --for=condition=Ready pod/m11-2a-dual-gpu --timeout=90s 2>/dev/null; then
    echo "  [+] m11-2a-dual-gpu is Running."
else
    STATUS=$(kubectl get pod m11-2a-dual-gpu -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    echo "  [-] m11-2a-dual-gpu status: $STATUS"
    kubectl describe pod m11-2a-dual-gpu 2>/dev/null | tail -10
    TEST_A_OK=false
fi

if $TEST_A_OK; then
    echo ""
    echo "Step 4: Checking GPU visibility..."
    echo "  Pod logs:"
    kubectl logs m11-2a-dual-gpu 2>/dev/null | head -20

    echo ""
    echo "  CUDA_VISIBLE_DEVICES:"
    kubectl exec m11-2a-dual-gpu -- printenv CUDA_VISIBLE_DEVICES 2>/dev/null || echo "  (not set)"

    echo ""
    echo "  Claim allocations:"
    for claim in m11-2a-claim-gpu0 m11-2a-claim-gpu1; do
        DEVICE=$(kubectl get resourceclaim "$claim" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
        echo "    $claim -> $DEVICE"
    done
fi

# Cleanup 11.2a
echo ""
echo "Step 5: Cleaning up 11.2a..."
kubectl delete -f "$MANIFEST_A" --ignore-not-found --wait=true --grace-period=5 2>/dev/null || true
sleep 1

# ─── Test 11.2b: Asymmetric Split ───
echo ""
echo "=== Test 11.2b: Asymmetric Split (Exclusive + MPS) ==="
echo "Step 6: Deploying 11.2b..."
kubectl apply -f "$MANIFEST_B"

echo "Step 7: Waiting for pod (90s timeout)..."
TEST_B_OK=true
if kubectl wait --for=condition=Ready pod/m11-2b-asymmetric --timeout=90s 2>/dev/null; then
    echo "  [+] m11-2b-asymmetric is Running."
else
    STATUS=$(kubectl get pod m11-2b-asymmetric -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    echo "  [-] m11-2b-asymmetric status: $STATUS"
    kubectl describe pod m11-2b-asymmetric 2>/dev/null | tail -10
    TEST_B_OK=false
fi

if $TEST_B_OK; then
    echo ""
    echo "Step 8: Checking GPU visibility..."
    echo "  Pod logs:"
    kubectl logs m11-2b-asymmetric 2>/dev/null | head -20

    echo ""
    echo "  CUDA_VISIBLE_DEVICES:"
    kubectl exec m11-2b-asymmetric -- printenv CUDA_VISIBLE_DEVICES 2>/dev/null || echo "  (not set)"

    echo ""
    echo "  Claim allocations:"
    for claim in m11-2b-claim-exclusive m11-2b-claim-mps; do
        DEVICE=$(kubectl get resourceclaim "$claim" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
        echo "    $claim -> $DEVICE"
    done
fi

# Cleanup
echo ""
echo "Step 9: Cleaning up..."
kubectl delete -f "$MANIFEST_B" --ignore-not-found --wait=true --grace-period=5 2>/dev/null || true

echo ""
if $TEST_A_OK && $TEST_B_OK; then
    echo "=== Module 11.2 Complete: Multi-GPU MPS tests passed ==="
else
    echo "=== Module 11.2 Complete (with warnings) ==="
fi
