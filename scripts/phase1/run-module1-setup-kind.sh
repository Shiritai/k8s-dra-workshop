#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "=== NVIDIA DRA Workshop: Cluster Setup ==="

# 1. Generate Config
echo "Step 1: Generating dynamic Kind configuration..."
"$SCRIPT_DIR/../common/helper-generate-kind-config.sh"

# 2. Check if cluster exists
CLUSTER_NAME="workshop-dra"
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "⚠️ Cluster '$CLUSTER_NAME' already exists."
    read -p "Do you want to delete it and recreate? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kind delete cluster --name "$CLUSTER_NAME"
    else
        echo "Skipping creation."
        exit 0
    fi
fi

# 3. Create Cluster
echo "Step 2: Creating Kind cluster '$CLUSTER_NAME'..."
kind create cluster --config "$WORKSHOP_DIR/manifests/kind-config.yaml" --name "$CLUSTER_NAME"

# 4. Verify GPU visibility in node
if docker exec "${CLUSTER_NAME}-control-plane" nvidia-smi &> /dev/null; then
    echo "✅ Success: nvidia-smi is accessible inside the Kind node."
else
    echo "❌ Fail: nvidia-smi failed inside the node. Check mounts."
    exit 1
fi

# 5. Start In-Cluster MPS Daemon
echo "Step 4: Starting In-Cluster MPS Daemon..."
# Start daemon in background (-d)
docker exec "${CLUSTER_NAME}-control-plane" nvidia-cuda-mps-control -d

# Verify
if docker exec "${CLUSTER_NAME}-control-plane" ps aux | grep -q "nvidia-cuda-mps-control"; then
    echo "✅ Success: In-Cluster MPS Daemon started."
else
    echo "❌ Fail: Failed to start MPS Daemon."
    exit 1
fi

echo "=== Cluster Setup Complete! ==="
echo "You can now proceed to install the driver."
