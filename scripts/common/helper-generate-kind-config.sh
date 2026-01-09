#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

TEMPLATE_FILE="$WORKSHOP_DIR/manifests/kind-config.yaml.template"
OUTPUT_FILE="$WORKSHOP_DIR/manifests/kind-config.yaml"

echo "=== Generating Kind Configuration ==="

# Function to resolve symlink to real file
resolve_path() {
    readlink -f "$1"
}

# List of critical libraries/binaries to mount
TARGETS=(
    "/usr/bin/nvidia-smi"
    "/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1"
    "/usr/lib/x86_64-linux-gnu/libcuda.so.1"
    "/usr/lib/x86_64-linux-gnu/libnvidia-ptxjitcompiler.so.1"
    "/usr/bin/nvidia-cuda-mps-control"
    "/usr/bin/nvidia-cuda-mps-server"
)

MOUNTS=""

for target in "${TARGETS[@]}"; do
    if [ -e "$target" ]; then
        # 1. Mount the target path itself (usually a symlink)
        echo "  - Found: $target"
        MOUNTS+="\n  - hostPath: $target\n    containerPath: $target"
        
        # 2. Resolve and mount the REAL file (to fix broken symlinks inside container)
        REAL_PATH=$(resolve_path "$target")
        if [ "$REAL_PATH" != "$target" ]; then
            echo "    -> Resolved to: $REAL_PATH"
            MOUNTS+="\n  - hostPath: $REAL_PATH\n    containerPath: $REAL_PATH"
        fi
    else
        echo "⚠️ Warning: $target not found on host. Node Agent might fail."
    fi
done

# Also mount CDI directory if it exists
if [ -d "/etc/cdi" ]; then
     echo "  - Found /etc/cdi"
     MOUNTS+="\n  - hostPath: /etc/cdi\n    containerPath: /var/run/cdi\n    readOnly: true"
fi

# Also mount device nodes
DEVICES=(
    "/dev/nvidia0"
    "/dev/nvidiactl"
    "/dev/nvidia-uvm"
    "/dev/nvidia-modeset"
)

for dev in "${DEVICES[@]}"; do
    if [ -e "$dev" ]; then
          MOUNTS+="\n  - hostPath: $dev\n    containerPath: $dev"
    fi
done


# Shared Memory (Recommended for IPC)
if [ -d "/dev/shm" ]; then
    echo "  - Found /dev/shm"
    MOUNTS+="\n  - hostPath: /dev/shm\n    containerPath: /dev/shm"
fi

# Escape newlines for sed
ESCAPED_MOUNTS=$(echo -e "$MOUNTS" | sed ':a;N;$!ba;s/\n/\\n/g')

# Generate final config
cp "$TEMPLATE_FILE" "$OUTPUT_FILE"
# Use a perl one-liner for easier multiline replacement or just careful sed
# Here we stick to a simple sed replacement of the placeholder
sed -i "s|{{EXTRA_MOUNTS}}|$ESCAPED_MOUNTS|" "$OUTPUT_FILE"

echo "✅ Generated: $OUTPUT_FILE"
cat "$OUTPUT_FILE" | grep -A 20 "extraMounts"
