#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CLASS_FILE="$WORKSHOP_DIR/manifests/module8/gpu-class-admin.yaml"
NS="nvidia-system"
POD_NAME="dcgm-exporter"
# Use unique claim name per run to avoid kubelet stale UID conflicts
CLAIM_NAME="claim-dcgm-$(date +%s)"

echo "=== Module 8: Observability (DCGM via Admin Access) ==="
source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"

# 0. Cleanup previous runs
echo "Step 0: Cleanup..."
# Delete any previous dcgm pods and claims (force to handle Terminating state)
kubectl delete pod -n "$NS" "$POD_NAME" --ignore-not-found --force --grace-period=0 2>/dev/null || true
kubectl delete daemonset -n "$NS" "$POD_NAME" --ignore-not-found 2>/dev/null || true
# Clean all dcgm claims (any previous unique names)
kubectl get resourceclaim -n "$NS" --no-headers -o name 2>/dev/null | grep "claim-dcgm" | \
    xargs -r kubectl delete -n "$NS" --force --grace-period=0 2>/dev/null || true
sleep 3

# 1. Prepare namespace label + DeviceClass for adminAccess
echo "Step 1: Preparing Admin Access prerequisites..."
kubectl label namespace "$NS" resource.kubernetes.io/admin-access=true --overwrite
kubectl apply -f "$CLASS_FILE"

# 2. Deploy DCGM Exporter with adminAccess ResourceClaim (inline manifest)
echo "Step 2: Deploying DCGM Exporter (DRA adminAccess)..."
cat <<EOF | kubectl apply -f -
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: $CLAIM_NAME
  namespace: $NS
spec:
  devices:
    requests:
    - name: monitor-gpu
      exactly:
        deviceClassName: gpu-admin.nvidia.com
        adminAccess: true
---
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: $NS
  labels:
    app: dcgm-exporter
spec:
  containers:
  - name: exporter
    image: nvidia/dcgm-exporter:3.3.5-3.4.0-ubuntu22.04
    env:
    - name: DCGM_EXPORTER_KUBERNETES
      value: "true"
    - name: DCGM_EXPORTER_LISTEN
      value: ":9400"
    securityContext:
      capabilities:
        add: ["SYS_ADMIN"]
    ports:
    - name: metrics
      containerPort: 9400
    resources:
      claims:
      - name: gpu-access
      limits:
        cpu: 200m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi
  resourceClaims:
  - name: gpu-access
    resourceClaimName: $CLAIM_NAME
  restartPolicy: Always
EOF

echo "Waiting for DCGM Exporter Pod to be Ready..."
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NS" --timeout=120s

echo "✅ DCGM Exporter is Running via adminAccess (no privileged, no hostPath)"
kubectl get pod -n "$NS" "$POD_NAME"
kubectl get resourceclaim -n "$NS" "$CLAIM_NAME"

# 3. Verify Metrics
echo "Step 3: Verifying Metrics..."
kubectl port-forward -n "$NS" pod/"$POD_NAME" 9400:9400 &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT

# DCGM needs ~30-60s after startup to collect metrics
echo "Waiting for DCGM to warm up..."
sleep 15

echo "Fetching metrics (with retries)..."
METRICS=""
MAX_RETRIES=20
for ((i=1; i<=MAX_RETRIES; i++)); do
    METRICS=$(curl -s localhost:9400/metrics 2>/dev/null || true)
    if echo "$METRICS" | grep -q "DCGM_FI_DEV_GPU_TEMP"; then
        echo "✅ Found DCGM_FI_DEV_GPU_TEMP on try $i"
        echo "$METRICS" | grep "DCGM_FI_DEV_GPU_TEMP" | head -n 5
        break
    fi
    echo "⚠️ Metric not found on try $i. Waiting 5s..."
    sleep 5
done

if ! echo "$METRICS" | grep -q "DCGM_FI_DEV_GPU_TEMP"; then
    echo "❌ DCGM_FI_DEV_GPU_TEMP not found after $MAX_RETRIES attempts!"
    echo "Full output (first 30 lines):"
    echo "$METRICS" | head -n 30
    echo "--- Pod logs ---"
    kubectl logs -n "$NS" "$POD_NAME" --tail=30 || true
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

# Cleanup
kill $PF_PID 2>/dev/null || true
trap - EXIT

echo "Step 4: Cleanup..."
kubectl delete pod -n "$NS" "$POD_NAME" --ignore-not-found --grace-period=10 2>/dev/null || true
sleep 10
kubectl delete resourceclaim -n "$NS" "$CLAIM_NAME" --ignore-not-found 2>/dev/null || true

echo "=== Module 8 (Observability via Admin Access) Passed! ==="
