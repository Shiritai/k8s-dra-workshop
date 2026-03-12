#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST="$WORKSHOP_DIR/manifests/module9/demo-resilience.yaml"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Module 9: Verifying Resilience (Self-Healing) ===${NC}"
source "$SCRIPT_DIR/check-env.sh"

echo "Step 0: Cleanup..."
# Force delete potential leftovers to ensure Idempotency
kubectl delete pod pod-resilience pod-owner pod-admin --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim claim-resilience claim-owner claim-admin --ignore-not-found
# Ensure driver is ready 
echo "Checking Driver Controller ready..."
kubectl rollout status deployment -n nvidia-system nvidia-dra-driver-gpu-controller --timeout=60s

echo "Step 1: Deploying long-running workload..."
kubectl apply -f "$MANIFEST"

echo "Step 2: Waiting for scheduling..."
kubectl wait --for=condition=Ready pod/pod-resilience --timeout=60s
echo "✅ pod-resilience is Running!"

echo "Step 3: Simulating Driver Crash (Deleting Controller Pod)..."
kubectl delete pod -n nvidia-system -l app.kubernetes.io/name=nvidia-dra-driver-gpu-controller
echo "Controller deleted. Waiting 5s..."
sleep 5

echo "Step 4: Verifying Workload Survival..."
STATUS_AFTER=$(kubectl get pod pod-resilience -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [ "$STATUS_AFTER" == "Running" ]; then
    echo -e "${GREEN}✅ pod-resilience survived the driver restart! (Self-Healing verified)${NC}"
else
    echo -e "❌ pod-resilience failed: $STATUS_AFTER"
    exit 1
fi

echo "Step 5: Waiting for Driver Recovery..."
kubectl rollout status deployment -n nvidia-system nvidia-dra-driver-gpu-controller --timeout=120s
echo -e "${GREEN}✅ Driver recovered.${NC}"

echo -e "${BLUE}=== Module 9 Verification Complete ===${NC}"
