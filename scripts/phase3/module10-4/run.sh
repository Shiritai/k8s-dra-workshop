#!/bin/bash
# M10.4: MIG x MPS Hybrid Configuration
# Goal: Demonstrate multi-tier sharing — MIG (hardware isolation) + MPS (logical sharing).
#
# Case A: 2 Pods sharing 1 MIG slice (4g.20gb or 7g.40gb) via MPS config
# Case B: 4 Pods on 2 MIG slices (4g.20gb + 3g.20gb), each shared via MPS config
#
# NOTE: DRA driver v25.8.1 may not start MPS daemons for MIG devices.
#       The key verification is that multiple pods share the same MIG device
#       (same MIG UUID visible from both pods), which is the prerequisite for MPS.

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST_A="$WORKSHOP_DIR/manifests/module10/10.4a-mps-single-mig.yaml"
MANIFEST_B="$WORKSHOP_DIR/manifests/module10/10.4b-mps-multi-mig.yaml"

echo "=== Module 10.4: MIG x MPS Hybrid Configuration ==="

# Cleanup
echo "Step 1: Cleaning up previous resources..."
kubectl delete -f "$MANIFEST_B" --ignore-not-found --wait=true 2>/dev/null || true
kubectl delete -f "$MANIFEST_A" --ignore-not-found --wait=true 2>/dev/null || true
sleep 2

# ─── Case A: Single MIG + MPS ───
echo ""
echo "=== Case A: Single-MIG x MPS Sharing (2 Pods on 1 MIG slice) ==="
echo "Step 2: Deploying Case A..."
kubectl apply -f "$MANIFEST_A"

echo "Step 3: Waiting for Case A pods..."
CASE_A_OK=true
for pod in m10-4a-v1-pod-1 m10-4a-v1-pod-2; do
    if kubectl wait --for=condition=Ready pod/$pod --timeout=90s 2>/dev/null; then
        echo "✅ $pod is Running."
    else
        echo "❌ $pod failed to start."
        kubectl describe pod $pod 2>/dev/null | tail -10
        CASE_A_OK=false
    fi
done

if $CASE_A_OK; then
    echo ""
    echo "Step 4: Verifying shared MIG device (Case A)..."
    CLAIM_DEVICE=$(kubectl get resourceclaim m10-4a-claim-v2 -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
    echo "  Shared claim → $CLAIM_DEVICE"

    UUID1=$(kubectl exec m10-4a-v1-pod-1 -- nvidia-smi -L 2>&1 | grep MIG | awk '{print $NF}' | tr -d '()')
    UUID2=$(kubectl exec m10-4a-v1-pod-2 -- nvidia-smi -L 2>&1 | grep MIG | awk '{print $NF}' | tr -d '()')
    echo "  Pod-1 MIG UUID: $UUID1"
    echo "  Pod-2 MIG UUID: $UUID2"

    if [ -n "$UUID1" ] && [ "$UUID1" = "$UUID2" ]; then
        echo "  ✅ Both pods share the same MIG device."
    else
        echo "  ❌ Pods see different MIG devices (or no MIG)."
        CASE_A_OK=false
    fi
fi

# Cleanup Case A before Case B (free MIG devices)
echo ""
echo "Step 5: Cleaning up Case A..."
kubectl delete -f "$MANIFEST_A" --ignore-not-found --wait=true 2>/dev/null || true
sleep 2

# ─── Case B: Multi-MIG + Multi-MPS ───
echo ""
echo "=== Case B: Multi-MIG x Multi-MPS (4 Pods on 2 MIG slices) ==="
echo "Step 6: Deploying Case B..."
kubectl apply -f "$MANIFEST_B"

echo "Step 7: Waiting for Case B pods..."
CASE_B_OK=true
for pod in m10-4b-mps-pod-1 m10-4b-mps-pod-2 m10-4b-mps-pod-3 m10-4b-mps-pod-4; do
    if kubectl wait --for=condition=Ready pod/$pod --timeout=90s 2>/dev/null; then
        echo "✅ $pod is Running."
    else
        echo "❌ $pod failed to start."
        kubectl describe pod $pod 2>/dev/null | tail -10
        CASE_B_OK=false
    fi
done

if $CASE_B_OK; then
    echo ""
    echo "Step 8: Verifying device allocation (Case B)..."
    for claim in m10-4b-claim-a-v1 m10-4b-claim-b-v1; do
        DEVICE=$(kubectl get resourceclaim "$claim" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
        PROFILE=$(kubectl get resourceslices -o json | jq -r ".items[].spec.devices[] | select(.name == \"$DEVICE\") | .attributes.profile.string // \"N/A\"" 2>/dev/null)
        echo "  $claim → $DEVICE (profile=$PROFILE)"
    done

    echo ""
    echo "Step 9: Verifying MIG sharing (Case B)..."
    # Pods 1+2 should share claim-a, Pods 3+4 should share claim-b
    UUID_A1=$(kubectl exec m10-4b-mps-pod-1 -- nvidia-smi -L 2>&1 | grep MIG | awk '{print $NF}' | tr -d '()')
    UUID_A2=$(kubectl exec m10-4b-mps-pod-2 -- nvidia-smi -L 2>&1 | grep MIG | awk '{print $NF}' | tr -d '()')
    UUID_B1=$(kubectl exec m10-4b-mps-pod-3 -- nvidia-smi -L 2>&1 | grep MIG | awk '{print $NF}' | tr -d '()')
    UUID_B2=$(kubectl exec m10-4b-mps-pod-4 -- nvidia-smi -L 2>&1 | grep MIG | awk '{print $NF}' | tr -d '()')

    echo "  Claim A: pod-1=$UUID_A1, pod-2=$UUID_A2"
    echo "  Claim B: pod-3=$UUID_B1, pod-4=$UUID_B2"

    if [ -n "$UUID_A1" ] && [ "$UUID_A1" = "$UUID_A2" ] && [ -n "$UUID_B1" ] && [ "$UUID_B1" = "$UUID_B2" ]; then
        echo "  ✅ Each pair shares its own MIG device."
        if [ "$UUID_A1" != "$UUID_B1" ]; then
            echo "  ✅ The two pairs use different MIG devices (hardware isolation between groups)."
        else
            echo "  ⚠️ Both pairs ended up on the same MIG device."
        fi
    else
        echo "  ❌ Sharing verification failed."
        CASE_B_OK=false
    fi
fi

# Cleanup
echo ""
echo "Step 10: Cleaning up..."
kubectl delete -f "$MANIFEST_B" --ignore-not-found --wait=false 2>/dev/null || true

echo ""
if $CASE_A_OK && $CASE_B_OK; then
    echo "=== Module 10.4 Complete: MIG x MPS hybrid verified ==="
else
    echo "=== Module 10.4 Complete (with warnings) ==="
fi
