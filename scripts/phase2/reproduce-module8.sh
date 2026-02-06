#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "=== Reproduce Module 8 Results (End-to-End & Robust) ==="
echo "Logs will be available in the terminal."

# 0. Robust Cleanup (Force clear Module 7 residuals)
echo ">>> Step 0: Ensuring Clean Environment (Force Cleanup)..."
kubectl delete pod pod-small pod-4gi pod-overflow pod-18gi pod-admin dcgm-exporter --ignore-not-found --grace-period=0 --force &>/dev/null || true
kubectl delete resourceclaim claim-small claim-4gi claim-18gi claim-overflow claim-admin --ignore-not-found &>/dev/null || true
kubectl delete deviceclass gpu-capacity.nvidia.com gpu-admin.nvidia.com --ignore-not-found &>/dev/null || true

# Wait for cleanup to settle
echo "Waiting for resources to terminate..."
sleep 5

# 0.5 Full Driver Re-install (Nuclear Option for Robustness)
echo ">>> Step 0.5: Re-installing Driver to ensure clean state..."
if helm list -n nvidia-system | grep -q nvidia-dra-driver; then
    helm uninstall -n nvidia-system nvidia-dra-driver
    echo "Waiting for driver to terminate..."
    kubectl wait --for=delete pod -l app.kubernetes.io/instance=nvidia-dra-driver -n nvidia-system --timeout=60s || true
fi

# Re-install Driver
"$WORKSHOP_DIR/scripts/phase1/run-module2-install-driver.sh"

# Note: Restart Kubelet to ensure it picks up the new plugin socket immediately
echo "Force restarting Kubelet to register new driver..."
docker exec workshop-dra-control-plane systemctl restart kubelet
echo "Waiting for Kubelet to stabilize..."
sleep 15

# 1. Verification: Admin Access
echo ">>> Step 1: Running Module 8 - Admin Access Verification..."
"$WORKSHOP_DIR/scripts/phase2/run-module8-admin-access.sh"

# 2. Verification: Observability
echo ">>> Step 2: Running Module 8 - Observability Verification..."
"$WORKSHOP_DIR/scripts/phase2/run-module8-observability.sh"

echo "=== Module 8 Reproduction Complete ==="
