#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST_TEMPLATE="$WORKSHOP_DIR/manifests/module8/dcgm-exporter.yaml"

echo "=== Module 8: Observability (DCGM Exporter) ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

# Detect architecture for library paths
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    LIB_DIR="aarch64-linux-gnu"
else
    LIB_DIR="x86_64-linux-gnu"
fi
echo "  Architecture: $ARCH → lib dir: $LIB_DIR"

# 0. Cleanup
echo "Step 0: Cleanup..."
kubectl delete daemonset -n nvidia-system dcgm-exporter --ignore-not-found 2>/dev/null || true
sleep 2

# 1. Deploy DCGM Exporter (with arch-specific paths)
echo "Step 1: Deploying DCGM Exporter..."
sed "s|LIB_ARCH_PLACEHOLDER|$LIB_DIR|g" "$MANIFEST_TEMPLATE" | kubectl apply -f -
echo "Waiting for DCGM Exporter to be Ready..."
kubectl rollout status daemonset -n nvidia-system dcgm-exporter --timeout=120s

# 2. Verify Metrics
echo "Step 2: Verifying Metrics..."
EXPORTER_POD=$(kubectl get pod -n nvidia-system -l app=dcgm-exporter -o jsonpath='{.items[0].metadata.name}')
echo "Exporter Pod: $EXPORTER_POD"

# Forward port 9400
echo "Forwarding port 9400..."
kubectl port-forward -n nvidia-system "$EXPORTER_POD" 9400:9400 &
PF_PID=$!
# Ensure cleanup on exit
trap "kill $PF_PID 2>/dev/null || true" EXIT

# DCGM needs ~30-60s after startup to collect the first batch of metrics.
echo "Waiting for DCGM to warm up..."
sleep 15

# Fetch Metrics
echo "Fetching metrics (with retries)..."
METRICS=""
MAX_RETRIES=20
for ((i=1; i<=MAX_RETRIES; i++)); do
    METRICS=$(curl -s localhost:9400/metrics 2>/dev/null || true)
    if echo "$METRICS" | grep -q "DCGM_FI_DEV_GPU_UTIL"; then
        echo "✅ Found DCGM_FI_DEV_GPU_UTIL on try $i"
        echo "$METRICS" | grep "DCGM_FI_DEV_GPU_UTIL" | head -n 5
        break
    fi
    echo "⚠️ Metric not found on try $i. Waiting 5s..."
    sleep 5
done

if ! echo "$METRICS" | grep -q "DCGM_FI_DEV_GPU_UTIL"; then
    echo "❌ DCGM_FI_DEV_GPU_UTIL not found after $MAX_RETRIES attempts!"
    echo "Full output (first 20 lines):"
    echo "$METRICS" | head -n 20
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

# Cleanup
kill $PF_PID 2>/dev/null || true
trap - EXIT

echo "Step 3: Cleanup..."
kubectl delete daemonset -n nvidia-system dcgm-exporter --ignore-not-found 2>/dev/null || true

echo "=== Module 8 (Observability) Passed! ==="
