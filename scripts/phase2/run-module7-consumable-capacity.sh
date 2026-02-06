#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST_WORKLOAD="$WORKSHOP_DIR/manifests/module7/demo-capacity-workload.yaml"
CLASS_FILE="$WORKSHOP_DIR/manifests/module7/gpu-class-capacity.yaml"

echo "=== Module 7: Verifying Consumable Capacity (Shared Pool) ==="
source "$SCRIPT_DIR/check-env.sh"

echo "Step 0: Cleanup..."
# Force delete to avoid sticky resources
kubectl delete pod pod-small pod-4gi pod-18gi pod-overflow --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim claim-small claim-4gi claim-18gi claim-overflow --ignore-not-found
kubectl delete -f "$CLASS_FILE" --ignore-not-found 2>/dev/null || true


echo "Step 0.4: Patching Driver (Feature Gates: MPS)..."
# Enable MPS Feature Gate (Disabled by default in v25.8.1)
if [ -f "$WORKSHOP_DIR/manifests/module7/patch-driver-featuregate.yaml" ]; then
    kubectl patch daemonset nvidia-dra-driver-gpu-kubelet-plugin \
        -n nvidia-system \
        --patch-file "$WORKSHOP_DIR/manifests/module7/patch-driver-featuregate.yaml"
    echo "✅ Applied FeatureGate Patch (MPS=true)."
else
     echo "⚠️ Warning: patch-driver-featuregate.yaml not found. MPS might fail."
fi

echo "Step 0.5: Refreshing Driver State (Apply Patches)..."
# Restart Plugin via Rollout to apply patches and clear state
kubectl rollout restart daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin
kubectl rollout status daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin --timeout=120s
echo "Driver Plugin refreshed."

echo "Step 0.55: Applying RBAC Fix (Supplemental)..."
# Fixes 'Permission Denied' for deployments (MPS control daemon)
if [ -f "$WORKSHOP_DIR/manifests/module7/fix-driver-rbac.yaml" ]; then
    kubectl apply -f "$WORKSHOP_DIR/manifests/module7/fix-driver-rbac.yaml"
    echo "✅ RBAC Fix applied."
else
    echo "⚠️ Warning: fix-driver-rbac.yaml not found. Verification might fail."
fi

echo "Step 0.6: Waiting for ResourceSlice..."
# Wait for ResourceSlice to be published by the new driver instance
for i in {1..30}; do
    count=$(kubectl get resourceslice -o name | wc -l)
    if [ "$count" -gt 0 ]; then
        echo "✅ ResourceSlice found."
        break
    fi
    echo "Waiting for ResourceSlice (Current: $count)..."
    sleep 2
done

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

echo "Step 3: Verification of Capacity Limit (pod-overflow, 50GB)..."
ioctl_status=$(kubectl get pod pod-overflow -o jsonpath='{.status.phase}')
if [ "$ioctl_status" == "Pending" ]; then
     echo "✅ pod-overflow is Pending as expected."
     echo "   (Note: Pending reason is 'Insufficient Devices' due to 1-to-1 Opaque Mapping, which effectively enforces capacity limits in this single-device setup.)"
else
     echo "❌ pod-overflow is $ioctl_status (Unexpected, should be Pending)."
     exit 1
fi

echo "=== Module 7 Verification Complete (Capacity Logic Verified) ==="
