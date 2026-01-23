---
marp: true
theme: default
paginate: true
header: "NVIDIA DRA Workshop - Phase 1"
footer: "Module 6 & 6.5"
style: |
  section {
    background-color: #ffffff;
    color: #000000;
    font-size: 28px;
  }
  h1, h2, h3, h4, h5, h6 {
    color: #000000 !important;
  }
  p, li, table, th, td {
    color: #000000 !important;
  }
  img[alt~="center"] {
    display: block;
    margin: 0 auto;
  }
  /* Force Code Blocks to Black on White */
  pre, code {
    background-color: #ffffff !important;
    color: #000000 !important;
    border: 1px solid #000000;
  }
  /* Marp/Highlight.js specific overrides */
  .hljs {
    background: #ffffff !important;
    color: #000000 !important;
  }
  /* Table styling for clarity */
  table {
    font-size: 25px;
    color: #000000;
  }
---

<!-- class: default -->
# Module 6 & 6.5
## Real-World Workloads & Performance Analysis

**Goal**: Verify Enterprise-Grade LLM Performance under MPS Constraints

---

# Recap: Phase 1 Journey (Modules 0-5)

We have built a **Production-Grade Infrastructure** from scratch.

- **Mod 0-2 (Infra)**:
    - Prepared Host (CDI, Drivers).
    - Built Kind Cluster with **In-Cluster MPS** (Fake Daemon Pattern).
    - Installed DRA Driver (Helm, Structured Parameters).
- **Mod 3-5 (Basics)**:
    - Verified **Exclusive Access** (Claim-Bind-Run).
    - Enabled **Spatial Sharing** (MPS IPC Bridge).
    - Enforced **QoS Limits** (Memory & Thread Isolation).

> *Everything is ready for the real workload.*

---

# This Update: Module 6 vs 6.5

We introduce two distinct AI workload verifications.

| Feature         | Module 6: Verification | Module 6.5: Experiment          |
| :-------------- | :--------------------- | :------------------------------ |
| **Goal**        | **Functional Check**   | **Quantitative Benchmark**      |
| **Tool**        | `curl` (Single Req)    | `vllm bench` (Suite)            |
| **Prompt**      | "Hello World"          | ShareGPT Dataset (100+)         |
| **Concurrency** | 1 (Sequential)         | 4.0 req/s (High Load)           |
| **Metric**      | Success / Fail         | Throughput, TTFT, ITL           |
| **Value**       | "It Runs."             | "Limitation & Performance." |

---

# Module 6: vLLM Verification

**The "Final Boss" of Phase 1.**

- **Workload**: `vLLM` (High-Performance Inference Engine)
- **Model**: `Qwen2.5-1.5B-Instruct`
- **Constraint**: **50% MPS Compute Limit**

> **Why vLLM?**
> Unlike synthetic benchmarks, vLLM uses advanced CUDA features (PagedAttention, CUDA Graphs) and heavily stresses Memory (KVCache) and Compute.

---

# Architecture: vLLM on MPS

We strictly throttle the vLLM container to **50% of the GPU's Streaming Multiprocessors (SMs)**.

![](./arch.svg)

<!-- 
graph LR
    subgraph "Kubernetes Node"
        Daemon[MPS Daemon]
        Vol[Volume: /tmp/nvidia-mps]
    end

    subgraph "Pod: vLLM"
        App[vLLM Server]
        Limit[MPS Limit: 50%]
    end

    App \--\>|Inference Req| Limit
    Limit \--\>|Throttled Stream| Vol
    Vol \--\>|Context 0| Daemon
 -->

---

# Verification criteria

Run: `./scripts/phase1/run-module6-vllm-verify.sh`

1.  **Deployment**: Pod status `Running` (CDI injection successful).
2.  **Initialization**: vLLM loads weights (~1-2 mins) without OOM.
3.  **Inference**:
    ```json
    {
      "model": "Qwen/Qwen2.5-1.5B-Instruct",
      "choices": [{ "text": "Hello! I am Qwen..." }]
    }
    ```

> **Success**: We can legally run **two** such high-performance workloads on a single GPU with zero context-switching penalty!

---

<!-- class: default -->

# Module 6.5: Sensitivity Analysis

**Question**: *How much compute does an LLM actually need?*

---

# Experiment Design: Quantitative Benchmark

We stress-test the GPU using `vllm bench serve` to simulate high-concurrency traffic.

- **Workload**: `ShareGPT` Dataset (Real-world human conversations).
- **Intensity**: 100 Prompts sent at **4.0 requests/second**.
- **Control Variable**: `active_thread_percentage` (20% to 100%).

> **Why ShareGPT?**
> Synthetic fixed-length prompts fail to capture the real-world variance in "Prefill vs. Decode" phases, which interact differently with MPS limits.

---

# Results: Throughput vs. Latency

*Baseline data from RTX 4090 Lab Environment:*

| MPS Limit | Throughput (req/s) | Mean TTFT (ms)   | Mean ITL (ms)   | Impact         |
| :-------- | :----------------- | :--------------- | :-------------- | :------------- |
| **20%**   | **3.47** (Stable)  | **42.97** (High) | **7.00** (+27%) | 🔴 High Latency |
| **40%**   | 3.56               | 25.50            | 5.77            | 🟡 Balanced     |
| **60%**   | 3.57               | 21.12            | 5.50            | 🟢 Good         |
| **80%**   | 3.58               | 17.95            | 5.25            | 🟢 Excellent    |
| **100%**  | 3.57               | 17.21            | 5.48            | 🔵 Baseline     |

---

# Key Insights

1.  **Throughput is Robust**:
    - vLLM is **not** compute-bound for pure throughput at this batch size.
    - Dropping to 20% compute only slightly affects req/s.

2.  **Latency is Sensitive**:
    - **Prefill (TTFT)** is compute-heavy. Reducing SMs by 5x (100% -> 20%) increases latency by **2.5x**.
    - **Decoding (ITL)** suffers at low concurrency, causing "stuttering" text generation.

---

# Conclusion: Proven Control & Observability

**We successfully tamed the "Final Boss" (vLLM) with DRA + MPS.**

1.  **Deterministic Control**:
    - Proved that rigorous compute limits effectively constrain complex AI workloads.
    - Resources enforced, making the GPU become a manageable shared resource.

2.  **Trade-off Visibility**:
    - We revealed the clear relationship between **Compute** and **Latency** (TTFT/ITL).
    - Platform Engineers can now tune `active_thread_percentage` to balance **Density** vs **QoS** based on *their* hardware and *their* SLA.

> **Takeaway**: We confirmed that vLLM is fully under the control of DRA + MPS.

---

<!-- class: default -->

# Thank You

**End of Phase 1 Walkthrough**
