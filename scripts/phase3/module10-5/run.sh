#!/bin/bash
# M10.5: MIG x Observability (Silicon-to-Pod Traceability)
# Goal: Correlate physical MIG UUIDs → DRA DeviceIDs → K8s Pod owners.
#
# Deploys pods on all 3 MIG slices, then runs a traceability audit showing
# the complete chain from physical hardware to Kubernetes workloads.

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
MANIFEST="$WORKSHOP_DIR/manifests/module10/10.5-traceability.yaml"

echo "=== Module 10.5: MIG Observability (Silicon-to-Pod Traceability) ==="

# Cleanup
echo "Step 1: Cleaning up previous resources..."
kubectl delete -f "$MANIFEST" --ignore-not-found --wait=false 2>/dev/null || true
sleep 2

# Deploy 3 pods, one per MIG slice
echo "Step 2: Deploying workloads on all MIG slices..."
kubectl apply -f "$MANIFEST"

echo "Step 3: Waiting for pods..."
for pod in m10-5-pod-a m10-5-pod-b m10-5-pod-c; do
    if kubectl wait --for=condition=Ready pod/$pod --timeout=90s 2>/dev/null; then
        echo "✅ $pod is Running."
    else
        echo "❌ $pod failed to start."
        kubectl describe pod $pod 2>/dev/null | tail -5
        exit 1
    fi
done

# Traceability audit
echo ""
echo "Step 4: Silicon-to-Pod Traceability Audit"
echo ""

# Collect physical MIG UUIDs from pods
echo "┌──────────────────────────────────────────────┬──────────────────────┬──────────────────┬─────────────┐"
echo "│ Physical MIG UUID                            │ DRA Device ID        │ Profile          │ Pod Owner   │"
echo "├──────────────────────────────────────────────┼──────────────────────┼──────────────────┼─────────────┤"

for claim in m10-5-claim-a m10-5-claim-b m10-5-claim-c; do
    DEVICE=$(kubectl get resourceclaim "$claim" -o jsonpath='{.status.allocation.devices.results[0].device}' 2>/dev/null)
    POD_NAME=$(kubectl get resourceclaim "$claim" -o jsonpath='{.status.reservedFor[0].name}' 2>/dev/null)
    PROFILE=$(kubectl get resourceslices -o json | jq -r ".items[].spec.devices[] | select(.name == \"$DEVICE\") | .attributes.profile.string // \"N/A\"" 2>/dev/null)
    UUID=$(kubectl get resourceslices -o json | jq -r ".items[].spec.devices[] | select(.name == \"$DEVICE\") | .attributes.uuid.string // \"N/A\"" 2>/dev/null)

    printf "│ %-44s │ %-20s │ %-16s │ %-11s │\n" "$UUID" "$DEVICE" "$PROFILE" "$POD_NAME"
done

echo "└──────────────────────────────────────────────┴──────────────────────┴──────────────────┴─────────────┘"

# Cross-verify: ask each pod what MIG UUID it sees
echo ""
echo "Step 5: Cross-verification (pod-side nvidia-smi -L)..."
for pod in m10-5-pod-a m10-5-pod-b m10-5-pod-c; do
    MIG_LINE=$(kubectl exec $pod -- nvidia-smi -L 2>&1 | grep MIG || echo "no MIG")
    echo "  $pod: $MIG_LINE"
done

# CDI mapping
echo ""
echo "Step 6: CDI Device Mapping (DRA DeviceID → Linux device nodes)..."
docker exec workshop-dra-control-plane cat /var/run/cdi/k8s.gpu.nvidia.com-device_base.yaml 2>/dev/null | \
    python3 -c '
import sys, yaml
data = yaml.safe_load(sys.stdin)
for dev in data.get("devices", []):
    nodes = [n["path"] for n in dev.get("containerEdits", {}).get("deviceNodes", [])]
    caps = [n for n in nodes if "nvidia-cap" in n]
    print(f"  {dev[\"name\"]}: {caps}")
' 2>/dev/null || echo "  (yaml parsing unavailable, check CDI manually)"

# Cleanup
echo ""
echo "Step 7: Cleaning up..."
kubectl delete -f "$MANIFEST" --ignore-not-found --wait=false 2>/dev/null || true

echo ""
echo "=== Module 10.5 Complete ==="
