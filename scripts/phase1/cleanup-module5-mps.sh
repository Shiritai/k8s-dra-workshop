#!/bin/bash
set -e

echo "=== Module 5 Cleanup: MPS Advanced ==="

kubectl delete pod mps-limited --ignore-not-found --wait=false
kubectl delete resourceclaim gpu-claim-limited gpu-claim-limited-v2 --ignore-not-found --wait=false

echo "Waiting for resources to terminate..."
kubectl wait --for=delete pod/mps-limited --timeout=30s 2>/dev/null || true

echo "✅ Module 5 Cleaned"
