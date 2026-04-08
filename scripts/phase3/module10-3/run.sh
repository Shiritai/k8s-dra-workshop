#!/bin/bash
# M10.3: MIG Isolation Verification
# Goal: Prove that OOM on one MIG slice does NOT affect another.
#
# Setup:
#   - vllm-llama: High-SLA pod on a larger MIG slice (SM >= 50, e.g., 4g.20gb or 7g.40gb)
#   - vllm-gemma: Standard pod on a smaller MIG slice (SM < 50, e.g., 3g.20gb)
#
# Test: Force OOM on vllm-gemma, verify vllm-llama survives.

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST="$WORKSHOP_DIR/manifests/module10/10.3-vllm-isolation.yaml"

echo "=== Module 10.3: MIG Isolation Verification ==="

# Cleanup
echo "Step 1: Cleaning up previous resources..."
kubectl delete -f "$MANIFEST" --ignore-not-found --wait=true 2>/dev/null || true
sleep 2

# Deploy
echo "Step 2: Deploying isolation workloads..."
kubectl apply -f "$MANIFEST"

# Wait for both pods
echo "Step 3: Waiting for pods..."
for pod in vllm-llama vllm-gemma; do
    if kubectl wait --for=condition=Ready pod/$pod --timeout=90s 2>/dev/null; then
        echo "✅ $pod is Running."
    else
        echo "❌ $pod failed to start."
        kubectl describe pod $pod | tail -5
        exit 1
    fi
done

# Show which MIG slices were allocated
echo ""
echo "Step 4: Device allocation:"
for claim in vllm-high-sla-claim vllm-standard-claim; do
    DEVICE=$(kubectl get resourceclaim "$claim" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
    PROFILE=$(kubectl get resourceslices -o json | jq -r ".items[].spec.devices[] | select(.name == \"$DEVICE\") | .attributes.profile.string // \"N/A\"" 2>/dev/null)
    SM=$(kubectl get resourceslices -o json | jq -r ".items[].spec.devices[] | select(.name == \"$DEVICE\") | .capacity.multiprocessors.value // \"?\"" 2>/dev/null)
    echo "  $claim → $DEVICE (profile=$PROFILE, SM=$SM)"
done

# Compile stress test on the standard pod
echo ""
echo "Step 5: Compiling stress test on vllm-gemma..."
kubectl exec vllm-gemma -- bash -c 'cd /tmp/work && nvcc stress.cu -o stress' 2>&1

# Sanity check: small allocation should work
echo ""
echo "Step 6: Sanity check (allocate 1GB on vllm-gemma)..."
if kubectl exec vllm-gemma -- /tmp/work/stress 1 2>&1; then
    echo "✅ 1GB allocation succeeded."
else
    echo "❌ 1GB allocation failed. CUDA environment broken."
    exit 1
fi

# Record vllm-llama status before stress
BEFORE=$(kubectl get pod vllm-llama -o jsonpath='{.status.phase}')
echo ""
echo "Step 7: vllm-llama status before stress: $BEFORE"

# Trigger OOM: try to allocate more than the 3g.20gb slice can hold (~19GB)
echo ""
echo "Step 8: Triggering OOM on vllm-gemma (attempting 25GB allocation)..."
OOM_OUTPUT=$(kubectl exec vllm-gemma -- /tmp/work/stress 25 2>&1) || true
echo "  Result: $OOM_OUTPUT"

if echo "$OOM_OUTPUT" | grep -qi "failed\|error\|out of memory"; then
    echo "✅ OOM triggered on vllm-gemma as expected."
else
    echo "⚠️ Allocation did not fail (MIG slice may have enough memory)."
fi

# Verify vllm-llama survived
echo ""
echo "Step 9: Checking vllm-llama after OOM stress..."
AFTER=$(kubectl get pod vllm-llama -o jsonpath='{.status.phase}')
echo "  vllm-llama status: $AFTER"

if [ "$AFTER" = "Running" ]; then
    echo "✅ vllm-llama survived! MIG hardware isolation confirmed."
    # Also verify it can still use GPU
    kubectl exec vllm-llama -- nvidia-smi -L 2>&1 || true
else
    echo "❌ vllm-llama is no longer Running ($AFTER). Isolation may have failed."
fi

# Cleanup
echo ""
echo "Step 10: Cleaning up..."
kubectl delete -f "$MANIFEST" --ignore-not-found --wait=false 2>/dev/null || true

echo ""
echo "=== Module 10.3 Complete ==="
