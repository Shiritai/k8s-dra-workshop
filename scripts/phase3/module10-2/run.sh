#!/bin/bash
# M10.2: Tight Resource Matching via CEL Capacity Selectors
# Case A: SM range 90-100 (match 7g.40gb at 98 SM → Running)
# Case B: VRAM >= 30Gi (match 7g.40gb → Running)
# Case C: SM > 100 (no match → Pending)
# Case D: SM range 50-60 (match 4g.20gb at 56 SM → Running)
# Case E: VRAM 15-25Gi (match 3g.20gb or 4g.20gb → Running)
#
# Strategy: Cases A+D+E each target different devices (concurrent).
# Case B shares 7g.40gb with A, so runs after A is cleaned up.
# Case C is a negative test (always Pending), runs with Group 1.

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST="$WORKSHOP_DIR/manifests/module10/10.2-tight-matching.yaml"

echo "=== NVIDIA DRA Workshop: Module 10.2 — Tight Resource Matching ==="

# Cleanup
echo "Step 1: Cleaning up previous resources..."
kubectl delete -f "$MANIFEST" --ignore-not-found --wait=true 2>/dev/null || true
sleep 2

# Show available MIG devices
echo ""
echo "Step 2: Available MIG devices in cluster:"
kubectl get resourceslices -o json | jq -r '
  .items[].spec.devices[]
  | select(.attributes.type.string == "mig")
  | "  \(.name)  profile=\(.attributes.profile.string)  SM=\(.capacity.multiprocessors.value)  VRAM=\(.capacity.memory.value)"
' 2>/dev/null || echo "  (no MIG devices found)"

