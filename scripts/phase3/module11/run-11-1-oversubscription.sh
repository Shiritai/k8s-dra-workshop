#!/bin/bash
# M11.1: MPS Oversubscription Tests
# Goal: Explore scheduler and runtime behavior when MPS resource requests exceed capacity.
#
# Test 11.1a: 3 Pods each requesting 50% SM threads (total 150%)
# Test 11.1b: 3 Pods each requesting 8Gi pinned VRAM on a shared GPU

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST_A="$WORKSHOP_DIR/manifests/module11/11.1a-sm-oversub.yaml"
MANIFEST_B="$WORKSHOP_DIR/manifests/module11/11.1b-vram-oversub.yaml"

echo "=== Module 11.1: MPS Oversubscription Tests ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

# Cleanup
echo "Step 1: Cleaning up previous resources..."
kubectl delete -f "$MANIFEST_B" --ignore-not-found --wait=true --grace-period=5 2>/dev/null || true
kubectl delete -f "$MANIFEST_A" --ignore-not-found --wait=true --grace-period=5 2>/dev/null || true
sleep 1

# ─── Test 11.1a: SM Oversubscription ───
echo ""
echo "=== Test 11.1a: SM Oversubscription (3 x 50% = 150%) ==="
echo "Step 2: Deploying 11.1a..."
kubectl apply -f "$MANIFEST_A"

echo "Step 3: Waiting for pods (90s timeout)..."
TEST_A_OK=true
for pod in m11-1a-pod-1 m11-1a-pod-2 m11-1a-pod-3; do
    if kubectl wait --for=condition=Ready pod/$pod --timeout=90s 2>/dev/null; then
        echo "  [+] $pod is Running."
    else
        STATUS=$(kubectl get pod $pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        echo "  [-] $pod status: $STATUS"
        kubectl describe pod $pod 2>/dev/null | tail -5
        TEST_A_OK=false
    fi
done

echo ""
echo "Step 4: Checking claim allocation..."
CLAIM_DEVICE=$(kubectl get resourceclaim m11-1a-claim -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
echo "  Shared claim device: $CLAIM_DEVICE"

if $TEST_A_OK; then
    echo ""
    echo "Step 5: Collecting nvidia-smi from each pod..."
    for pod in m11-1a-pod-1 m11-1a-pod-2 m11-1a-pod-3; do
        echo "  --- $pod ---"
        kubectl exec $pod -- nvidia-smi --query-gpu=gpu_name,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null || echo "  (nvidia-smi failed)"
    done
fi

echo ""
echo "Step 6: Results for 11.1a"
SCHEDULED=$(kubectl get pods -l '!batch.kubernetes.io/job-name' --field-selector=metadata.name=m11-1a-pod-1 --no-headers 2>/dev/null | wc -l)
RUNNING=$(kubectl get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | grep 'm11-1a' | wc -l)
PENDING=$(kubectl get pods --field-selector=status.phase=Pending --no-headers 2>/dev/null | grep 'm11-1a' | wc -l)
echo "  Running: $RUNNING, Pending: $PENDING"
if [ "$RUNNING" -eq 3 ]; then
    echo "  --> MPS allows SM oversubscription (all 3 pods scheduled and running)"
elif [ "$RUNNING" -gt 0 ]; then
    echo "  --> Partial scheduling: some pods pending (scheduler may enforce thread limits)"
else
    echo "  --> No pods running (scheduler rejected oversubscription)"
fi

# Cleanup 11.1a
echo ""
echo "Step 7: Cleaning up 11.1a..."
kubectl delete -f "$MANIFEST_A" --ignore-not-found --wait=true --grace-period=5 2>/dev/null || true
sleep 1

# ─── Test 11.1b: VRAM Oversubscription ───
echo ""
echo "=== Test 11.1b: VRAM Oversubscription (3 x 8Gi pinned memory) ==="
echo "Step 8: Deploying 11.1b..."
kubectl apply -f "$MANIFEST_B"

echo "Step 9: Waiting for pods (120s timeout)..."
TEST_B_OK=true
for pod in m11-1b-pod-1 m11-1b-pod-2 m11-1b-pod-3; do
    if kubectl wait --for=condition=Ready pod/$pod --timeout=120s 2>/dev/null; then
        echo "  [+] $pod is Running."
    else
        STATUS=$(kubectl get pod $pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        echo "  [-] $pod status: $STATUS"
        kubectl describe pod $pod 2>/dev/null | tail -5
        TEST_B_OK=false
    fi
done

echo ""
echo "Step 10: Waiting for CUDA stress test output (nvcc compile ~30s)..."
for attempt in $(seq 1 60); do
    if kubectl logs m11-1b-pod-1 2>/dev/null | grep -q '\[cuda\]'; then
        break
    fi
    sleep 2
done

echo "  Checking VRAM allocation results..."
for pod in m11-1b-pod-1 m11-1b-pod-2 m11-1b-pod-3; do
    echo "  --- $pod logs ---"
    kubectl logs $pod 2>/dev/null | grep -E '\[cuda\]|FAILED|Success' || echo "  (no output yet)"
done

echo ""
echo "Step 11: Results for 11.1b"
RUNNING_B=$(kubectl get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | grep 'm11-1b' | wc -l)
FAILED_B=$(kubectl get pods --field-selector=status.phase=Failed --no-headers 2>/dev/null | grep 'm11-1b' | wc -l)
echo "  Running: $RUNNING_B, Failed: $FAILED_B"
if [ "$FAILED_B" -gt 0 ]; then
    echo "  --> Some pods failed (likely OOM from VRAM oversubscription)"
else
    echo "  --> All pods survived (MPS pinnedMemoryLimit may be advisory or GPU has enough VRAM)"
fi

# Cleanup
echo ""
echo "Step 12: Cleaning up..."
kubectl delete -f "$MANIFEST_B" --ignore-not-found --wait=true --grace-period=5 2>/dev/null || true

echo ""
echo "=== Module 11.1 Complete ==="
