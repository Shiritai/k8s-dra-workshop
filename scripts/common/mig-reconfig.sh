#!/bin/bash
# MIG Reconfiguration Script
# Switches GPU 0 between non-MIG (for modules 3-9) and MIG (for modules 10.x).
#
# Usage:
#   ./mig-reconfig.sh gpu       # Disable MIG on GPU 0 (modules 3-9)
#   ./mig-reconfig.sh mig       # Enable MIG on GPU 0 with 3g.20gb + 4g.20gb (modules 10.x)
#   ./mig-reconfig.sh status    # Show current MIG status
#
# Prerequisites:
#   - Must be run with sudo/root (or via a wrapper like my-sudo)
#   - GPU 0 must not have active processes (MPS, CUDA apps)
#   - Kind cluster must be running

set -e

MODE="${1:-status}"

CLUSTER_NAME="workshop-dra"

print_status() {
    echo "=== Current MIG Status ==="
    nvidia-smi --query-gpu=index,name,mig.mode.current --format=csv,noheader 2>&1
    echo ""
    echo "=== MIG Devices ==="
    nvidia-smi mig -lgi 2>/dev/null || echo "(no MIG instances or insufficient permissions)"
    echo ""
    echo "=== DRA ResourceSlice Devices ==="
    kubectl get resourceslices -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
for i in d["items"]:
  if i["spec"].get("driver")=="gpu.nvidia.com":
    for dev in i["spec"].get("devices",[]):
      a=dev.get("attributes",{})
      c=dev.get("capacity",{})
      t=a.get("type",{}).get("string","?")
      p=a.get("profile",{}).get("string","N/A")
      sm=c.get("multiprocessors",{}).get("value","?")
      mem=c.get("memory",{}).get("value","?")
      print(f"  {dev[\"name\"]}: type={t}, profile={p}, SM={sm}, mem={mem}")
' 2>/dev/null || echo "(cluster not accessible)"
}

refresh_dra_driver() {
    echo ""
    echo "Refreshing DRA driver to detect new GPU configuration..."

    # Restart kubelet to clear stale DRA plugin registration
    echo "  Restarting kubelet..."
    docker exec "$CLUSTER_NAME-control-plane" pkill -f kubelet 2>/dev/null || true
    sleep 15

    # Wait for API server
    echo "  Waiting for API server..."
    for i in $(seq 1 20); do
        if kubectl get nodes &>/dev/null; then
            break
        fi
        sleep 3
    done

    # Restart DRA plugin pods (must happen AFTER kubelet is up)
    echo "  Restarting DRA plugin..."
    kubectl rollout restart daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin 2>/dev/null
    kubectl rollout status daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin --timeout=120s 2>/dev/null

    # Wait for ResourceSlice
    echo "  Waiting for ResourceSlice..."
    for i in $(seq 1 20); do
        COUNT=$(kubectl get resourceslices -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(sum(1 for i in d["items"] if i["spec"].get("driver")=="gpu.nvidia.com"))
' 2>/dev/null)
        if [ "$COUNT" -gt 0 ]; then
            echo "  ✅ GPU ResourceSlice published."
            return 0
        fi
        sleep 3
    done
    echo "  ⚠️ ResourceSlice not found. May need manual intervention."
    return 1
}

case "$MODE" in
    status)
        print_status
        ;;

    gpu)
        echo "=== Switching GPU 0 to non-MIG mode (for modules 3-9) ==="
        echo ""

        CURRENT=$(nvidia-smi -i 0 --query-gpu=mig.mode.current --format=csv,noheader 2>&1)
        if [ "$CURRENT" = "Disabled" ]; then
            echo "GPU 0 MIG is already Disabled. Nothing to do."
            print_status
            exit 0
        fi

        echo "Step 1: Stopping MPS daemon (if running)..."
        # Kill MPS processes that might be using GPU 0
        pkill -f "nvidia-cuda-mps-server" 2>/dev/null || true
        pkill -f "nvidia-cuda-mps-control" 2>/dev/null || true
        sleep 2

        echo "Step 2: Destroying MIG instances on GPU 0..."
        nvidia-smi mig -i 0 -dci 2>/dev/null || true
        nvidia-smi mig -i 0 -dgi 2>/dev/null || true

        echo "Step 3: Disabling MIG mode on GPU 0..."
        nvidia-smi -i 0 -mig 0

        echo "Step 4: Resetting GPU 0..."
        nvidia-smi -i 0 -r || echo "⚠️ Reset failed. A reboot may be required."

        refresh_dra_driver

        echo ""
        echo "✅ GPU 0 is now in non-MIG mode. Ready for modules 3-9."
        print_status
        ;;

    mig)
        echo "=== Switching GPU 0 to MIG mode (3g.20gb + 4g.20gb) for modules 10.x ==="
        echo ""

        CURRENT=$(nvidia-smi -i 0 --query-gpu=mig.mode.current --format=csv,noheader 2>&1)

        if [ "$CURRENT" = "Disabled" ]; then
            echo "Step 1: Stopping MPS daemon (if running)..."
            pkill -f "nvidia-cuda-mps-server" 2>/dev/null || true
            pkill -f "nvidia-cuda-mps-control" 2>/dev/null || true
            sleep 2

            echo "Step 2: Enabling MIG mode on GPU 0..."
            nvidia-smi -i 0 -mig 1

            echo "Step 3: Resetting GPU 0..."
            nvidia-smi -i 0 -r || echo "⚠️ Reset failed. A reboot may be required."
        else
            echo "GPU 0 MIG is already Enabled. Cleaning existing instances..."
            nvidia-smi mig -i 0 -dci 2>/dev/null || true
            nvidia-smi mig -i 0 -dgi 2>/dev/null || true
        fi

        echo "Step 4: Creating MIG instances (3g.20gb + 4g.20gb)..."
        # Profile IDs for A100-PCIE-40GB (verify with: nvidia-smi mig -lgip):
        #   0  = 7g.40gb
        #   5  = 4g.20gb
        #   9  = 3g.20gb
        #   14 = 2g.10gb
        #   19 = 1g.5gb
        nvidia-smi mig -i 0 -cgi 9,5 -C

        echo "Step 5: Verifying MIG instances..."
        nvidia-smi mig -i 0 -lgi

        refresh_dra_driver

        echo ""
        echo "✅ GPU 0 is now in MIG mode with 3g.20gb + 4g.20gb. Ready for modules 10.x."
        print_status
        ;;

    *)
        echo "Usage: $0 {gpu|mig|status}"
        echo ""
        echo "  gpu     - Disable MIG on GPU 0 (for modules 3-9)"
        echo "  mig     - Enable MIG on GPU 0 with 3g.20gb + 4g.20gb (for modules 10.x)"
        echo "  status  - Show current MIG and DRA status"
        exit 1
        ;;
esac
