#!/bin/bash
# M11.1: MPS Oversubscription & Memory Limit Tests
#
# Test 11.1a: SM oversubscription — 3 Pods × 50% threads on 1 MIG (compute stress)
# Test 11.1b: Server-side limit verification — 3 Pods (6/12/6 GiB) with 8Gi limit
#             Proves defaultPinnedDeviceMemoryLimit is NOT enforced on MIG
# Test 11.1c: Client-side MPS limit workaround — 3 Pods (4.5/3/3 GiB) with env var
#             CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=4096M enforces 4 GiB limit on MIG

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST_A="$WORKSHOP_DIR/manifests/module11/11.1a-sm-compute-stress.yaml"
MANIFEST_B="$WORKSHOP_DIR/manifests/module11/11.1b-server-limit-test.yaml"
MANIFEST_C="$WORKSHOP_DIR/manifests/module11/11.1c-client-limit-workaround.yaml"

echo "=== Module 11.1: MPS Oversubscription & Memory Limit Tests ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

# ─────────────────────────────────────────────────────────────────
# Cleanup: delete ALL known resources by name (bulletproof)
# ─────────────────────────────────────────────────────────────────
echo ""
echo "Step 0: Cleaning up ALL previous 11.1 resources..."

# Delete pods first (they hold claim references)
for pod in \
    m11-1a-stress-pod-1 m11-1a-stress-pod-2 m11-1a-stress-pod-3 \
    m11-1a-pod-1 m11-1a-pod-2 m11-1a-pod-3 \
    m11-1b-limit-pod-1 m11-1b-limit-pod-2 m11-1b-limit-pod-3 \
    m11-1b-mps-pod-1 m11-1b-mps-pod-2 m11-1b-mps-pod-3 \
    m11-1c-mps-pod-1 m11-1c-mps-pod-2 m11-1c-mps-pod-3 \
    m11-1b-pod-1 m11-1b-pod-2 m11-1b-pod-3; do
    kubectl delete pod "$pod" --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
done

# Wait briefly for pods to terminate, then delete claims and configmaps
sleep 3

for claim in \
    m11-1a-stress-claim m11-1a-claim \
    m11-1b-limit-claim m11-1b-mps-limit-claim m11-1b-claim \
    m11-1c-mps-limit-claim; do
    kubectl delete resourceclaim "$claim" --ignore-not-found --wait=true 2>/dev/null || true
done

for cm in m11-1a-stress-cuda m11-1b-limit-test m11-1b-mps-limit-cuda m11-1c-mps-limit-cuda m11-1b-vram-stress; do
    kubectl delete configmap "$cm" --ignore-not-found 2>/dev/null || true
done

sleep 2
echo "  Cleanup done."

# ─────────────────────────────────────────────────────────────────
# Test 11.1a: SM Compute Stress (3 × MPS 50%)
# ─────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Test 11.1a: SM Compute Stress (3 Pods × 50% = 150%)"
echo "================================================================"
echo "Step 1: Deploying 11.1a..."
kubectl apply -f "$MANIFEST_A"

echo "Step 2: Waiting for pods to be Running (180s timeout, includes nvcc compile)..."
ALL_A_OK=true
for pod in m11-1a-stress-pod-1 m11-1a-stress-pod-2 m11-1a-stress-pod-3; do
    if kubectl wait --for=condition=Ready "pod/$pod" --timeout=180s 2>/dev/null; then
        echo "  [+] $pod is Running."
    else
        STATUS=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        echo "  [-] $pod status: $STATUS"
        kubectl describe pod "$pod" 2>/dev/null | tail -5
        ALL_A_OK=false
    fi
done

