#!/bin/bash
# Module 4: DRA-Managed MPS Basics
# DRA driver handles MPS daemon — no hostIPC, no hostPath needed.
# For the legacy Host MPS approach, see run-module4-mps-basics.archive.sh.
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST="$WORKSHOP_DIR/manifests/module4/demo-dra-mps-basics.yaml"

echo "=== Module 4: DRA-Managed MPS Basics ==="
source "$SCRIPT_DIR/run-module0-check-env.sh"

# Cleanup
echo "Step 0: Cleaning up previous resources..."
kubectl delete -f "$MANIFEST" --ignore-not-found --wait=true 2>/dev/null || true
sleep 2

echo "Step 1: Verifying MPSSupport feature gate..."
if kubectl get ds -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin -o json 2>/dev/null \
   | grep -q "MPSSupport=true"; then
    echo "  MPSSupport=true confirmed."
else
    echo "  Applying MPSSupport feature gate patch..."
    kubectl patch ds -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin \
        --type strategic -p "$(cat "$WORKSHOP_DIR/manifests/module7/patch-driver-featuregate.yaml")"
    kubectl rollout status ds -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin --timeout=120s
    sleep 5
fi

echo "Step 2: Deploying DRA-MPS workload (2 pods sharing 1 claim)..."
kubectl apply -f "$MANIFEST"

echo "Step 3: Waiting for pods..."
for pod in dra-mps-basic-1 dra-mps-basic-2; do
    if kubectl wait --for=condition=Ready "pod/$pod" --timeout=120s 2>/dev/null; then
        echo "  ✅ $pod is Ready."
    else
        echo "  ❌ $pod failed to start."
        kubectl describe pod "$pod" 2>/dev/null | tail -15
        exit 1
    fi
done

echo "Step 4: Verifying shared GPU device..."
CLAIM_DEVICE=$(kubectl get resourceclaim gpu-claim-dra-mps -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
echo "  Shared claim → $CLAIM_DEVICE"

UUID1=$(kubectl exec dra-mps-basic-1 -- nvidia-smi -L 2>&1 | head -1)
UUID2=$(kubectl exec dra-mps-basic-2 -- nvidia-smi -L 2>&1 | head -1)
echo "  Pod-1: $UUID1"
echo "  Pod-2: $UUID2"

if [ -n "$UUID1" ] && [ "$UUID1" = "$UUID2" ]; then
    echo "  ✅ Both pods share the same GPU device."
else
    echo "  ❌ Pods see different devices."
fi

echo "Step 5: Verifying DRA-injected MPS (CDI)..."
echo "  5a. MPS env var:"
kubectl exec dra-mps-basic-1 -- env 2>&1 | grep "CUDA_MPS" || echo "    (not found)"

echo "  5b. MPS pipe directory:"
kubectl exec dra-mps-basic-1 -- ls -la /tmp/nvidia-mps/ 2>&1 || echo "    (not found)"

echo "  5c. /dev/shm (MPS shared memory):"
kubectl exec dra-mps-basic-1 -- df -h /dev/shm 2>&1 || true

echo "  5d. MPS Control Daemon Deployment:"
kubectl get deploy -n nvidia-system -l app=mps-control-daemon 2>/dev/null || \
    kubectl get deploy -n nvidia-system 2>/dev/null | grep mps || echo "    (no MPS daemon deployment found)"

echo "  5e. Security verification:"
HOST_IPC=$(kubectl get pod dra-mps-basic-1 -o jsonpath='{.spec.hostIPC}')
echo "    hostIPC: ${HOST_IPC:-false} (DRA-managed MPS does not require hostIPC)"

echo "Step 6: Cleanup..."
kubectl delete -f "$MANIFEST" --ignore-not-found --wait=false 2>/dev/null || true

echo "=== Module 4 Complete ==="
