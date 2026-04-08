#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

TEMPLATE_FILE="$WORKSHOP_DIR/manifests/module1/kind-config.yaml.template"
OUTPUT_FILE="$WORKSHOP_DIR/manifests/module1/kind-config.yaml"

echo "=== Generating Kind Configuration ==="

# Function to resolve symlink to real file
resolve_path() {
    readlink -f "$1"
}

# Detect architecture dynamically
ARCH=$(uname -m)
LIB_DIR="x86_64-linux-gnu"
if [ "$ARCH" = "aarch64" ]; then
    LIB_DIR="aarch64-linux-gnu"
fi

# List of critical libraries/binaries to mount
TARGETS=(
    "/usr/bin/nvidia-smi"
    "/usr/bin/nvidia-ctk"
    "/usr/bin/nvidia-container-runtime"
    "/usr/lib/$LIB_DIR/libnvidia-ml.so.1"
    "/usr/lib/$LIB_DIR/libcuda.so.1"
    "/usr/lib/$LIB_DIR/libnvidia-ptxjitcompiler.so.1"
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
     MOUNTS+="\n  - hostPath: /etc/cdi\n    containerPath: /etc/cdi"
fi

# Also mount device nodes
DEVICES=(
    "/dev/nvidiactl"
    "/dev/nvidia-uvm"
    "/dev/nvidia-uvm-tools"
    "/dev/nvidia-modeset"
)

for dev in "${DEVICES[@]}"; do
    if [ -e "$dev" ]; then
          MOUNTS+="\n  - hostPath: $dev\n    containerPath: $dev"
    fi
done

# Mount all available nvidia GPUs
for dev in /dev/nvidia[0-9]*; do
    if [ -e "$dev" ]; then
          MOUNTS+="\n  - hostPath: $dev\n    containerPath: $dev"
    fi
done

# Mount MIG capabilities (critical for A100)
if [ -d "/dev/nvidia-caps" ]; then
    MOUNTS+="\n  - hostPath: /dev/nvidia-caps\n    containerPath: /dev/nvidia-caps"
fi


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
