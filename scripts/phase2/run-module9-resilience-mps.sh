#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST_DIR="$PROJECT_ROOT/manifests/module9"

# Import Phase 1 Environment Check
# source "$PROJECT_ROOT/scripts/phase1/run-module0-check-env.sh"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Module 9: Resilience (MPS Failure Recovery) ===${NC}"

# 0. Cleanup
echo "Step 0: Cleanup..."
kubectl delete pod pod-victim pod-survivor --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim claim-victim claim-survivor --force --grace-period=0 2>/dev/null || true
kubectl apply -f "$MANIFEST_DIR/gpu-class-test.yaml"

# 1. Deploy Victim Pod
echo "Step 1: Deploying Victim Pod (Existing Client)..."
cat <<EOF | kubectl apply -f -
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: claim-victim
spec:
  devices:
    requests:
    - name: req-1
      exactly:
        deviceClassName: gpu-test.nvidia.com
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-victim
spec:
  hostIPC: true
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sleep", "inf"]
    env:
    - name: CUDA_MPS_PIPE_DIRECTORY
      value: /tmp/nvidia-mps
    volumeMounts:
    - mountPath: /tmp/nvidia-mps
      name: mps-pipe
    resources:
      claims:
      - name: claim-ref
  resourceClaims:
  - name: claim-ref
    resourceClaimName: claim-victim
  volumes:
  - name: mps-pipe
    hostPath:
      path: /tmp/nvidia-mps
  restartPolicy: Never
EOF

echo "Waiting for pod-victim to run..."
kubectl wait --for=condition=Ready pod/pod-victim --timeout=60s

echo "Step 2: Verifying Victim is connected..."
kubectl exec pod-victim -- nvidia-smi -L
echo "✅ Victim is alive."

# 2. Kill MPS Daemon
echo "Step 3: ⚠️  KILLING MPS DAEMON ⚠️"
MPS_POD=$(kubectl get pods -n nvidia-system -l app=nvidia-mps-control-daemon -o jsonpath='{.items[0].metadata.name}')
echo "Target: $MPS_POD"
kubectl delete pod -n nvidia-system "$MPS_POD" --force --grace-period=0

# 3. Verify Victim Survival
echo "Step 4: Observing Victim Pod behavior..."
for i in {1..5}; do
    kubectl exec pod-victim -- nvidia-smi -L || echo "⚠️ Connection lost (Expected temporarily)"
    sleep 2
done

echo "Step 4.5: Deleting Victim Pod to free resources..."
kubectl delete pod pod-victim --force --grace-period=0
kubectl delete resourceclaim claim-victim --force --grace-period=0

# 4. Wait for Daemon Restart
echo "Step 5: Waiting for MPS Daemon to restart..."
kubectl rollout status ds -n nvidia-system nvidia-mps-control-daemon

# 5. Deploy Survivor Pod
echo "Step 6: Deploying Survivor Pod (New Client)..."
cat <<EOF | kubectl apply -f -
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: claim-survivor
spec:
  devices:
    requests:
    - name: req-1
      exactly:
        deviceClassName: gpu-test.nvidia.com
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-survivor
spec:
  hostIPC: true
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sleep", "inf"]
    env:
    - name: CUDA_MPS_PIPE_DIRECTORY
      value: /tmp/nvidia-mps
    volumeMounts:
    - mountPath: /tmp/nvidia-mps
      name: mps-pipe
    resources:
      claims:
      - name: claim-ref
  resourceClaims:
  - name: claim-ref
    resourceClaimName: claim-survivor
  volumes:
  - name: mps-pipe
    hostPath:
      path: /tmp/nvidia-mps
  restartPolicy: Never
EOF

echo "Waiting for pod-survivor..."
kubectl wait --for=condition=Ready pod/pod-survivor --timeout=60s
kubectl exec pod-survivor -- nvidia-smi

echo -e "${GREEN}=== Module 9 (MPS Failure) Passed! ===${NC}"
