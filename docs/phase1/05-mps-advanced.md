# Module 5: MPS Advanced (Resource Limits & QoS)

The true power of MPS lies in **Active Resource Partitioning**. This module verifies that we can enforce strict limits on both Compute (Threads) and Memory, ensuring QoS for multi-tenant workloads.

## 1. Automated Verification (Basic)
Run the automated stress test:
```bash
./scripts/phase1/run-module5-mps-advanced.sh
```

### What it tests:
1. **Sanity Check**: Allocates 100MB (Should Pass).
2. **OOM Test**: Allocates 2GB on a 1GB-limited Pod (Should Fail).
3. **Env Injection**: Confirms `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=20` is set.

## 2. Empirical Verification (Advanced)
We designed two advanced schemes to verify that the Thread Percentage limit actually throttles performance.

### Scheme A: Extreme Throttling (1% vs 100%)
We ran a heavy Matrix Multiplication (N=4096) on an RTX 4090:

| Configuration | Compute Limit | Throughput   | Impact      |
| ------------- | ------------- | ------------ | ----------- |
| Baseline      | 100%          | 5.29 TFLOPS  | 1x          |
| Throttled     | 1%            | 0.078 TFLOPS | ~68x Slower |

**Conclusion**: The limit is strictly enforced at the hardware (SM) level.

### Scheme B: Multi-Tenant Competition
We deployed **3 Pods** simultaneously on a single GPU, each limited to **20%**.

| Pod   | Limit | Observed Throughput |
| ----- | ----- | ------------------- |
| Pod 1 | 20%   | 0.860 TFLOPS        |
| Pod 2 | 20%   | 0.865 TFLOPS        |
| Pod 3 | 20%   | 0.856 TFLOPS        |

**Conclusion**: MPS ensures fair, deterministic partitioning even under heavy contention.

## 3. How to Reproduce (Manual)
You can reproduce Scheme A using the provided manifests:

1. **Deploy 1% Pod**:
   ```bash
   kubectl apply -f manifests/test-mps-1pct.yaml
   ```
2. **Compile Benchmark (inside pod)**:
   ```bash
   kubectl cp scripts/phase1/verify-mps-throughput.cu mps-1pct:/tmp/bench.cu
   kubectl exec mps-1pct -- nvcc /tmp/bench.cu -o /tmp/bench
   ```
3. **Run**:
   ```bash
   kubectl exec mps-1pct -- /tmp/bench 4096 10
   ```

## 4. Technical Deep Dive
### Memory Limiting (`CUDA_MPS_PINNED_DEVICE_MEM_LIMIT`)
- **Mechanism**: The MPS Server intercepts `cudaMalloc` calls.
- **Behavior**: If a request exceeds the per-context limit, it returns `cudaErrorMemoryAllocation` immediately, protecting other tenants from OOM crashes.

### Compute Limiting (`CUDA_MPS_ACTIVE_THREAD_PERCENTAGE`)
- **Mechanism**: Limits the number of Streaming Multiprocessors (SMs) available to the context.
- **Behavior**: The kernel is scheduled only on a subset of SMs, effectively functioning as a "hardware partition" (though not as strict as MIG).
