#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST_DIR="$WORKSHOP_DIR/manifests"

# Import Environment Check
source "$SCRIPT_DIR/run-module0-check-env.sh"

echo "=== Module 6: vLLM Verification (MPS Functionality Check) ==="

MODEL_NAME="Qwen/Qwen2.5-1.5B-Instruct"
MPS_PCT=50

check_and_cleanup_pod() {
    local pod_name=$1
    local claim_name=$2
    if kubectl get pod "$pod_name" &> /dev/null; then
        echo "Cleaning up existing pod $pod_name..."
        kubectl delete pod "$pod_name" --force --grace-period=0
    fi
    if [ -n "$claim_name" ] && kubectl get resourceclaim "$claim_name" &> /dev/null; then
        echo "Cleaning up existing claim $claim_name..."
        kubectl delete resourceclaim "$claim_name"
    fi
    # Wait for deletion
    while kubectl get pod "$pod_name" &> /dev/null; do sleep 1; done
    if [ -n "$claim_name" ]; then
        while kubectl get resourceclaim "$claim_name" &> /dev/null; do sleep 1; done
    fi
    sleep 2
}

wait_for_pod_ready() {
    local pod_name=$1
    echo "Waiting for pod $pod_name to be ready..."
    kubectl wait --for=condition=Ready pod/"$pod_name" --timeout=600s
}

# Generate unique claim name
claim_name="vllm-gpu-claim-verify-$(date +%s)"

echo "Step 1: Cleaning up..."
check_and_cleanup_pod "vllm-server" "$claim_name"

echo "Step 2: Deploying vLLM with MPS Active Thread Percentage: $MPS_PCT%..."
sed "s/value: \"100\"/value: \"$MPS_PCT\"/" "$MANIFEST_DIR/demo-vllm.yaml" | \
sed "s/vllm-gpu-claim/$claim_name/g" | \
kubectl create -f -

wait_for_pod_ready "vllm-server"

echo "Step 2.5: Starting vLLM Server..."
kubectl exec "vllm-server" -- bash -c "nohup vllm serve $MODEL_NAME --port 8000 --gpu-memory-utilization 0.9 > /tmp/vllm.log 2>&1 &"

echo "Step 3: Waiting for vLLM Server to be healthy..."
# Wait for server to be ready
for i in {1..300}; do
    if kubectl exec "vllm-server" -- curl -s http://localhost:8000/health > /dev/null; then
        echo "Server is ready."
        break
    fi
    if [ $i -eq 300 ]; then
        echo "Timeout waiting for vLLM server."
        kubectl exec "vllm-server" -- cat /tmp/vllm.log
        exit 1
    fi
    sleep 2
done

echo "Step 4: Running Inference Verification..."
# Simple generation request
kubectl exec "vllm-server" -- curl -s http://localhost:8000/v1/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$MODEL_NAME"'",
        "prompt": "Hello, Kubernetes!",
        "max_tokens": 50,
        "temperature": 0
    }' > /tmp/vllm_verify_output.json

echo "Inference Output:"
cat /tmp/vllm_verify_output.json
echo ""

if grep -q "text" /tmp/vllm_verify_output.json; then
    echo "✅ Verification Successful: vLLM generated text under MPS constraints."
else
    echo "❌ Verification Failed: No text generated."
    exit 1
fi

echo "Step 5: Cleaning up..."
check_and_cleanup_pod "vllm-server" "$claim_name"

echo "=== Module 6 Verification Complete ==="

