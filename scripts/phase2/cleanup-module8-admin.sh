#!/bin/bash
set -e

echo "=== Module 7 Cleanup: Admin Access ==="

kubectl delete pod admin-pod --ignore-not-found --wait=false
kubectl delete resourceclaim admin-claim --ignore-not-found --wait=false

echo "Waiting for resources to terminate..."
kubectl wait --for=delete pod/admin-pod --timeout=30s 2>/dev/null || true

echo "✅ Module 7 Cleaned"
