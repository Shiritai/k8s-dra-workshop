#!/bin/bash
set -e

echo "=== Module 3 Cleanup: Basic Workloads ==="

# Delete Resources
kubectl delete pod pod-gpu-1 pod-gpu-2 --ignore-not-found --wait=false
kubectl delete resourceclaim gpu-claim-1 gpu-claim-2 --ignore-not-found --wait=false

echo "Waiting for resources to terminate..."
kubectl wait --for=delete pod/pod-gpu-1 --timeout=30s 2>/dev/null || true
kubectl wait --for=delete pod/pod-gpu-2 --timeout=30s 2>/dev/null || true

echo "✅ Module 3 Cleaned"
