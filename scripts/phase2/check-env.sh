#!/bin/bash

# Helper function to check environment readiness for Phase 2 modules
# Usage: source check-env.sh

check_dra_driver() {
    echo ">>> Checking NVIDIA DRA Driver status..."
    if kubectl get pods -n nvidia-system -l app.kubernetes.io/name=nvidia-dra-driver-gpu | grep -q "Running"; then
        echo "✅ Driver is running."
    else
        echo "❌ Driver is NOT running. Please run 'scripts/phase1/run-module1-setup-kind.sh' and 'scripts/phase1/run-module2-install-driver.sh' first."
        exit 1
    fi
}

cleanup_stale_resources() {
    echo ">>> Checking for stale resources (Prevention of 'old ResourceClaim' error)..."
    
    # Check for any claims/pods related to the workshop
    STALE_PODS=$(kubectl get pods -l app=workshop-dra -o name 2>/dev/null)
    STALE_CLAIMS=$(kubectl get resourceclaims -o name 2>/dev/null | grep "gpu-" || true)

    if [ -n "$STALE_PODS" ] || [ -n "$STALE_CLAIMS" ]; then
        echo "⚠️ Found stale resources. Cleaning up aggressively to ensure clean state..."
        
        # Delete Pods first
        if [ -n "$STALE_PODS" ]; then
             kubectl delete pod --all --force --grace-period=0 2>/dev/null
             echo "   - Deleted all pods."
        fi
        
        # Delete Claims
        if [ -n "$STALE_CLAIMS" ]; then
             kubectl delete resourceclaims --all --force --grace-period=0 2>/dev/null
             echo "   - Deleted all claims."
        fi
        
        # Optional: Wait a bit for Kubelet GC
        echo "   - Waiting 5s for Kubelet state sync..."
        sleep 5
    else
        echo "✅ Environment is clean."
    fi
}

# Main check routine
check_dra_driver
cleanup_stale_resources
