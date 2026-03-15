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
kind create cluster --config "$WORKSHOP_DIR/manifests/module1/kind-config.yaml" --name "$CLUSTER_NAME"

# 4. Configure ldconfig inside node so nvidia-smi can find libraries
echo "Step 3: Configuring ldconfig inside node for AArch64/x86_64 compatibility..."
ARCH=$(uname -m)
LIB_DIR="x86_64-linux-gnu"
if [ "$ARCH" = "aarch64" ]; then
    LIB_DIR="aarch64-linux-gnu"
fi
docker exec "${CLUSTER_NAME}-control-plane" bash -c "mkdir -p /etc/ld.so.conf.d && echo '/usr/lib/$LIB_DIR' > /etc/ld.so.conf.d/nvidia.conf && ldconfig"

# 5. Verify GPU visibility in node
# Note: In some virtualized/nested environments, nvidia-smi might return exit code 14 
# due to "infoROM is corrupted", but still output valid GPU info.
# We wrap it in a command group or use '|| true' to prevent 'set -e' from killing the script.
NVIDIA_SMI_STATUS=0
docker exec "${CLUSTER_NAME}-control-plane" nvidia-smi > nvidia_smi_out.tmp 2>&1 || NVIDIA_SMI_STATUS=$?

if [ $NVIDIA_SMI_STATUS -eq 0 ] || [ $NVIDIA_SMI_STATUS -eq 14 ]; then
    echo "✅ Success: nvidia-smi is accessible (Status: $NVIDIA_SMI_STATUS) inside the Kind node."
    cat nvidia_smi_out.tmp
else
    echo "❌ Fail: nvidia-smi failed inside the node with status $NVIDIA_SMI_STATUS. Check mounts."
    cat nvidia_smi_out.tmp
    exit 1
fi
rm nvidia_smi_out.tmp

# 6. Start In-Cluster MPS Daemon
echo "Step 4: Starting In-Cluster MPS Daemon..."
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
