#!/bin/bash
# M10.1: Basic MIG Abstraction
# Case A: Any MIG instance (pure abstraction, no CEL)
# Case B: Profile-based CEL selector (7g.40gb)
# Case C: Profile-based CEL selector (3g.20gb)
# Case D: Profile-based CEL selector (4g.20gb)
#
# Strategy: Run A alone first (validates abstraction), clean up,
# then B+C+D concurrently (each targets a distinct profile).

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST="$WORKSHOP_DIR/manifests/module10/10.1-basic-mig.yaml"

echo "=== NVIDIA DRA Workshop: Module 10.1 — MIG Abstraction ==="

# Cleanup
echo "Step 1: Cleaning up previous resources..."
kubectl delete -f "$MANIFEST" --ignore-not-found --wait=true 2>/dev/null || true
sleep 2

# Helper function
verify_case() {
    local LABEL="$1"
    local CLAIM="$2"
    local POD="$3"
    local EXPECTED_PROFILE="$4"

    echo ""
    echo "━━━ $LABEL ━━━"
    echo "Waiting for claim allocation..."
    for i in $(seq 1 15); do
        DEVICE=$(kubectl get resourceclaim "$CLAIM" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
        if [ -n "$DEVICE" ]; then
            echo "✅ Allocated device: $DEVICE"
            PROFILE=$(kubectl get resourceslices -o json | \
                jq -r ".items[].spec.devices[] | select(.name == \"$DEVICE\") | .attributes.profile.string // \"N/A\"" 2>/dev/null)
            echo "   Profile: $PROFILE"
            if [ -n "$EXPECTED_PROFILE" ] && [ "$PROFILE" != "$EXPECTED_PROFILE" ]; then
                echo "❌ Expected profile $EXPECTED_PROFILE but got $PROFILE"
            fi
            break
        fi
        echo "  Waiting... ($i/15)"
        sleep 3
    done

    echo "Waiting for pod..."
    if kubectl wait --for=condition=Ready pod/"$POD" --timeout=60s 2>/dev/null; then
        echo "✅ $POD is Running."
        kubectl exec "$POD" -- nvidia-smi -L 2>&1 || true
    else
        echo "❌ $POD failed."
        kubectl describe pod "$POD" | tail -5
    fi
}

# ── Phase 1: Case A (Any MIG) ──
echo ""
echo "════ Phase 1: Pure Abstraction (any MIG) ════"
kubectl apply -f - <<'EOF'
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: m10-1a-any-mig-claim
spec:
  devices:
    requests:
    - name: mig-req
      exactly:
        count: 1
        deviceClassName: mig.nvidia.com
---
apiVersion: v1
kind: Pod
metadata:
  name: m10-1a-any-mig-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sh", "-c", "echo '=== Case A: Any MIG ===' && nvidia-smi -L && sleep 3600"]
    resources:
      claims:
      - name: gpus
  resourceClaims:
  - name: gpus
    resourceClaimName: m10-1a-any-mig-claim
  restartPolicy: Never
EOF

verify_case "Case A: Any MIG Instance (No CEL)" "m10-1a-any-mig-claim" "m10-1a-any-mig-pod" ""

echo ""
echo "Cleaning up Case A to free device for Phase 2..."
kubectl delete pod m10-1a-any-mig-pod --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim m10-1a-any-mig-claim --ignore-not-found 2>/dev/null || true
sleep 3

# ── Phase 2: Cases B+C+D (all 3 profiles concurrently) ──
echo ""
echo "════ Phase 2: Profile-Specific Selection (B+C+D concurrent) ════"
# Apply only B, C, D inline to avoid re-creating A from the manifest
kubectl apply -f - <<'EOF'
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: m10-1b-profile-claim
spec:
  devices:
    requests:
    - name: mig-req
      exactly:
        count: 1
        deviceClassName: mig.nvidia.com
        selectors:
        - cel:
            expression: "device.attributes['gpu.nvidia.com'].profile == '7g.40gb'"
---
apiVersion: v1
kind: Pod
metadata:
  name: m10-1b-profile-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sh", "-c", "echo '=== Case B: Profile 7g.40gb ===' && nvidia-smi -L && sleep 3600"]
    resources:
      claims:
      - name: gpus
  resourceClaims:
  - name: gpus
    resourceClaimName: m10-1b-profile-claim
  restartPolicy: Never
---
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: m10-1c-profile-claim
spec:
  devices:
    requests:
    - name: mig-req
      exactly:
        count: 1
        deviceClassName: mig.nvidia.com
        selectors:
        - cel:
            expression: "device.attributes['gpu.nvidia.com'].profile == '3g.20gb'"
---
apiVersion: v1
kind: Pod
metadata:
  name: m10-1c-profile-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sh", "-c", "echo '=== Case C: Profile 3g.20gb ===' && nvidia-smi -L && sleep 3600"]
    resources:
      claims:
      - name: gpus
  resourceClaims:
  - name: gpus
    resourceClaimName: m10-1c-profile-claim
  restartPolicy: Never
---
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: m10-1d-profile-claim
spec:
  devices:
    requests:
    - name: mig-req
      exactly:
        count: 1
        deviceClassName: mig.nvidia.com
        selectors:
        - cel:
            expression: "device.attributes['gpu.nvidia.com'].profile == '4g.20gb'"
---
apiVersion: v1
kind: Pod
metadata:
  name: m10-1d-profile-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sh", "-c", "echo '=== Case D: Profile 4g.20gb ===' && nvidia-smi -L && sleep 3600"]
    resources:
      claims:
      - name: gpus
  resourceClaims:
  - name: gpus
    resourceClaimName: m10-1d-profile-claim
  restartPolicy: Never
EOF

verify_case "Case B: Profile Filter (7g.40gb)" "m10-1b-profile-claim" "m10-1b-profile-pod" "7g.40gb"
verify_case "Case C: Profile Filter (3g.20gb)" "m10-1c-profile-claim" "m10-1c-profile-pod" "3g.20gb"
verify_case "Case D: Profile Filter (4g.20gb)" "m10-1d-profile-claim" "m10-1d-profile-pod" "4g.20gb"

# Summary
echo ""
echo "━━━ Summary ━━━"
echo "Pod Status:"
kubectl get pods --no-headers 2>/dev/null | grep "^m10-1" || true
echo ""
echo "Claim Allocation:"
kubectl get resourceclaims --no-headers 2>/dev/null | grep "^m10-1" || true

# Cleanup
echo ""
echo "Step 3: Cleaning up..."
kubectl delete pod m10-1b-profile-pod m10-1c-profile-pod m10-1d-profile-pod --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim m10-1b-profile-claim m10-1c-profile-claim m10-1d-profile-claim --ignore-not-found 2>/dev/null || true

echo ""
echo "=== Module 10.1 Complete ==="
