#!/bin/bash
# M11.2: MIG MPS VRAM Limits
#
# Test 11-2a: Server-side VRAM limit (defaultPinnedDeviceMemoryLimit: 4Gi)
#             3 Pods (4.5/3/3 GiB) — proves limit is NOT enforced on MIG
# Test 11-2b: Client-side VRAM limit (CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=4096M)
#             No server-side limit — 3 Pods (4.5/3/3 GiB) — enforces limit, virtualizes cudaMemGetInfo

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST_A="$WORKSHOP_DIR/manifests/module11/11-2a-vram-server-side.yaml"
MANIFEST_B="$WORKSHOP_DIR/manifests/module11/11-2b-vram-client-side.yaml"

echo "=== Module 11.2: MIG MPS VRAM Limits ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

# ─────────────────────────────────────────────────────────────────
# Cleanup: delete ALL known resources by name (old AND new)
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

# Wait briefly for pods to terminate, then delete ALL claims
sleep 3

for claim in \
    m11-1a-stress-claim m11-1a-thread-claim m11-1a-claim \
    m11-1a-claim-10 m11-1a-claim-30 m11-1a-claim-50 \
    m11-1b-claim m11-1b-limit-claim m11-1b-mps-limit-claim m11-1c-mps-limit-claim \
    m11-2a-claim m11-2b-claim \
    m11-2a-stress-mig0 m11-2a-stress-mig1 m11-2a-claim-gpu0 m11-2a-claim-gpu1 \
    m11-2b-stress-exclusive m11-2b-stress-mps30 m11-2b-claim-exclusive m11-2b-claim-mps \
    m11-3a-claim-mig0 m11-3a-claim-mig1 \
    m11-3b-claim-exclusive m11-3b-claim-mps30; do
    kubectl delete resourceclaim "$claim" --ignore-not-found --wait=true 2>/dev/null || true
done

for cm in \
    m11-1a-stress-cuda m11-1a-thread-cuda m11-1a-cuda m11-1b-cuda \
    m11-1b-limit-test m11-1b-mps-limit-cuda m11-1c-mps-limit-cuda m11-1b-vram-stress \
    m11-2a-cuda m11-2b-cuda \
    m11-1-cuda m11-2-cuda \
    m11-2a-cuda-stress-src m11-2b-cuda-stress-src m11-3a-cuda m11-3b-cuda; do
    kubectl delete configmap "$cm" --ignore-not-found 2>/dev/null || true
done

sleep 2
echo "  Cleanup done."

# ─────────────────────────────────────────────────────────────────
# Test 11-2a: Server-side VRAM limit (proves bug on MIG)
# ─────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Test 11-2a: Server-Side VRAM (defaultPinnedDeviceMemoryLimit: 4Gi)"
echo "  Pod 1: 4.5 GiB → expect success IF limit broken (over 4 GiB limit)"
echo "  Pod 2:   3 GiB → expect success (under limit)"
echo "  Pod 3:   3 GiB → expect success (under limit)"
echo "  Purpose: Prove defaultPinnedDeviceMemoryLimit is NOT enforced on MIG"
echo "================================================================"
CUDA_DIR="$WORKSHOP_DIR/manifests/module11/cuda"

echo "Step 1: Creating shared ConfigMap and deploying 11-2a..."
kubectl create configmap m11-2-cuda --from-file="$CUDA_DIR/vram_limit.cu" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$MANIFEST_A"

echo "Step 2: Waiting for pods (180s timeout, includes nvcc compile)..."
for pod in m11-2a-pod-1 m11-2a-pod-2 m11-2a-pod-3; do
    kubectl wait --for=condition=Ready "pod/$pod" --timeout=180s 2>/dev/null \
        || kubectl wait --for=jsonpath='{.status.phase}'=Failed "pod/$pod" --timeout=30s 2>/dev/null \
        || true
    STATUS=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    echo "  $pod: $STATUS"
done

echo ""
echo "Step 3: Waiting for CUDA output (up to 90s)..."
for attempt in $(seq 1 45); do
    DONE=$(kubectl logs m11-2a-pod-1 2>/dev/null | grep -c '\[cuda\]' || true)
    if [ "$DONE" -ge 2 ]; then break; fi
    sleep 2
done

echo ""
echo "Step 4: Server-Side VRAM Results"
echo "  ─────────────────────────────────────────────────"
for pod in m11-2a-pod-1 m11-2a-pod-2 m11-2a-pod-3; do
    echo "  --- $pod ---"
    kubectl logs "$pod" 2>/dev/null | grep -E '\[cuda\]' || echo "  (no output yet)"
    echo ""
done
echo "  ─────────────────────────────────────────────────"

echo ""
echo "Step 5: Analysis (11-2a)"
# Pod 1 tries 4.5 GiB with 4 GiB limit — if it succeeds, limit is broken
if kubectl logs m11-2a-pod-1 2>/dev/null | grep -q 'Success'; then
    echo "  --> Pod 1 (4.5 GiB) succeeded despite 4 GiB limit: defaultPinnedDeviceMemoryLimit NOT enforced on MIG"
elif kubectl logs m11-2a-pod-1 2>/dev/null | grep -q 'FAILED'; then
    echo "  --> Pod 1 (4.5 GiB) failed — limit may be working, or physical OOM"
else
    echo "  --> Pod 1: no result yet"
fi

for pod in m11-2a-pod-2 m11-2a-pod-3; do
    if kubectl logs "$pod" 2>/dev/null | grep -q 'Success'; then
        echo "  --> $pod (3 GiB) succeeded"
    elif kubectl logs "$pod" 2>/dev/null | grep -q 'FAILED'; then
        echo "  --> $pod (3 GiB) failed unexpectedly"
    fi
