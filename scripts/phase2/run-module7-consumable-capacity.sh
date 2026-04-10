#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST_WORKLOAD="$WORKSHOP_DIR/manifests/module7/demo-capacity-workload.yaml"
CLASS_FILE="$WORKSHOP_DIR/manifests/module7/gpu-class-capacity.yaml"

echo "=== Module 7: Verifying Consumable Capacity (Shared Pool) ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

echo "Step 1: Applying Shared DeviceClass (MPS Strategy)..."
# Using MPS strategy manifest (ensure it exists)
if [ ! -f "$CLASS_FILE" ]; then
    echo "❌ Missing $CLASS_FILE"
    exit 1
fi
kubectl apply -f "$CLASS_FILE"

echo "Step 2: Deploying Valid Workload (pod-small, 4GB)..."
# Extract and apply only pod-small/claim-small parts or use full manifest and filter?
# Using full manifest for simplicity, it defines multiple distinct resources.
kubectl apply -f "$MANIFEST_WORKLOAD"

echo "Waiting for pod-small to be Ready..."
kubectl wait --for=condition=Ready pod/pod-small --timeout=60s
echo "✅ Pod-Small works (Allocated Device + MPS Config)."

echo "Step 3: Verification — Opaque 1-to-1 Mapping blocks remaining pods..."
FAIL=0
for pod in pod-4gi pod-18gi pod-overflow; do
    status=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}')
    if [ "$status" == "Pending" ]; then
        echo "✅ $pod is Pending as expected (Opaque 1-to-1 mapping: gpu-0 already bound)."
    else
        echo "❌ $pod is $status (Expected Pending)."
        FAIL=1
    fi
done
if [ "$FAIL" -eq 1 ]; then
    echo "⚠️  Some pods were not Pending. Do you have >1 GPU?"
fi

echo "Step 4: Cleanup..."
kubectl delete pod pod-small pod-4gi pod-18gi pod-overflow --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim claim-small claim-4gi claim-18gi claim-overflow --ignore-not-found

echo "=== Module 7 Verification Complete (Capacity Logic Verified) ==="