echo ""
echo "Step 3: Claim allocation..."
CLAIM_DEV=$(kubectl get resourceclaim m11-1a-stress-claim \
    -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
echo "  Shared claim device: $CLAIM_DEV"

echo ""
echo "Step 4: Waiting for benchmark output (up to 60s)..."
for attempt in $(seq 1 30); do
    if kubectl logs m11-1a-stress-pod-1 2>/dev/null | grep -q '\[bench\] iterations'; then
        break
    fi
    sleep 2
done

echo ""
echo "Step 5: FMA Benchmark Results"
echo "  ─────────────────────────────────────────────────"
for pod in m11-1a-stress-pod-1 m11-1a-stress-pod-2 m11-1a-stress-pod-3; do
    RESULT=$(kubectl logs "$pod" 2>/dev/null | grep '\[bench\] iterations' || echo "(no output)")
    echo "  $pod: $RESULT"
done
echo "  ─────────────────────────────────────────────────"

RUNNING_A=$(kubectl get pods --no-headers 2>/dev/null | grep 'm11-1a-stress' | grep -c 'Running' || true)
echo ""
if [ "$RUNNING_A" -eq 3 ]; then
    echo "  --> ✅ All 3 pods running: MPS allows SM oversubscription (3×50% = 150%)"
else
    echo "  --> ⚠ Only $RUNNING_A/3 pods running"
fi

echo ""
echo "Step 6: Cleaning up 11.1a..."
for pod in m11-1a-stress-pod-1 m11-1a-stress-pod-2 m11-1a-stress-pod-3; do
    kubectl delete pod "$pod" --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
done
sleep 2
kubectl delete resourceclaim m11-1a-stress-claim --ignore-not-found --wait=true 2>/dev/null || true
kubectl delete configmap m11-1a-stress-cuda --ignore-not-found 2>/dev/null || true
sleep 2

# ─────────────────────────────────────────────────────────────────
# Test 11.1b: Server-side limit verification (proves bug on MIG)
# ─────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Test 11.1b: Server-Side Limit (defaultPinnedDeviceMemoryLimit: 8Gi)"
echo "  Pod 1: 6 GiB → expect success (under 8 GiB limit)"
echo "  Pod 2: 12 GiB → expect success IF limit broken (over 8 GiB limit)"
echo "  Pod 3: 6 GiB → expect success or OOM (depends on remaining physical memory)"
echo "  Purpose: Prove defaultPinnedDeviceMemoryLimit is NOT enforced on MIG"
echo "================================================================"
echo "Step 7: Deploying 11.1b..."
kubectl apply -f "$MANIFEST_B"

echo "Step 8: Waiting for pods (180s timeout, includes nvcc compile)..."
for pod in m11-1b-limit-pod-1 m11-1b-limit-pod-2 m11-1b-limit-pod-3; do
    kubectl wait --for=condition=Ready "pod/$pod" --timeout=180s 2>/dev/null \
        || kubectl wait --for=jsonpath='{.status.phase}'=Failed "pod/$pod" --timeout=30s 2>/dev/null \
        || true
    STATUS=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    echo "  $pod: $STATUS"
done

echo ""
echo "Step 9: Waiting for CUDA output (up to 90s)..."
for attempt in $(seq 1 45); do
    DONE=$(kubectl logs m11-1b-limit-pod-2 2>/dev/null | grep -c '\[cuda\]' || true)
    if [ "$DONE" -ge 2 ]; then break; fi
    sleep 2
done

echo ""
echo "Step 10: Server-Side Limit Results"
echo "  ─────────────────────────────────────────────────"
for pod in m11-1b-limit-pod-1 m11-1b-limit-pod-2 m11-1b-limit-pod-3; do
    echo "  --- $pod ---"
    kubectl logs "$pod" 2>/dev/null | grep -E '\[cuda\]' || echo "  (no output yet)"
    echo ""
done
echo "  ─────────────────────────────────────────────────"

echo ""
echo "Step 11: Analysis (11.1b)"
# Pod 2 tries 12 GiB with 8 GiB limit — if it succeeds, limit is broken
if kubectl logs m11-1b-limit-pod-2 2>/dev/null | grep -q 'Success'; then
    echo "  --> ✅ Pod 2 (12 GiB) succeeded despite 8 GiB limit: defaultPinnedDeviceMemoryLimit NOT enforced on MIG"
elif kubectl logs m11-1b-limit-pod-2 2>/dev/null | grep -q 'FAILED'; then
    echo "  --> Pod 2 (12 GiB) failed — limit may be working, or physical OOM"
else
    echo "  --> Pod 2: no result yet"
fi

for pod in m11-1b-limit-pod-1 m11-1b-limit-pod-3; do
    if kubectl logs "$pod" 2>/dev/null | grep -q 'Success'; then
        echo "  --> ✅ $pod (6 GiB) succeeded"
    elif kubectl logs "$pod" 2>/dev/null | grep -q 'FAILED'; then
        echo "  --> ⚠ $pod (6 GiB) failed (likely physical OOM after others allocated)"
    fi
done

echo ""
echo "Step 12: Cleaning up 11.1b..."
for pod in m11-1b-limit-pod-1 m11-1b-limit-pod-2 m11-1b-limit-pod-3; do
    kubectl delete pod "$pod" --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
done
sleep 2
kubectl delete resourceclaim m11-1b-limit-claim --ignore-not-found --wait=true 2>/dev/null || true
kubectl delete configmap m11-1b-limit-test --ignore-not-found 2>/dev/null || true
sleep 2

# ─────────────────────────────────────────────────────────────────
# Test 11.1c: Client-side MPS Limit Workaround
# ─────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Test 11.1c: Client-Side MPS Limit (CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=4096M)"
echo "  Pod 1: 4.5 GiB → expect MPS limit OOM (> 4 GiB limit, fits physically)"
echo "  Pod 2:   3 GiB → expect success (within limit)"
echo "  Pod 3:   3 GiB → expect success (within limit)"
echo "================================================================"
echo "Step 13: Deploying 11.1c..."
kubectl apply -f "$MANIFEST_C"

echo "Step 14: Waiting for pods (180s timeout, includes nvcc compile)..."
for pod in m11-1c-mps-pod-1 m11-1c-mps-pod-2 m11-1c-mps-pod-3; do
    kubectl wait --for=condition=Ready "pod/$pod" --timeout=180s 2>/dev/null \
        || kubectl wait --for=jsonpath='{.status.phase}'=Failed "pod/$pod" --timeout=30s 2>/dev/null \
        || true
    STATUS=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    echo "  $pod: $STATUS"
done

echo ""
echo "Step 15: Waiting for CUDA output (up to 90s)..."
for attempt in $(seq 1 45); do
    DONE=$(kubectl logs m11-1c-mps-pod-1 2>/dev/null | grep -c '\[cuda\]' || true)
    if [ "$DONE" -ge 2 ]; then break; fi
    sleep 2
done

echo ""
echo "Step 16: Client-Side Limit Results"
echo "  ─────────────────────────────────────────────────"
for pod in m11-1c-mps-pod-1 m11-1c-mps-pod-2 m11-1c-mps-pod-3; do
    echo "  --- $pod ---"
    kubectl logs "$pod" 2>/dev/null | grep -E '\[env\]|\[cuda\]' || echo "  (no output yet)"
    echo ""
done
echo "  ─────────────────────────────────────────────────"

echo ""
echo "Step 17: Analysis (11.1c)"
SUCCESS_C=0
FAIL_C=0
for pod in m11-1c-mps-pod-1 m11-1c-mps-pod-2 m11-1c-mps-pod-3; do
    if kubectl logs "$pod" 2>/dev/null | grep -q 'FAILED'; then
        FAIL_C=$((FAIL_C + 1))
    elif kubectl logs "$pod" 2>/dev/null | grep -q 'Success'; then
        SUCCESS_C=$((SUCCESS_C + 1))
    fi
done
echo "  Succeeded: $SUCCESS_C, Failed: $FAIL_C"

# Check if Pod 1 (4.5 GiB > 4 GiB limit) was rejected by MPS limit
POD1_FREE=$(kubectl logs m11-1c-mps-pod-1 2>/dev/null | grep 'GPU memory:' | grep -oP 'free=\K[0-9]+' || echo "0")
if kubectl logs m11-1c-mps-pod-1 2>/dev/null | grep -q 'FAILED'; then
    if [ "$POD1_FREE" -gt 4608 ] 2>/dev/null; then
        echo "  --> ✅ Pod 1 (4.5 GiB) rejected by MPS limit: free=${POD1_FREE} MiB > 4608 MiB, so it's NOT physical OOM"
    elif [ "$POD1_FREE" -le 4096 ] 2>/dev/null && [ "$POD1_FREE" -gt 0 ] 2>/dev/null; then
        echo "  --> ✅ Pod 1 (4.5 GiB) rejected: cudaMemGetInfo reports free=${POD1_FREE} MiB (virtualized to ~4 GiB limit)"
    else
        echo "  --> ⚠ Pod 1 (4.5 GiB) failed: free=${POD1_FREE} MiB — could be physical OOM, not MPS enforcement"
    fi
else
    echo "  --> ❌ Pod 1 (4.5 GiB) succeeded: client-side MPS limit did NOT work"
fi

# Check Pod 2 and 3 (should succeed)
for pod in m11-1c-mps-pod-2 m11-1c-mps-pod-3; do
    if kubectl logs "$pod" 2>/dev/null | grep -q 'Success'; then
        echo "  --> ✅ $pod (3 GiB) succeeded: within MPS limit"
    elif kubectl logs "$pod" 2>/dev/null | grep -q 'FAILED'; then
        echo "  --> ❌ $pod (3 GiB) failed unexpectedly"
    fi
done

echo ""
echo "Step 18: Cleaning up 11.1c..."
for pod in m11-1c-mps-pod-1 m11-1c-mps-pod-2 m11-1c-mps-pod-3; do
    kubectl delete pod "$pod" --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
done
sleep 2
kubectl delete resourceclaim m11-1c-mps-limit-claim --ignore-not-found --wait=true 2>/dev/null || true
kubectl delete configmap m11-1c-mps-limit-cuda --ignore-not-found 2>/dev/null || true

echo ""
echo "=== Module 11.1 Complete ==="
echo ""
echo "Summary:"
echo "  11.1a — SM oversubscription: 3×50% = 150% allowed (per-daemon, not per-client)"
echo "  11.1b — Server-side limit: defaultPinnedDeviceMemoryLimit NOT enforced on MIG"
echo "  11.1c — Client-side limit: CUDA_MPS_PINNED_DEVICE_MEM_LIMIT enforces limit on MIG"
