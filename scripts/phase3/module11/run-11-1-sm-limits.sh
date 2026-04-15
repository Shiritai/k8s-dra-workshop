#!/bin/bash
# M11-1: MIG MPS SM Limits
#
# Test 11-1a: Server-side SM limit — 1 shared claim with defaultActiveThreadPercentage=50%,
#             3 pods share 1 MIG device → all see same 50% ceiling (per-daemon, not per-client)
# Test 11-1b: Client-side SM limit — CUDA_MPS_ACTIVE_THREAD_PERCENTAGE = 10/30/50%,
#             3 pods share 1 MIG via 1 claim (daemon ceiling 100%, no server-side limit)

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST_A="$WORKSHOP_DIR/manifests/module11/11-1a-sm-server-side.yaml"
MANIFEST_B="$WORKSHOP_DIR/manifests/module11/11-1b-sm-client-side.yaml"

echo "=== Module 11-1: MIG MPS SM Limits ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

# ─────────────────────────────────────────────────────────────────
# Cleanup: delete ALL known resources by name (old + new naming)
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
# Test 11-1a: Server-Side SM Limit (daemon-level, 1 shared claim)
# ─────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Test 11-1a: Server-Side SM Limit (Daemon-Level)"
echo "  1 shared claim: defaultActiveThreadPercentage = 50%"
echo "  3 pods sharing 1 MIG device via MPS"
echo "  → expect ~equal GFLOPS (daemon ceiling applies to all clients)"
echo "================================================================"
CUDA_DIR="$WORKSHOP_DIR/manifests/module11/cuda"

echo "Step 1: Creating shared ConfigMap and deploying 11-1a..."
kubectl create configmap m11-1-cuda --from-file="$CUDA_DIR/fma_bench.cu" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$MANIFEST_A"

