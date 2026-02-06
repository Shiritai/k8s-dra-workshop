#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST_DIR="$PROJECT_ROOT/manifests/module8"

# Import Phase 1 Environment Check
source "$PROJECT_ROOT/scripts/phase1/run-module0-check-env.sh"

echo "=== Module 7: Admin Access & Observability (Safe Mode) ==="

# 0. Cleanup
echo "Step 0: Cleanup..."
kubectl delete daemonset -n nvidia-system dcgm-exporter 2>/dev/null || true
sleep 2

# 1. Deploy DCGM Exporter
echo "Step 1: Deploying DCGM Exporter..."
kubectl apply -f "$MANIFEST_DIR/dcgm-exporter.yaml"
echo "Waiting for DCGM Exporter to be Ready..."
kubectl rollout status daemonset -n nvidia-system dcgm-exporter

# 2. Verify Metrics (Passive)
echo "Step 2: Verifying Metrics (Passive Check)..."
EXPORTER_POD=$(kubectl get pod -n nvidia-system -l app=dcgm-exporter -o jsonpath='{.items[0].metadata.name}')
echo "Exporter Pod: $EXPORTER_POD"

# Forward port 9400
echo "Forwarding port 9400..."
kubectl port-forward -n nvidia-system "$EXPORTER_POD" 9400:9400 &
PF_PID=$!
sleep 5

# Fetch Metrics
echo "Fetching metrics (with retries)..."
MAX_RETRIES=10
for ((i=1; i<=MAX_RETRIES; i++)); do
    METRICS=$(curl -s localhost:9400/metrics)
    if echo "$METRICS" | grep -q "DCGM_FI_DEV_GPU_UTIL"; then
        echo "✅ Found DCGM_FI_DEV_GPU_UTIL on try $i"
        echo "$METRICS" | grep "DCGM_FI_DEV_GPU_UTIL" | head -n 5
        break
    fi
    echo "⚠️ Metric not found on try $i. Waiting 3s..."
    sleep 3
done

if ! echo "$METRICS" | grep -q "DCGM_FI_DEV_GPU_UTIL"; then
    echo "❌ DCGM_FI_DEV_GPU_UTIL not found after $MAX_RETRIES attempts!"
    echo "Full output (first 20 lines):"
    echo "$METRICS" | head -n 20
    kill $PF_PID
    exit 1
fi

# Cleanup Port Forward
kill $PF_PID

echo "=== Module 7 (Observability) Passed! ==="