done

echo ""
echo "Step 6: Cleaning up 11-2a..."
for pod in m11-2a-pod-1 m11-2a-pod-2 m11-2a-pod-3; do
    kubectl delete pod "$pod" --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
done
sleep 2
kubectl delete resourceclaim m11-2a-claim --ignore-not-found --wait=true 2>/dev/null || true
sleep 2

# ─────────────────────────────────────────────────────────────────
# Test 11-2b: Client-side VRAM limit workaround
# ─────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Test 11-2b: Client-Side VRAM (CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=4096M)"
echo "  No server-side limit — pure client-side MPS VRAM enforcement"
echo "  Pod 1: 4.5 GiB → expect MPS limit OOM (> 4 GiB limit, fits physically)"
echo "  Pod 2:   3 GiB → expect success (within limit)"
echo "  Pod 3:   3 GiB → expect success (within limit)"
echo "================================================================"
echo "Step 7: Deploying 11-2b (reuses m11-2-cuda ConfigMap)..."
kubectl apply -f "$MANIFEST_B"

echo "Step 8: Waiting for pods (180s timeout, includes nvcc compile)..."
for pod in m11-2b-pod-1 m11-2b-pod-2 m11-2b-pod-3; do
    kubectl wait --for=condition=Ready "pod/$pod" --timeout=180s 2>/dev/null \
        || kubectl wait --for=jsonpath='{.status.phase}'=Failed "pod/$pod" --timeout=30s 2>/dev/null \
        || true
    STATUS=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    echo "  $pod: $STATUS"
done

echo ""
echo "Step 9: Waiting for CUDA output (up to 90s)..."
for attempt in $(seq 1 45); do
    DONE=$(kubectl logs m11-2b-pod-1 2>/dev/null | grep -c '\[cuda\]' || true)
    if [ "$DONE" -ge 2 ]; then break; fi
    sleep 2
done

echo ""
echo "Step 10: Client-Side VRAM Results"
echo "  ─────────────────────────────────────────────────"
for pod in m11-2b-pod-1 m11-2b-pod-2 m11-2b-pod-3; do
    echo "  --- $pod ---"
    kubectl logs "$pod" 2>/dev/null | grep -E '\[env\]|\[cuda\]' || echo "  (no output yet)"
    echo ""
done
echo "  ─────────────────────────────────────────────────"

echo ""
echo "Step 11: Analysis (11-2b)"
SUCCESS_B=0
FAIL_B=0
for pod in m11-2b-pod-1 m11-2b-pod-2 m11-2b-pod-3; do
    if kubectl logs "$pod" 2>/dev/null | grep -q 'FAILED'; then
        FAIL_B=$((FAIL_B + 1))
    elif kubectl logs "$pod" 2>/dev/null | grep -q 'Success'; then
        SUCCESS_B=$((SUCCESS_B + 1))
    fi
done
echo "  Succeeded: $SUCCESS_B, Failed: $FAIL_B"

# Check if Pod 1 (4.5 GiB > 4 GiB limit) was rejected by MPS limit
POD1_FREE=$(kubectl logs m11-2b-pod-1 2>/dev/null | grep 'GPU memory:' | grep -oP 'free=\K[0-9]+' || echo "0")
if kubectl logs m11-2b-pod-1 2>/dev/null | grep -q 'FAILED'; then
    if [ "$POD1_FREE" -le 4096 ] 2>/dev/null && [ "$POD1_FREE" -gt 0 ] 2>/dev/null; then
        echo "  --> Pod 1 (4.5 GiB) rejected: cudaMemGetInfo reports free=${POD1_FREE} MiB (virtualized to ~4 GiB limit)"
    elif [ "$POD1_FREE" -gt 4096 ] 2>/dev/null; then
        echo "  --> Pod 1 (4.5 GiB) rejected by MPS limit: free=${POD1_FREE} MiB > 4096 MiB, so it's NOT physical OOM"
    else
        echo "  --> Pod 1 (4.5 GiB) failed: free=${POD1_FREE} MiB — could be physical OOM, not MPS enforcement"
    fi
else
    echo "  --> Pod 1 (4.5 GiB) succeeded: client-side MPS limit did NOT work"
fi

# Check Pod 2 and 3 (should succeed)
for pod in m11-2b-pod-2 m11-2b-pod-3; do
    if kubectl logs "$pod" 2>/dev/null | grep -q 'Success'; then
        echo "  --> $pod (3 GiB) succeeded: within MPS limit"
    elif kubectl logs "$pod" 2>/dev/null | grep -q 'FAILED'; then
        echo "  --> $pod (3 GiB) failed unexpectedly"
    fi
done

echo ""
echo "Step 12: Cleaning up 11-2b..."
for pod in m11-2b-pod-1 m11-2b-pod-2 m11-2b-pod-3; do
    kubectl delete pod "$pod" --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
done
sleep 2
kubectl delete resourceclaim m11-2b-claim --ignore-not-found --wait=true 2>/dev/null || true
kubectl delete configmap m11-2-cuda --ignore-not-found 2>/dev/null || true

echo ""
echo "=== Module 11.2 Complete ==="
echo ""
echo "Summary:"
echo "  11-2a — Server-side VRAM: 4 GiB limit NOT enforced on MIG (4.5 GiB alloc succeeds)"
echo "  11-2b — Client-side VRAM: 4 GiB limit enforced (4.5 GiB alloc rejected, cudaMemGetInfo virtualized)"
