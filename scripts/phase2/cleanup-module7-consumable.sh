#!/bin/bash
set -e

echo "=== Module 6 Cleanup: Consumable Capacity ==="

# Delete all potential pods from this module
kubectl delete pod pod-shared-1 pod-shared-2 --ignore-not-found --wait=false
kubectl delete resourceclaim gpu-claim-shared-1 gpu-claim-shared-2 --ignore-not-found --wait=false

echo "Waiting for resources to terminate..."
kubectl wait --for=delete pod/pod-shared-1 --timeout=30s 2>/dev/null || true
kubectl wait --for=delete pod/pod-shared-2 --timeout=30s 2>/dev/null || true

echo "✅ Module 6 Cleaned"
