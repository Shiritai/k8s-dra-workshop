#!/bin/bash
# Master orchestrator: runs all workshop modules (0-9) sequentially.
# Idempotent: safe to re-run. Each module cleans up its own resources before starting.
#
# Adapts to the hardware environment:
#   - Full GPU mode: runs all modules (0-9)
#   - MIG-only mode: skips modules 3-6 (require type=gpu devices)
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

echo "=========================================="
echo "  NVIDIA DRA Workshop: Full Run (M0-M9)"
echo "=========================================="

# ─── Phase 1: Environment & Cluster Setup ───
echo ""
echo "──── Phase 1: Environment & Cluster Setup ────"

"$SCRIPT_DIR/scripts/phase1/run-module0-check-env.sh"

# Module 1: Skip recreation if cluster already exists and is healthy
CLUSTER_NAME="workshop-dra"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$" && \
   kubectl get nodes --context "kind-${CLUSTER_NAME}" &>/dev/null; then
    echo "=== Module 1: Cluster '$CLUSTER_NAME' already exists and is healthy. Skipping. ==="
else
    echo 'y' | "$SCRIPT_DIR/scripts/phase1/run-module1-setup-kind.sh"
fi

# Module 2: Skip if driver is already running and ResourceSlices exist
DRIVER_READY=$(kubectl get pods -n nvidia-system -l app.kubernetes.io/name=nvidia-dra-driver-gpu --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
SLICE_COUNT=$(kubectl get resourceslices --no-headers 2>/dev/null | wc -l)
if [ "$DRIVER_READY" -ge 2 ] && [ "$SLICE_COUNT" -gt 0 ]; then
    echo "=== Module 2: Driver already running ($DRIVER_READY pods, $SLICE_COUNT slices). Skipping. ==="
else
    "$SCRIPT_DIR/scripts/phase1/run-module2-install-driver.sh"
fi

# ─── Detect device types ───
HAS_GPU=$(kubectl get resourceslices -o json 2>/dev/null | \
    jq -r '[.items[].spec.devices[] | select(.attributes.type.string == "gpu")] | length')
HAS_MIG=$(kubectl get resourceslices -o json 2>/dev/null | \
    jq -r '[.items[].spec.devices[] | select(.attributes.type.string == "mig")] | length')

echo ""
echo "──── Environment Detection ────"
echo "  Full GPU devices: $HAS_GPU"
echo "  MIG devices:      $HAS_MIG"

# ─── Phase 1: Workloads ───
echo ""
echo "──── Phase 1: GPU Workload Verification ────"

if [ "$HAS_GPU" -gt 0 ]; then
    "$SCRIPT_DIR/scripts/phase1/run-module3-verify-workload.sh"
    "$SCRIPT_DIR/scripts/phase1/run-module4-mps-basics.sh"
    "$SCRIPT_DIR/scripts/phase1/run-module5-mps-advanced.sh"
    "$SCRIPT_DIR/scripts/phase1/run-module6-vllm-verify.sh"
else
    echo "⚠️  Skipping Modules 3-6: No full GPU devices (MIG-only environment)."
    echo "   Modules 3-6 require deviceClassName: gpu.nvidia.com (type=gpu)."
    echo "   MIG devices are validated in Phase 3 (Modules 10.x)."
fi

# ─── Phase 2: Advanced ───
echo ""
echo "──── Phase 2: Advanced Features ────"

if [ "$HAS_GPU" -gt 0 ]; then
    "$SCRIPT_DIR/scripts/phase2/run-module7-consumable-capacity.sh"
    "$SCRIPT_DIR/scripts/phase2/run-module8-admin-access.sh"
    "$SCRIPT_DIR/scripts/phase2/run-module9-resilience.sh"
else
    echo "⚠️  Skipping Modules 7-9: No full GPU devices (MIG-only environment)."
    echo "   These modules require deviceClassName: gpu.nvidia.com (type=gpu)."
fi

# ─── Phase 3: MIG Experiments ───
echo ""
echo "──── Phase 3: MIG Experiments ────"

if [ "$HAS_MIG" -gt 0 ]; then
    echo ""
    echo "⚠️  Phase 3 requires GPU 0 in MIG mode with 3g.20gb + 4g.20gb."
    echo "   If GPU 0 is not in MIG mode, run: sudo scripts/common/mig-reconfig.sh mig"
    echo ""

    # Refresh DRA plugin registration to prevent stale socket issues (Kind-specific).
    # After many claim create/delete cycles, kubelet's fsnotify loses track of the
    # DRA plugin socket. Must restart kubelet FIRST, then the plugin.
    # See: docs/book/appendix-02-troubleshooting.md "問題 2"
    echo "Refreshing kubelet + DRA plugin registration..."
    CTRL_NODE="workshop-dra-control-plane"
    docker exec "$CTRL_NODE" pkill -f kubelet
    echo "  Waiting for kubelet to restart..."
    sleep 20
    until kubectl get nodes &>/dev/null; do sleep 5; done
    kubectl rollout restart daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin
    kubectl rollout status daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin --timeout=120s
    sleep 5

    "$SCRIPT_DIR/scripts/phase3/module10-1/run.sh"
    "$SCRIPT_DIR/scripts/phase3/module10-2/run.sh"
    "$SCRIPT_DIR/scripts/phase3/module10-3/run.sh"
    "$SCRIPT_DIR/scripts/phase3/module10-4/run.sh"
    "$SCRIPT_DIR/scripts/phase3/module10-5/run.sh"
else
    echo "⚠️  Skipping Phase 3: No MIG devices detected."
    echo "   To enable, run: sudo scripts/common/mig-reconfig.sh mig"
fi

echo ""
echo "=========================================="
echo "  All applicable modules completed."
if [ "$HAS_GPU" -eq 0 ]; then
    echo "  (Modules 3-9 skipped: MIG-only environment)"
fi
echo "=========================================="
