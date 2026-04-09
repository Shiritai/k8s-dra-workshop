#!/bin/bash
# Full environment reset: cleans up all workshop resources and refreshes
# the DRA plugin socket, leaving the cluster ready to run any module.
#
# Does NOT destroy the cluster or reinstall the driver.
# For a full teardown, use run-teardown.sh instead.
set -e

CLUSTER_NAME="workshop-dra"
CTRL_NODE="${CLUSTER_NAME}-control-plane"
NAMESPACE="nvidia-system"

echo "=== Workshop Environment Reset ==="

# ── Step 1: Clean user-namespace resources ──
echo ""
echo "Step 1: Cleaning user-namespace resources..."

# Delete all pods that look like workshop workloads (default namespace)
PODS=$(kubectl get pods -o name 2>/dev/null || true)
if [ -n "$PODS" ]; then
    echo "  Deleting pods..."
    kubectl delete pods --all --force --grace-period=0 2>/dev/null || true
fi

# Delete all ResourceClaims
CLAIMS=$(kubectl get resourceclaims -o name 2>/dev/null || true)
if [ -n "$CLAIMS" ]; then
    echo "  Deleting ResourceClaims..."
    kubectl delete resourceclaims --all --ignore-not-found 2>/dev/null || true
fi

# Delete all ResourceClaimTemplates
TEMPLATES=$(kubectl get resourceclaimtemplates -o name 2>/dev/null || true)
if [ -n "$TEMPLATES" ]; then
    echo "  Deleting ResourceClaimTemplates..."
    kubectl delete resourceclaimtemplates --all --ignore-not-found 2>/dev/null || true
fi

# Delete workshop-created DeviceClasses (keep the driver-managed ones)
for dc in gpu-capacity.nvidia.com gpu-admin.nvidia.com; do
    if kubectl get deviceclass "$dc" &>/dev/null; then
        echo "  Deleting DeviceClass $dc..."
        kubectl delete deviceclass "$dc" --ignore-not-found 2>/dev/null || true
    fi
done

# Delete ConfigMaps created by modules (e.g. stress-code from 10.3)
for cm in stress-code; do
    kubectl delete configmap "$cm" --ignore-not-found 2>/dev/null || true
done

echo "  Done."

# ── Step 2: Clear stale checkpoint ──
echo ""
echo "Step 2: Clearing node agent checkpoint..."
docker exec "$CTRL_NODE" rm -f /var/lib/kubelet/plugins/gpu.nvidia.com/checkpoint.json 2>/dev/null || true
echo "  Done."

# ── Step 3: Refresh kubelet + DRA plugin (fix socket staleness) ──
echo ""
echo "Step 3: Refreshing kubelet + DRA plugin..."

echo "  Restarting kubelet..."
# Use pkill -x (exact match) instead of pkill -f to avoid killing
# kube-apiserver, gpu-kubelet-plugin, etc. whose cmdline contains "kubelet".
docker exec "$CTRL_NODE" pkill -x kubelet

echo "  Waiting for API server..."
sleep 20
for i in $(seq 1 20); do
    if kubectl get nodes &>/dev/null; then
        break
    fi
    sleep 5
done

echo "  Waiting for nvidia-system namespace..."
for i in $(seq 1 30); do
    if kubectl get ns "$NAMESPACE" &>/dev/null && \
       kubectl get daemonset -n "$NAMESPACE" nvidia-dra-driver-gpu-kubelet-plugin &>/dev/null; then
        break
    fi
    sleep 3
done

echo "  Restarting DRA plugin..."
kubectl rollout restart daemonset -n "$NAMESPACE" nvidia-dra-driver-gpu-kubelet-plugin
kubectl rollout status daemonset -n "$NAMESPACE" nvidia-dra-driver-gpu-kubelet-plugin --timeout=120s

# ── Step 4: Verify ResourceSlice ──
echo ""
echo "Step 4: Verifying ResourceSlice..."
sleep 5
for i in $(seq 1 15); do
    SLICE_COUNT=$(kubectl get resourceslices --no-headers 2>/dev/null | wc -l)
    if [ "$SLICE_COUNT" -gt 0 ]; then
        echo "  ResourceSlices: $SLICE_COUNT"

        # Show available devices
        kubectl get resourceslices -o json 2>/dev/null | \
            jq -r '.items[].spec.devices[] | "\(.name)  type=\(.attributes.type.string)  profile=\(.attributes.profile.string // "N/A")"' 2>/dev/null | \
            sed 's/^/    /'
        break
    fi
    sleep 3
done

if [ "$SLICE_COUNT" -eq 0 ]; then
    echo "  ⚠️  No ResourceSlices found. Driver may need manual intervention."
    exit 1
fi

# ── Summary ──
echo ""
echo "=== Environment Reset Complete ==="
echo "  Pods:              $(kubectl get pods --no-headers 2>/dev/null | wc -l)"
echo "  ResourceClaims:    $(kubectl get resourceclaims --no-headers 2>/dev/null | wc -l)"
echo "  ResourceSlices:    $SLICE_COUNT"
echo ""
echo "Ready to run any module."
