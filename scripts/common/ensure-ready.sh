#!/bin/bash
# Common helper sourced by every module to ensure DRA environment is ready.
# Usage: source "$WORKSHOP_DIR/scripts/common/ensure-ready.sh"
#
# What it does:
#   1. Verifies driver pods are running
#   2. Cleans stale checkpoint if present
#   3. Ensures MPSSupport feature gate is enabled
#   4. Ensures MPS RBAC is applied
#   5. Cleans workshop-created DeviceClasses from other modules
#   6. Cleans all leftover pods/claims in default namespace
#   7. Waits for ResourceSlice to exist
#
# Requires WORKSHOP_DIR to be set before sourcing.

_ensure_ready() {
    local NS="nvidia-system"
    local DS="nvidia-dra-driver-gpu-kubelet-plugin"
    local CTRL_NODE="workshop-dra-control-plane"

    echo ">>> Ensuring DRA environment is ready..."

    # 1. Check driver is running
    if ! kubectl get pods -n "$NS" -l app.kubernetes.io/name=nvidia-dra-driver-gpu \
         --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -q .; then
        echo "❌ DRA driver is not running. Run module 1 + 2 first."
        return 1
    fi

    # 2. Ensure MPSSupport feature gate
    if ! kubectl get ds -n "$NS" "$DS" -o json 2>/dev/null | grep -q "MPSSupport=true"; then
        echo "  Enabling MPSSupport feature gate..."
        if [ -f "$WORKSHOP_DIR/manifests/module7/patch-driver-featuregate.yaml" ]; then
            kubectl patch ds -n "$NS" "$DS" \
                --type strategic -p "$(cat "$WORKSHOP_DIR/manifests/module7/patch-driver-featuregate.yaml")" 2>/dev/null || true
            kubectl rollout status ds -n "$NS" "$DS" --timeout=120s 2>/dev/null
            sleep 3
        fi
    fi

    # 4. Ensure MPS RBAC
    if [ -f "$WORKSHOP_DIR/manifests/module7/fix-driver-rbac.yaml" ]; then
        kubectl apply -f "$WORKSHOP_DIR/manifests/module7/fix-driver-rbac.yaml" 2>/dev/null || true
    fi

    # 5. Clean workshop-created DeviceClasses (leave driver-managed ones)
    for dc in gpu-capacity.nvidia.com gpu-admin.nvidia.com; do
        kubectl delete deviceclass "$dc" --ignore-not-found 2>/dev/null || true
    done

    # 6. Clean leftover pods and claims in default namespace
    local PODS=$(kubectl get pods --no-headers -o name 2>/dev/null || true)
    if [ -n "$PODS" ]; then
        echo "  Cleaning leftover pods..."
        kubectl delete pods --all --force --grace-period=0 2>/dev/null || true
        sleep 2
    fi

    local CLAIMS=$(kubectl get resourceclaims --no-headers -o name 2>/dev/null || true)
    if [ -n "$CLAIMS" ]; then
        echo "  Cleaning leftover claims..."
        kubectl delete resourceclaims --all --ignore-not-found 2>/dev/null || true
        sleep 2
    fi

    # Also clean MPS daemon deployments that may be stale
    local MPS_DEPLOYS=$(kubectl get deploy -n "$NS" --no-headers -o name 2>/dev/null | grep mps-control-daemon || true)
    if [ -n "$MPS_DEPLOYS" ]; then
        echo "  Cleaning stale MPS daemon deployments..."
        echo "$MPS_DEPLOYS" | xargs kubectl delete -n "$NS" --ignore-not-found 2>/dev/null || true
        sleep 2
    fi

    # 7. Wait for ResourceSlice
    local found=0
    for i in $(seq 1 15); do
        local count=$(kubectl get resourceslices --no-headers 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            found=1
            break
        fi
        sleep 3
    done
    if [ "$found" -eq 0 ]; then
        echo "  ⚠️  No ResourceSlices. Restarting plugin..."
        kubectl rollout restart ds -n "$NS" "$DS" 2>/dev/null
        kubectl rollout status ds -n "$NS" "$DS" --timeout=120s 2>/dev/null
        sleep 5
    fi

    echo ">>> Environment ready."
}

_ensure_ready