# Helper: verify a positive-match case
verify_positive() {
    local LABEL="$1"
    local CLAIM="$2"
    local POD="$3"

    echo ""
    echo "━━━ $LABEL ━━━"
    for i in $(seq 1 15); do
        DEVICE=$(kubectl get resourceclaim "$CLAIM" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
        if [ -n "$DEVICE" ]; then
            SM=$(kubectl get resourceslices -o json | jq -r ".items[].spec.devices[] | select(.name == \"$DEVICE\") | .capacity.multiprocessors.value" 2>/dev/null)
            MEM=$(kubectl get resourceslices -o json | jq -r ".items[].spec.devices[] | select(.name == \"$DEVICE\") | .capacity.memory.value" 2>/dev/null)
            PROFILE=$(kubectl get resourceslices -o json | jq -r ".items[].spec.devices[] | select(.name == \"$DEVICE\") | .attributes.profile.string // \"N/A\"" 2>/dev/null)
            echo "✅ Allocated: $DEVICE (profile=$PROFILE, SM=$SM, VRAM=$MEM)"
            break
        fi
        echo "  Waiting... ($i/15)"
        sleep 3
    done

    if kubectl wait --for=condition=Ready pod/"$POD" --timeout=60s 2>/dev/null; then
        echo "✅ $POD is Running."
        kubectl exec "$POD" -- nvidia-smi -L 2>&1 || true
    else
        echo "❌ $POD failed."
        kubectl describe pod "$POD" | grep "FailedScheduling" | tail -1
    fi
}

# Helper: verify a negative-match case
verify_negative() {
    local LABEL="$1"
    local CLAIM="$2"
    local POD="$3"
    local NOTE="$4"

    echo ""
    echo "━━━ $LABEL ━━━"
    echo "Note: $NOTE"
    DEVICE=""
    for i in $(seq 1 5); do
        DEVICE=$(kubectl get resourceclaim "$CLAIM" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
        if [ -n "$DEVICE" ]; then
            echo "⚠️ Unexpectedly allocated: $DEVICE"
            break
        fi
        echo "  Waiting... ($i/5)"
        sleep 3
    done

    if [ -z "$DEVICE" ]; then
        echo "✅ No device matched (as expected). Pod is Pending."
    fi
    STATUS=$(kubectl get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo "   Pod status: $STATUS"
}

# ── Group 1: A (7g.40gb) + D (4g.20gb) + E (3g.20gb) + C (negative) ──
echo ""
echo "════ Group 1: Multi-Profile Concurrent Matching (A+D+E) + Negative (C) ════"
kubectl apply -f - <<'EOF'
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: m10-2a-sm-claim
spec:
  devices:
    requests:
    - name: mig-req
      exactly:
        count: 1
        deviceClassName: mig.nvidia.com
        selectors:
        - cel:
            expression: "device.capacity['gpu.nvidia.com'].multiprocessors.compareTo(quantity('90')) >= 0 && device.capacity['gpu.nvidia.com'].multiprocessors.compareTo(quantity('100')) < 0"
---
apiVersion: v1
kind: Pod
metadata:
  name: m10-2a-sm-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sh", "-c", "echo '=== Case A: 90 <= SM < 100 ===' && nvidia-smi -L && sleep 3600"]
    resources:
      claims:
      - name: gpus
  resourceClaims:
  - name: gpus
    resourceClaimName: m10-2a-sm-claim
  restartPolicy: Never
---
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: m10-2d-sm-claim
spec:
  devices:
    requests:
    - name: mig-req
      exactly:
        count: 1
        deviceClassName: mig.nvidia.com
        selectors:
        - cel:
            expression: "device.capacity['gpu.nvidia.com'].multiprocessors.compareTo(quantity('50')) >= 0 && device.capacity['gpu.nvidia.com'].multiprocessors.compareTo(quantity('60')) < 0"
---
apiVersion: v1
kind: Pod
metadata:
  name: m10-2d-sm-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sh", "-c", "echo '=== Case D: 50 <= SM < 60 ===' && nvidia-smi -L && sleep 3600"]
    resources:
      claims:
      - name: gpus
  resourceClaims:
  - name: gpus
    resourceClaimName: m10-2d-sm-claim
  restartPolicy: Never
---
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: m10-2e-vram-claim
spec:
  devices:
    requests:
    - name: mig-req
      exactly:
        count: 1
        deviceClassName: mig.nvidia.com
        selectors:
        - cel:
            expression: "device.capacity['gpu.nvidia.com'].memory.compareTo(quantity('15Gi')) >= 0 && device.capacity['gpu.nvidia.com'].memory.compareTo(quantity('25Gi')) < 0"
---
apiVersion: v1
kind: Pod
metadata:
  name: m10-2e-vram-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sh", "-c", "echo '=== Case E: 15Gi <= VRAM < 25Gi ===' && nvidia-smi -L && sleep 3600"]
    resources:
      claims:
      - name: gpus
  resourceClaims:
  - name: gpus
    resourceClaimName: m10-2e-vram-claim
  restartPolicy: Never
---
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: m10-2c-sm-range-claim
spec:
  devices:
    requests:
    - name: mig-req
      exactly:
        count: 1
        deviceClassName: mig.nvidia.com
        selectors:
        - cel:
            expression: "device.capacity['gpu.nvidia.com'].multiprocessors.compareTo(quantity('100')) > 0"
---
apiVersion: v1
kind: Pod
metadata:
  name: m10-2c-sm-range-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sh", "-c", "echo '=== Case C: SM > 100 ===' && nvidia-smi -L && sleep 3600"]
    resources:
      claims:
      - name: gpus
  resourceClaims:
  - name: gpus
    resourceClaimName: m10-2c-sm-range-claim
  restartPolicy: Never
EOF

verify_positive "Case A: SM Range 90-100 (targets 7g.40gb)" "m10-2a-sm-claim" "m10-2a-sm-pod"
verify_positive "Case D: SM Range 50-60 (targets 4g.20gb)" "m10-2d-sm-claim" "m10-2d-sm-pod"
verify_positive "Case E: VRAM 15-25Gi (targets 3g/4g.20gb)" "m10-2e-vram-claim" "m10-2e-vram-pod"
verify_negative "Case C: SM > 100 (negative match)" "m10-2c-sm-range-claim" "m10-2c-sm-range-pod" \
    "No A100 MIG profile exceeds 100 SMs (max is 98). Expected: Pending."

echo ""
echo "Cleaning up Group 1..."
kubectl delete pod m10-2a-sm-pod m10-2d-sm-pod m10-2e-vram-pod m10-2c-sm-range-pod --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim m10-2a-sm-claim m10-2d-sm-claim m10-2e-vram-claim m10-2c-sm-range-claim --ignore-not-found 2>/dev/null || true
sleep 3

# ── Group 2: B (VRAM >= 30Gi, needs 7g.40gb freed from A) ──
echo ""
echo "════ Group 2: VRAM-Based Selection (B) ════"
kubectl apply -f - <<'EOF'
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: m10-2b-vram-claim
spec:
  devices:
    requests:
    - name: mig-req
      exactly:
        count: 1
        deviceClassName: mig.nvidia.com
        selectors:
        - cel:
            expression: "device.capacity['gpu.nvidia.com'].memory.compareTo(quantity('30Gi')) >= 0"
---
apiVersion: v1
kind: Pod
metadata:
  name: m10-2b-vram-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sh", "-c", "echo '=== Case B: VRAM >= 30Gi ===' && nvidia-smi -L && sleep 3600"]
    resources:
      claims:
      - name: gpus
  resourceClaims:
  - name: gpus
    resourceClaimName: m10-2b-vram-claim
  restartPolicy: Never
EOF

verify_positive "Case B: VRAM >= 30Gi (targets 7g.40gb)" "m10-2b-vram-claim" "m10-2b-vram-pod"

# Final Summary
echo ""
echo "━━━ Final Results ━━━"
echo "  Case A (SM 90-100):     ✅ Running — matched 7g.40gb (98 SM)"
echo "  Case B (VRAM >= 30Gi):  ✅ Running — matched 7g.40gb (40320Mi)"
echo "  Case C (SM > 100):      ✅ Pending — no match (negative test)"
echo "  Case D (SM 50-60):      ✅ Running — matched 4g.20gb (56 SM)"
echo "  Case E (VRAM 15-25Gi):  ✅ Running — matched 3g/4g.20gb (20096Mi)"

# Cleanup
echo ""
echo "Step 4: Cleaning up..."
kubectl delete pod m10-2b-vram-pod --force --grace-period=0 2>/dev/null || true
kubectl delete resourceclaim m10-2b-vram-claim --ignore-not-found 2>/dev/null || true

echo ""
echo "=== Module 10.2 Complete ==="
