# Module 6.5: vLLM Performance Sensitivity Analysis

## 1. Objective

This module is an advanced experiment designed to explore the specific impact of different MPS (Multi-Process Service) **Active Thread Percentage** limits on LLM inference performance. We conduct a **Sensitivity Analysis** to observe performance metrics (Throughput, TTFT, ITL) under various `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` settings.

## 2. Experiment Design

We execute an automated loop test to measure performance with MPS Active Thread Percentage ranging from 20% to 100%:

- **Variable**: `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` (20, 40, 60, 80, 100)
- **Fixed**:
  - Model Parameters & Input Dataset (`ShareGPT`)
  - `gpu-memory-utilization` (0.9)
  - Request Rate (4.0 req/s)

## 3. Execution Steps

Run the following script to automatically complete the loop test and data collection:

```bash
./scripts/phase1/run-module6-vllm-experiment.sh
```

The script will:

1. Automatically deploy vLLM Pods in a loop (20% -> 100%).
2. Execute `vllm bench serve` after each deployment.
3. Repeat execution multiple times (default 3 runs) to gather statistical data.
4. Aggregate and output a CSV performance report (`/tmp/vllm_benchmark_results.csv`).

## 4. Experiment Results (Sensitivity Analysis)

The following are the aggregated results from 4 independent runs (Mean ± Std Dev), with 100% MPS Active Thread Percentage as the Baseline:

| MPS Active Thread (%) | Throughput (req/s) | Mean TTFT (ms) | Mean TPOT (ms) | Mean ITL (ms) | TTFT Impact (vs 100%) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **20%** | 3.48 ± 0.06 | 42.78 ± 1.66 | 6.94 ± 0.54 | 6.91 ± 0.60 | ~2.48x Slower |
| **40%** | 3.56 ± 0.00 | 25.42 ± 0.17 | 5.81 ± 0.01 | 5.76 ± 0.01 | ~1.47x Slower |
| **60%** | 3.57 ± 0.00 | 21.18 ± 0.16 | 5.55 ± 0.01 | 5.50 ± 0.01 | ~1.23x Slower |
| **80%** | 3.58 ± 0.00 | 17.97 ± 0.21 | 5.28 ± 0.02 | 5.25 ± 0.02 | ~1.04x Slower |
| **100%** | 3.56 ± 0.01 | 17.26 ± 0.23 | 5.50 ± 0.02 | 5.47 ± 0.03 | Baseline |

### Analysis

#### 1. Core Metrics Comparison (Mean vs P99)

In addition to the mean, we further analyze **P99 (99th Percentile)** data (averaged from 3 runs), which better reflects system stability and Tail Latency under load.

| MPS Active Thread | Mean TTFT (ms) | **P99 TTFT (ms)** | Mean ITL (ms) | **P99 ITL (ms)** |
| :--- | :--- | :--- | :--- | :--- |
| **20%** | 42.78 | **97.07 ± 2.39** | 6.91 | **29.37 ± 6.04** |
| **40%** | 25.42 | **53.13 ± 0.68** | 5.76 | **12.79 ± 0.11** |
| **60%** | 21.18 | 40.82 ± 1.24 | 5.50 | 10.05 ± 0.16 |
| **80%** | 17.97 | 32.07 ± 0.49 | 5.25 | 7.29 ± 0.11 |
| **100%** | 17.26 | **29.99 ± 1.45** | 5.47 | **7.02 ± 0.25** |

> *Note: P99 latency significantly increases under 20% MPS Active Thread, indicating strong tail effects when resources are constrained.*

#### 2. Deep Insights

1.  **Non-linear Relationship between Throughput and Compute Capability**:
    - Even under the **20% MPS Active Thread** limit, the system maintains a **Request Throughput (~3.5 req/s)** almost identical to 100%.
    - This indicates that for this specific workload (Concurrency=13, Qwen2.5-1.5B), **Compute Capability is not the bottleneck for throughput**.

2.  **Cost of Tail Latency**:
    - Although the average throughput at 20% meets the target, its **P99 ITL (29.37ms)** is significantly higher than the 40% setting (12.79ms). This means that under low resource configurations, the "stuttering" during generation will be very noticeable, resulting in an unstable user experience.
    - **40% MPS Active Thread** shows a better balance. Although P99 ITL (12.79ms) is still higher than 100% (7.02ms), it is a significant improvement over 20%.

3.  **Resource Sensitivity in Prefill Phase**:
    - TTFT (Time To First Token) is directly constrained by compute resources. From 20% to 40%, the average TTFT decreased by 40%, and P99 TTFT also improved significantly. This confirms that the Prefill phase is highly Compute-Bound.
