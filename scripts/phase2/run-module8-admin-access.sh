#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST="$WORKSHOP_DIR/manifests/module8/demo-admin-native.yaml"
CLASS_FILE="$WORKSHOP_DIR/manifests/module8/gpu-class-admin.yaml"

echo "=== Module 8: Verifying Admin Access (Native) ==="
source "$SCRIPT_DIR/check-env.sh"

echo "Step 0: Cleanup..."
# Force delete potential leftovers
kubectl delete pod pod-owner pod-admin-native pod-admin --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim claim-owner claim-admin-native claim-admin --ignore-not-found

echo "Step 0.5: Preparing Namespace Security Label..."
# Required for Admin Access in K8s 1.26+ DRA
if kubectl label namespace default resource.kubernetes.io/admin-access=true --overwrite; then
    echo "✅ Namespace labeled for Admin Access."
else
    echo "❌ Failed to label namespace."
    exit 1
fi


echo "Step 1: Check Method 1: User Contention (Verify Baseline)"
# Deploy two exclusive user pods. Pod 1 should run, Pod 2 should pend (on 1-GPU node).
echo "Deploying standard user workloads..."
kubectl apply -f "$WORKSHOP_DIR/manifests/module3/demo-gpu.yaml"

echo "Waiting for pod-gpu-1 (User 1) to be Ready..."
if kubectl wait --for=condition=Ready pod/pod-gpu-1 --timeout=60s; then
    echo "✅ pod-gpu-1 is Running (GPU 0 consumed)."
else
    echo "❌ pod-gpu-1 failed to start."
    exit 1
fi

echo "Verifying pod-gpu-2 (User 2) is Pending..."
sleep 2
STATUS=$(kubectl get pod pod-gpu-2 -o jsonpath='{.status.phase}')
if [ "$STATUS" == "Pending" ]; then
    echo "✅ pod-gpu-2 is Pending (Resource Exhausted as expected)."
else
    echo "⚠️ Warning: pod-gpu-2 is $STATUS. (Do you have >1 GPU?)"
    # Continue anyway, as Admin Access should still work.
fi

echo "Step 2: Check Method 2: Native Admin Access (Override)"
echo "Deploying Admin Pod..."
kubectl apply -f "$CLASS_FILE"
kubectl apply -f "$MANIFEST"

echo "Waiting for Native Admin Pod (pod-admin)..."
# This is the moment of truth: Can it bind despite GPU 0 being "consumed"?
kubectl wait --for=condition=Ready pod/pod-admin --timeout=60s

if kubectl get pod pod-admin | grep -q Running; then
    echo "✅ pod-admin is Running! (Native Admin Access bypassed exclusivity)"
    # Optional: Check if we can see UUIDs inside?
    kubectl exec pod-admin -- nvidia-smi -L
else
    echo "❌ pod-admin failed to start (Native Access check failed)."
    kubectl describe pod pod-admin
    kubectl describe resourceclaim claim-admin
    exit 1
fi

echo "Step 3: Cleanup"
kubectl delete -f "$WORKSHOP_DIR/manifests/module3/demo-gpu.yaml" --force --grace-period=0
kubectl delete -f "$MANIFEST" --force --grace-period=0
kubectl delete resourceclaim claim-admin --ignore-not-found
kubectl delete pod pod-admin --grace-period=0 --ignore-not-found

echo "=== Module 8 Verification Complete ==="
