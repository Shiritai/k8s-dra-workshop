#!/bin/bash
set -e

echo "=== Module 2 Cleanup: Uninstall NVIDIA DRA Driver ==="

if helm list -n nvidia-system | grep -q nvidia-dra-driver; then
    helm uninstall -n nvidia-system nvidia-dra-driver
    echo "✅ Driver uninstalled."
else
    echo "ℹ️  Driver not found, skipping."
fi

# Wait for pods to terminate
echo "Waiting for driver pods to terminate..."
kubectl wait --for=delete pod -l app.kubernetes.io/name=nvidia-dra-driver-gpu -n nvidia-system --timeout=60s || true

echo "✅ Module 2 Cleaned"
