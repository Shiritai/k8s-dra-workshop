#!/bin/bash
set -e

echo "=== 🔄 Resetting NVIDIA DRA Driver 🔄 ==="

NAMESPACE="nvidia-system"
LABEL="app.kubernetes.io/name=nvidia-dra-driver-gpu"

echo "Step 1: Deleting Driver Pods..."
kubectl delete pod -n "$NAMESPACE" -l "$LABEL" --force --grace-period=0 --ignore-not-found

echo "Step 2: Waiting for Driver to Restart..."
# Wait for pods to be recreated and running
# Increasing timeout to 300s to be safe
kubectl wait --for=condition=Ready pod -n "$NAMESPACE" -l "$LABEL" --timeout=300s

echo "Step 3: Checking ResourceSlices..."
# Verify driver is actually publishing resources
sleep 5
SLC=$(kubectl get resourceslice --no-headers 2>/dev/null | wc -l)
if [ "$SLC" -gt 0 ]; then
    echo "✅ Success: Driver is up and ResourceSlices are present."
else
    echo "⚠️  Warning: No ResourceSlices found. Driver might need more time or node is unhealthy."
fi
