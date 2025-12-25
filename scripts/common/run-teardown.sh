#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$SCRIPT_DIR")"
CLUSTER_NAME="workshop-dra"

echo "=== NVIDIA DRA Workshop: Teardown ==="

if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "Deleting cluster '$CLUSTER_NAME'..."
    kind delete cluster --name "$CLUSTER_NAME"
    echo "✅ Cluster deleted."
else
    echo "Cluster '$CLUSTER_NAME' not found. Nothing to delete."
fi

# Cleanup generated config
if [ -f "$WORKSHOP_DIR/manifests/kind-config.yaml" ]; then
    rm "$WORKSHOP_DIR/manifests/kind-config.yaml"
    echo "✅ Cleaned up generated config file."
fi

echo "=== Teardown Complete ==="
