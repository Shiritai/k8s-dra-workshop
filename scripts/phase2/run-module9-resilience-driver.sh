#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST_DIR="$PROJECT_ROOT/manifests/module9"

# Import Phase 1 Environment Check
source "$PROJECT_ROOT/scripts/phase1/run-module0-check-env.sh"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Module 9: Resilience - Driver Failure ===${NC}"

# 0. Cleanup
echo "Step 0: Cleanup..."
kubectl delete pod pod-driver-victim pod-driver-survivor --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim claim-driver-victim claim-driver-survivor 2>/dev/null || true
kubectl apply -f "$MANIFEST_DIR/gpu-class-test.yaml"
sleep 2

# 1. Deploy Workload (Victim)
echo "Step 1: Deploying Workload (Victim)..."
cat <<EOF | kubectl apply -f -
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: claim-driver-victim
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
  name: pod-driver-victim
spec:
  hostIPC: true
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["bash", "-c"]
    args: ["while true; do nvidia-smi -L; sleep 1; done"]
    env:
    - name: CUDA_MPS_PIPE_DIRECTORY
      value: /tmp/nvidia-mps
    volumeMounts:
    - mountPath: /tmp/nvidia-mps
      name: mps-pipe
    resources:
      claims:
      - name: claim-ref-1
  resourceClaims:
  - name: claim-ref-1
    resourceClaimName: claim-driver-victim
  volumes:
  - name: mps-pipe
    hostPath:
      path: /tmp/nvidia-mps
  restartPolicy: Never
EOF

echo "Waiting for pod-driver-victim..."
kubectl wait --for=condition=Ready pod/pod-driver-victim --timeout=60s
echo "✅ Workload is running."

# 2. Restart Driver
echo "Step 2: ⚠️  RESTARTING DRA DRIVER ⚠️"
DRIVER_PODS=$(kubectl get pod -n nvidia-system -l app.kubernetes.io/name=nvidia-dra-driver-gpu -o jsonpath='{.items[*].metadata.name}')
echo "Targets: $DRIVER_PODS"
kubectl delete pod -n nvidia-system $DRIVER_PODS --grace-period=0 --force

echo "Step 3: Verifying Workload Survival..."
sleep 5
# Check if pod is still running and logging
kubectl logs pod-driver-victim --tail=5
STATUS=$(kubectl get pod pod-driver-victim -o jsonpath='{.status.phase}')
if [ "$STATUS" == "Running" ]; then
    echo -e "${GREEN}✅ Workload survived Driver restart!${NC}"
else
    echo -e "❌ Workload failed! Status: $STATUS"
    exit 1
fi

echo "Step 3.5: Deleting Victim Pod to free resources..."
kubectl delete pod pod-driver-victim --force --grace-period=0
kubectl delete resourceclaim claim-driver-victim --force --grace-period=0

echo "Step 4: Waiting for Driver to recover..."
kubectl rollout status daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin
kubectl rollout status deployment -n nvidia-system nvidia-dra-driver-gpu-controller
sleep 10 # Allow registration

# 3. Deploy New Workload (Survivor)
echo "Step 5: Deploying New Workload (Survivor)..."
cat <<EOF | kubectl apply -f -
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: claim-driver-survivor
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
  name: pod-driver-survivor
spec:
  hostIPC: true
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["bash", "-c"]
    args: ["while true; do nvidia-smi -L; sleep 1; done"]
    env:
    - name: CUDA_MPS_PIPE_DIRECTORY
      value: /tmp/nvidia-mps
    volumeMounts:
    - mountPath: /tmp/nvidia-mps
      name: mps-pipe
    resources:
      claims:
      - name: claim-ref-1
  resourceClaims:
  - name: claim-ref-1
    resourceClaimName: claim-driver-survivor
  volumes:
  - name: mps-pipe
    hostPath:
      path: /tmp/nvidia-mps
  restartPolicy: Never
EOF

echo "Waiting for pod-driver-survivor..."
kubectl wait --for=condition=Ready pod/pod-driver-survivor --timeout=60s
kubectl logs pod-driver-survivor

echo -e "${GREEN}=== Module 9 (Driver Failure) Passed! ===${NC}"
