#!/bin/bash
set -e

NAMESPACE="nvidia-system"
RELEASE_NAME="nvidia-dra-driver"

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "=== NVIDIA DRA Workshop: Driver Installation ==="

# 1. Add Helm Repo
echo "Step 1: Adding NVIDIA Helm repository..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Detect architecture dynamically
ARCH=$(uname -m)
LIB_DIR="x86_64-linux-gnu"
if [ "$ARCH" = "aarch64" ]; then
    LIB_DIR="aarch64-linux-gnu"
fi

# 2. Install Driver
echo "Step 2: Installing NVIDIA DRA Driver (Standard Path Passthrough)..."
# Use local chart from workshop directory
LOCAL_CHART="$WORKSHOP_DIR/nvidia-dra-driver-gpu"

# Generate architecture-specific values file
ARCH_VALUES="values-arch.yaml"

# Detect all existing NVIDIA device nodes (excluding nvidia-caps which is a directory)
DEVICES_YAML=""
for dev in /dev/nvidia*; do
    if [ -c "$dev" ]; then
        DEVICES_YAML+="\n- $dev"
    fi
done

# We mount the host's library directory directly to the container's standard path.
# We also set LD_LIBRARY_PATH to that path inside the container to ensure
# dynamic loading (dlopen) works correctly without requiring ldconfig.
cat > "$ARCH_VALUES" <<EOF
nvidiaDriverLibDir: "/usr/lib/$LIB_DIR"
nvidiaDevices: $(echo -e "$DEVICES_YAML")
kubeletPlugin:
  skipPrestart: $([ "$ARCH" = "aarch64" ] && echo "true" || echo "false")
  containers:
    init:
      env:
      - name: LD_LIBRARY_PATH
        value: "/usr/lib/$LIB_DIR"
    computeDomains:
      env:
      - name: LD_LIBRARY_PATH
        value: "/usr/lib/$LIB_DIR"
    gpus:
      env:
      - name: LD_LIBRARY_PATH
        value: "/usr/lib/$LIB_DIR"
controller:
  containers:
    computeDomain:
      securityContext:
        privileged: true
        readOnlyRootFilesystem: false
      env:
      - name: LD_LIBRARY_PATH
        value: "/usr/lib/$LIB_DIR"
featureGates:
  IMEXDaemonsWithDNSNames: false
EOF

helm upgrade -i "$RELEASE_NAME" "$LOCAL_CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set gpuResourcesEnabledOverride=true \
  --set kubeletPlugin.enabled=true \
  --set image.tag=v25.8.1 \
  -f "$ARCH_VALUES" \
  --wait

rm "$ARCH_VALUES"

echo "✅ Driver installed successfully."

# 3. Verify Components
echo "Step 3: Verifying driver components..."
echo "Waiting for plugin pods to be ready..."
kubectl rollout status daemonset -n "$NAMESPACE" nvidia-dra-driver-gpu-kubelet-plugin --timeout=120s
kubectl get pods -n "$NAMESPACE"
echo "-----------------------------------"
kubectl get ds -n "$NAMESPACE"

# 4. Check ResourceSlice (wait for DRA socket registration with kubelet)
echo "Step 4: Checking ResourceSlice creation..."
echo "Waiting for Node Agent to publish resources..."
for i in $(seq 1 30); do
    SLC_COUNT=$(kubectl get resourceslices --no-headers 2>/dev/null | wc -l)
    if [ "$SLC_COUNT" -gt 0 ]; then
        echo "✅ Success: $SLC_COUNT ResourceSlice(s) found."
        kubectl get resourceslices
        break
    fi
    echo "  Waiting for ResourceSlice... ($i/30)"
    sleep 3
done
if [ "$SLC_COUNT" -eq 0 ]; then
    echo "⚠️ Warning: No ResourceSlices found yet. Please check DaemonSet logs."
fi


# 5. Fix Scheduler RBAC (if needed)
echo "Step 5: Ensuring scheduler has DRA permissions..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: dra-scheduler-fix
rules:
- apiGroups: ["resource.k8s.io"]
  resources: ["deviceclasses", "resourceclaims", "resourceclaims/status", "resourceslices"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: [""]
  resources: ["pods", "pods/finalizers"]
  verbs: ["get", "list", "watch", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dra-scheduler-fix-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: dra-scheduler-fix
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:kube-scheduler
EOF

# 6. Fix MPS RBAC (kubelet plugin needs to manage MPS daemon deployments)
echo "Step 6: Ensuring kubelet plugin has MPS daemon permissions..."
RBAC_FILE="$WORKSHOP_DIR/manifests/module7/fix-driver-rbac.yaml"
if [ -f "$RBAC_FILE" ]; then
    kubectl apply -f "$RBAC_FILE"
else
    # Inline fallback if file not found
    cat <<RBAC_EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nvidia-dra-driver-kubelet-plugin-deployments-role
  namespace: nvidia-system
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nvidia-dra-driver-kubelet-plugin-deployments-binding
  namespace: nvidia-system
subjects:
- kind: ServiceAccount
  name: nvidia-dra-driver-nvidia-dra-driver-gpu-service-account-kubeletplugin
  namespace: nvidia-system
roleRef:
  kind: Role
  name: nvidia-dra-driver-kubelet-plugin-deployments-role
  apiGroup: rbac.authorization.k8s.io
RBAC_EOF
fi

echo "=== Driver Installation Complete! ==="
