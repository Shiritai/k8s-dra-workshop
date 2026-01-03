#!/bin/bash
set -e

echo "=== 🧹 Global Workload Cleanup 🧹 ==="

# Define all known pod names across all modules
PODS="pod-gpu-1 pod-gpu-2 mps-basic mps-limited pod-shared-1 pod-shared-2 admin-pod resilient-pod"
CLAIMS="gpu-claim-1 gpu-claim-2 gpu-claim-basic gpu-claim-basic-v2 gpu-claim-limited gpu-claim-limited-v2 gpu-claim-shared-1 gpu-claim-shared-2 admin-claim resilient-claim"

echo "Step 1: Deleting all potential Pods (Forcefully)..."
# We use xargs to pass multiple args, and silence errors
for pod in $PODS; do
    if kubectl get pod $pod >/dev/null 2>&1; then
        echo "  - Deleting pod/$pod..."
        kubectl delete pod $pod --force --grace-period=0 --ignore-not-found --wait=false 2>/dev/null || true
    fi
done

echo "Step 2: Deleting all potential ResourceClaims..."
for claim in $CLAIMS; do
    if kubectl get resourceclaim $claim >/dev/null 2>&1; then
        echo "  - Deleting resourceclaim/$claim..."
        # Try normal delete first
        kubectl delete resourceclaim $claim --ignore-not-found --wait=false 2>/dev/null || true
    fi
done

echo "Step 3: Waiting for resource termination..."
sleep 2
# Check for stuck items and patch finalizers if needed (Zombie Killer)
STUCK_CLAIMS=$(kubectl get resourceclaims --no-headers 2>/dev/null | awk '{print $1}')
if [ ! -z "$STUCK_CLAIMS" ]; then
    echo "⚠️  Found remaining claims, attempting to remove finalizers for:"
    echo "$STUCK_CLAIMS"
    for claim in $STUCK_CLAIMS; do
         kubectl patch resourceclaim $claim -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
    done
fi

# Double check pods
STUCK_PODS=$(kubectl get pods --no-headers 2>/dev/null | awk '{print $1}')
if [ ! -z "$STUCK_PODS" ]; then
    echo "⚠️  Found lingering pods (likely Terminating):"
    echo "$STUCK_PODS"
    # One last force delete for good measure
    kubectl delete pod --all --force --grace-period=0 2>/dev/null || true
fi

echo "✅ Global Workload Cleanup Complete."