echo "Step 2: Waiting for pods to be Running (180s timeout, includes nvcc compile)..."
ALL_A_OK=true
for pod in m11-1a-pod-1 m11-1a-pod-2 m11-1a-pod-3; do
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
echo "Step 3: Claim allocation (1 shared claim, 1 MIG device)..."
CLAIM_DEV=$(kubectl get resourceclaim m11-1a-claim \
    -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
echo "  m11-1a-claim -> $CLAIM_DEV (shared by 3 pods)"

echo ""
echo "Step 4: Waiting for ALL 3 pods benchmark output (up to 90s)..."
for attempt in $(seq 1 45); do
    DONE=0
    for pod in m11-1a-pod-1 m11-1a-pod-2 m11-1a-pod-3; do
        if kubectl logs "$pod" 2>/dev/null | grep -q '\[bench\] iterations'; then
            DONE=$((DONE + 1))
        fi
    done
    if [ "$DONE" -eq 3 ]; then break; fi
    sleep 2
done

echo ""
echo "Step 5: FMA Benchmark Results (Server-Side SM Limit)"
echo "  ─────────────────────────────────────────────────"
for pod in m11-1a-pod-1 m11-1a-pod-2 m11-1a-pod-3; do
    SM_LINE=$(kubectl logs "$pod" 2>/dev/null | grep '\[cuda\] device:' || true)
    RESULT=$(kubectl logs "$pod" 2>/dev/null | grep '\[bench\] iterations' || echo "(no output)")
    echo "  $pod:"
    echo "    $SM_LINE"
    echo "    $RESULT"
done
echo "  ─────────────────────────────────────────────────"

echo ""
echo "Step 5b: Analysis (11-1a)"
for pod in m11-1a-pod-1 m11-1a-pod-2 m11-1a-pod-3; do
    GFLOPS=$(kubectl logs "$pod" 2>/dev/null | grep '\[bench\] iterations' | grep -oP 'throughput=\K[0-9.]+' || echo "?")
    SMS=$(kubectl logs "$pod" 2>/dev/null | grep '\[cuda\] device:' | grep -oP 'SMs: \K[0-9]+' || echo "?")
    echo "  $pod: SMs=${SMS}, throughput=${GFLOPS} GFLOPS"
done
echo "  Note: All 3 pods share the same MIG device with the same 50% SM ceiling."
echo "  Server-side config (defaultActiveThreadPercentage) is per-daemon, not per-client."
echo "  → Works as a global cap, but cannot differentiate per-pod."

RUNNING_A=$(kubectl get pods --no-headers 2>/dev/null | grep 'm11-1a-pod' | grep -c 'Running' || true)
echo ""
if [ "$RUNNING_A" -eq 3 ]; then
    echo "  --> All 3 pods sharing 1 MIG device with daemon-level 50% SM ceiling"
else
    echo "  --> Only $RUNNING_A/3 pods running"
fi

echo ""
echo "Step 6: Cleaning up 11-1a..."
for pod in m11-1a-pod-1 m11-1a-pod-2 m11-1a-pod-3; do
    kubectl delete pod "$pod" --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
done
sleep 3
kubectl delete resourceclaim m11-1a-claim --ignore-not-found --wait=true 2>/dev/null || true
sleep 2

# ─────────────────────────────────────────────────────────────────
# Test 11-1b: Client-Side SM Limit (CUDA_MPS_ACTIVE_THREAD_PERCENTAGE)
# ─────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Test 11-1b: Client-Side SM Limit"
echo "  Daemon ceiling: 100% (no server-side limit)"
echo "  Pod 1: CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=10 → expect lowest throughput"
echo "  Pod 2: CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=30 → expect ~3x of Pod 1"
echo "  Pod 3: CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=50 → expect highest"
echo "================================================================"
echo "Step 7: Deploying 11-1b (reuses m11-1-cuda ConfigMap)..."
kubectl apply -f "$MANIFEST_B"

echo "Step 8: Waiting for pods to be Running (180s timeout, includes nvcc compile)..."
for pod in m11-1b-pod-1 m11-1b-pod-2 m11-1b-pod-3; do
    if kubectl wait --for=condition=Ready "pod/$pod" --timeout=180s 2>/dev/null; then
        echo "  [+] $pod is Running."
    else
        STATUS=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        echo "  [-] $pod status: $STATUS"
    fi
done

echo ""
echo "Step 9: Claim allocation..."
CLAIM_DEV=$(kubectl get resourceclaim m11-1b-claim \
    -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
echo "  Shared claim device: $CLAIM_DEV"

echo ""
echo "Step 10: Waiting for ALL 3 pods benchmark output (up to 90s)..."
for attempt in $(seq 1 45); do
    DONE=0
    for pod in m11-1b-pod-1 m11-1b-pod-2 m11-1b-pod-3; do
        if kubectl logs "$pod" 2>/dev/null | grep -q '\[bench\] iterations'; then
            DONE=$((DONE + 1))
        fi
    done
    if [ "$DONE" -eq 3 ]; then break; fi
    sleep 2
done

echo ""
echo "Step 11: FMA Benchmark Results (Client-Side SM Limit)"
echo "  ─────────────────────────────────────────────────"
for pod in m11-1b-pod-1 m11-1b-pod-2 m11-1b-pod-3; do
    ENV_LINE=$(kubectl logs "$pod" 2>/dev/null | grep '\[env\]' || true)
    SM_LINE=$(kubectl logs "$pod" 2>/dev/null | grep '\[cuda\] device:' || true)
    RESULT=$(kubectl logs "$pod" 2>/dev/null | grep '\[bench\] iterations' || echo "(no output)")
    echo "  $pod:"
    echo "    $ENV_LINE"
    echo "    $SM_LINE"
    echo "    $RESULT"
done
echo "  ─────────────────────────────────────────────────"

echo ""
echo "Step 12: Analysis (11-1b)"
for pod in m11-1b-pod-1 m11-1b-pod-2 m11-1b-pod-3; do
    PCT=$(kubectl logs "$pod" 2>/dev/null | grep '\[env\]' | grep -oP 'PERCENTAGE=\K[0-9]+' || echo "?")
    GFLOPS=$(kubectl logs "$pod" 2>/dev/null | grep '\[bench\] iterations' | grep -oP 'throughput=\K[0-9.]+' || echo "?")
    SMS=$(kubectl logs "$pod" 2>/dev/null | grep '\[cuda\] device:' | grep -oP 'SMs: \K[0-9]+' || echo "?")
    echo "  $pod: thread%=${PCT}, SMs=${SMS}, throughput=${GFLOPS} GFLOPS"
done

echo ""
echo "Step 13: Cleaning up 11-1b..."
for pod in m11-1b-pod-1 m11-1b-pod-2 m11-1b-pod-3; do
    kubectl delete pod "$pod" --ignore-not-found --grace-period=5 --wait=false 2>/dev/null || true
done
sleep 3
kubectl delete resourceclaim m11-1b-claim --ignore-not-found --wait=true 2>/dev/null || true
kubectl delete configmap m11-1-cuda --ignore-not-found 2>/dev/null || true

echo ""
echo "=== Module 11-1 Complete ==="
echo ""
echo "Summary:"
echo "  11-1a — Server-side SM: daemon-level 50% ceiling on 1 shared claim → all 3 pods see ~equal throughput (per-daemon, not per-client)"
echo "  11-1b — Client-side SM: 10/30/50% via env var on 1 shared claim → proportional throughput per-pod (true per-client control)"
