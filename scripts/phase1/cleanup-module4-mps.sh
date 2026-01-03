#!/bin/bash
set -e

echo "=== Module 4 Cleanup: MPS Basics ==="

kubectl delete pod mps-basic --ignore-not-found --wait=false
kubectl delete resourceclaim gpu-claim-basic gpu-claim-basic-v2 --ignore-not-found --wait=false

echo "Waiting for resources to terminate..."
kubectl wait --for=delete pod/mps-basic --timeout=30s 2>/dev/null || true

echo "✅ Module 4 Cleaned"
