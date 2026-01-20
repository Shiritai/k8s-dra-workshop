#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
MANIFEST_DIR="$WORKSHOP_DIR/manifests"

# Import Environment Check
source "$SCRIPT_DIR/run-module0-check-env.sh"

echo "=== Module 6.5: vLLM Performance Analysis (MPS Impact - Sensitivity Analysis) ==="

MODEL_NAME="Qwen/Qwen2.5-1.5B-Instruct"
DATASET_URL="https://huggingface.co/datasets/anon8231489123/ShareGPT_Vicuna_unfiltered/resolve/main/ShareGPT_V3_unfiltered_cleaned_split.json"
DATASET_FILE="/tmp/ShareGPT_V3_unfiltered_cleaned_split.json"
RESULT_FILE="/tmp/vllm_benchmark_results.csv"

# Initialize Result File if not exists
if [ ! -f "$RESULT_FILE" ]; then
    echo "Run_ID,MPS_Percentage,Throughput(req/s),TTFT(ms),TPOT(ms),ITL(ms)" > "$RESULT_FILE"
fi

check_and_cleanup_pod() {
    local pod_name=$1
    local claim_name=$2
    if kubectl get pod "$pod_name" &> /dev/null; then
        echo "Cleaning up existing pod $pod_name..."
        kubectl delete pod "$pod_name" --force --grace-period=0
    fi
    if [ -n "$claim_name" ] && kubectl get resourceclaim "$claim_name" &> /dev/null; then
        echo "Cleaning up existing claim $claim_name..."
        # Do NOT use force deletion for claims to avoid Kubelet sync issues
        kubectl delete resourceclaim "$claim_name"
    fi
    # Wait for deletion
    while kubectl get pod "$pod_name" &> /dev/null; do sleep 1; done
    if [ -n "$claim_name" ]; then
        while kubectl get resourceclaim "$claim_name" &> /dev/null; do sleep 1; done
    fi
    # Extra safety sleep
    sleep 5
}

wait_for_pod_ready() {
    local pod_name=$1
    echo "Waiting for pod $pod_name to be ready..."
    kubectl wait --for=condition=Ready pod/"$pod_name" --timeout=600s
}

# Function to run benchmark
run_benchmark() {
    local pod_name=$1
    local mps_pct=$2
    local run_id=$3
    local label="run${run_id}_mps_${mps_pct}pct"
    
    echo ">>> Running Benchmark for: $label ($mps_pct% MPS Active Thread, Run $run_id)"
    
    # Download dataset inside pod if not exists
    kubectl exec "$pod_name" -- bash -c "if [ ! -f $DATASET_FILE ]; then curl -sL -o $DATASET_FILE $DATASET_URL; fi"
    
    # Run vLLM Server in background
    echo "Starting vLLM Server..."
    kubectl exec "$pod_name" -- bash -c "nohup vllm serve $MODEL_NAME --port 8000 --gpu-memory-utilization 0.9 > /tmp/vllm.log 2>&1 &"
    
    # Wait for server to be ready
    echo "Waiting for vLLM server to be ready..."
    for i in {1..300}; do
        if kubectl exec "$pod_name" -- curl -s http://localhost:8000/health > /dev/null; then
            echo "Server is ready."
            break
        fi
        if [ $i -eq 300 ]; then
            echo "Timeout waiting for vLLM server."
            kubectl exec "$pod_name" -- cat /tmp/vllm.log
            return 1
        fi
        sleep 2
    done
    
    # Run Benchmark
    echo "Running vllm bench serve..."
    # Capture output
    kubectl exec "$pod_name" -- vllm bench serve \
        --model "$MODEL_NAME" \
        --dataset-name sharegpt \
        --dataset-path "$DATASET_FILE" \
        --num-prompts 100 \
        --request-rate 4.0 \
        --port 8000 > "/tmp/result-$label.txt"
        
    echo "Benchmark Complete for $mps_pct% (Run $run_id)."
    
    # Parse Results
    local throughput=$(grep "Request throughput" "/tmp/result-$label.txt" | awk '{print $4}')
    local ttft=$(grep "Mean TTFT" "/tmp/result-$label.txt" | awk '{print $4}')
    local tpot=$(grep "Mean TPOT" "/tmp/result-$label.txt" | awk '{print $4}')
    local itl=$(grep "Mean ITL" "/tmp/result-$label.txt" | awk '{print $4}')
    
    echo "$run_id,$mps_pct,$throughput,$ttft,$tpot,$itl" >> "$RESULT_FILE"
    echo "Recorded: Run $run_id, $mps_pct% -> Throughput: $throughput, TTFT: $ttft, TPOT: $tpot, ITL: $itl"
    
    # Stop server
    kubectl exec "$pod_name" -- pkill -f "vllm serve"
}

# Main Loop: 20% to 100%, 3 Runs
PERCENTAGES=(20 40 60 80 100)
RUNS=(1 2 3)

for run in "${RUNS[@]}"; do
    echo "########################################"
    echo "Starting Benchmark Run: $run / 3"
    echo "########################################"
    
    for pct in "${PERCENTAGES[@]}"; do
        # Check if result already exists
        if grep -q "^$run,$pct," "$RESULT_FILE"; then
            echo "Skipping Run $run, MPS $pct% (Already completed)"
            continue
        fi

        echo "========================================"
        echo "Starting Test for MPS Active Thread Percentage: $pct% (Run $run)"
        echo "========================================"
        
        # Cleanup
        # Generate unique claim name with timestamp to avoid Kubelet stuck issues on retries
        claim_name="vllm-gpu-claim-run${run}-mps${pct}-$(date +%s)"

        # Cleanup
        check_and_cleanup_pod "vllm-server" "$claim_name"
        
        # Deploy with specific MPS percentage
        # We use sed to modify the manifest on the fly
        # Also replace claim name to avoid Kubelet stuck issues
        sed "s/value: \"100\"/value: \"$pct\"/" "$MANIFEST_DIR/demo-vllm.yaml" | \
        sed "s/vllm-gpu-claim/$claim_name/g" | \
        kubectl create -f -
        
        wait_for_pod_ready "vllm-server"
        
        run_benchmark "vllm-server" "$pct" "$run"
        
        echo "Test for $pct% (Run $run) complete."
        echo ""
        
        # Cool down between tests
        echo "Cooling down for 10s..."
        sleep 10
    done
    
    # Longer cool down between runs
    echo "Run $run complete. Cooling down for 30s..."
    sleep 30
done

echo "=== All Benchmarks Complete ==="
echo "Results saved to $RESULT_FILE"
cat "$RESULT_FILE" | column -t -s,
