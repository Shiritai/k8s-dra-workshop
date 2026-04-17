# Module 11: Stress & Boundary Tests — Overall Analysis

**Status**: ✅ **Verified** (K8s v1.34.0, NVIDIA A100-PCIE-40GB x2, DRA driver v25.8.1)

Module 11 explores the boundary conditions of NVIDIA DRA with MPS sharing on MIG devices. These tests intentionally push resource requests beyond normal limits to determine where the DRA scheduler's awareness ends and where CUDA runtime enforcement begins.

- [Module 11.1: MIG MPS SM Limits](11.1-sm-limits.md)
- [Module 11.2: MIG MPS VRAM Limits](11.2-vram-limits.md)
- [Module 11.3: Multi-MIG MPS per Pod](11.3-multi-mig-mps.md)

---

## Cross-Module Summary

| Test | Mechanism | Key Question | Result |
|---|---|---|---|
| 11-1a | Server-side SM (1 shared claim, 1 device) | Does per-daemon `defaultActiveThreadPercentage` produce uniform SM ceiling across all clients? | **Yes** — 3 pods sharing 1 MIG all see 20 SMs and ~2300 GFLOPS (uniform cap, not per-pod differentiation) |
| 11-1b | Client-side SM (1 claim, 1 device) | Does per-pod `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` enforce SM limits on a shared device? | **Yes** — throughput proportional to thread% (10%=507, 30%=1438, 50%=2331 GFLOPS) |
| 11-2a | Server-side VRAM (4 GiB limit) | Is `defaultPinnedDeviceMemoryLimit: 4Gi` enforced on MIG? | **No** — 4.5 GiB allocation succeeds despite 4 GiB limit (DRA driver bug) |
| 11-2b | Client-side VRAM (4 GiB limit) | Does `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=4096M` enforce limits on MIG? | **Yes** — 4.5 GiB rejected; `cudaMemGetInfo` virtualized to ~4 GiB |
| 11-3a | Multi-MIG (2 MPS claims) | Can one pod use CUDA on 2 MPS MIG slices? | Scheduled yes, **CUDA sees only 1 device** |
| 11-3b | Multi-MIG (exclusive + MPS) | Can one pod mix exclusive + MPS across MIG? | Scheduled yes, **only MPS device visible** |

---

## Key Insights

1. **`GpuConfig` vs `MigDeviceConfig`**: The DRA driver uses different config types for full GPUs and MIG devices. Using `kind: GpuConfig` with `mig.nvidia.com` devices causes the driver to silently fall back to `DefaultMigDeviceConfig()` (TimeSlicing, no MPS). **You must use `kind: MigDeviceConfig`** for MIG devices to enable MPS sharing.

2. **MPS memory limit is ineffective on MIG (MIG × MPS incompatibility)**: `defaultPinnedDeviceMemoryLimit` is silently ignored on MIG devices (11-2a). Root cause: `EXCLUSIVE_PROCESS` mode — required for MPS server-side memory accounting — is not supported on MIG-enabled GPUs. The DRA driver's `setComputeMode("EXCLUSIVE_PROCESS")` call silently fails; the daemon startup sequence itself is correct by design (works on non-MIG GPUs). Workaround: client-side `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` env var (11-2b).

3. **Client-side env vars provide reliable per-pod resource isolation on MIG**: Both `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` (11-1b) and `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` (11-2b) work correctly on MIG. The 11-1 paired experiment compares server-side uniform ceiling (11-1a: all pods see 20 SMs) vs. client-side per-pod differentiation (11-1b: 10/30/50%). The 11-2 paired experiment uses the same allocation sizes (4.5/3/3 GiB at 4 GiB limit) to compare server-side vs. client-side VRAM enforcement.

4. **Server-side SM limiting is per-daemon, not per-client**: `defaultActiveThreadPercentage` enforces a uniform SM ceiling across all clients sharing a daemon (11-1a) — 3 pods on 1 MIG all see the same 20 SMs. It works as a global cap but cannot differentiate per-pod. Client-side `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` achieves per-pod differentiation on the same shared device (11-1b).

5. **MPS oversubscription is always allowed at the scheduler level**: The DRA scheduler treats a shared ResourceClaim as a single allocation unit. It does not sum up per-client thread percentages or memory limits. Oversubscription is only detected at CUDA runtime.

6. **MIG devices behave as independent compute units for DRA**: Two claims targeting `mig.nvidia.com` get allocated to two different MIG slices, even on the same physical GPU.

7. **`nvidia-smi` limitations on MIG + MPS**: Inside a MIG-backed MPS container, `nvidia-smi --query-gpu` returns `[Insufficient Permissions]` for memory/utilization fields. Use DCGM or CUDA runtime APIs instead.

8. **MPS daemon = single-device CUDA context**: A Pod with 2 MPS claims gets 2 MPS daemons, but CUDA only connects to one (11-3a, 11-3b). To use N MIG devices via CUDA, use N separate Pods.

9. **Scheduling vs. runtime enforcement gap**: The DRA scheduler is capacity-unaware for MPS parameters — it schedules based on device availability, not resource fit. KEP-5075 (Consumable Capacity) aims to close this gap.

---

## The Scheduling vs. Runtime Gap

```text
┌─────────────────────────────┐     ┌─────────────────────────────┐
│     DRA Scheduler           │     │     CUDA Runtime            │
│                             │     │                             │
│  ✅ Device availability     │     │  ✅ Physical memory limits   │
│  ✅ CEL attribute matching  │     │  ✅ SM execution             │
│  ⚠️ MPS thread% totals      │     │  ⚠️  Per-client VRAM (MIG)   │
│  ❌ MPS VRAM totals         │     │  ✅ Per-client VRAM (GPU)    │
│                             │     │                             │
│  "Is the device free?"      │     │  "Does the memory fit?"     │
└─────────────────────────────┘     └─────────────────────────────┘
```

---

## Recommendations

| Scenario | Solution |
|----------|----------|
| Per-pod SM isolation on MIG | `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` env var — per-pod on a single device (11-1b) |
| Per-pod VRAM isolation on MIG | `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` env var (11-2b) |
| Multi-MIG concurrent compute | Separate Pods, not multi-claim single Pod (11-3a/3b) |
| Server-side SM limiting | `defaultActiveThreadPercentage` applies a uniform ceiling to all clients on the daemon — effective as a global cap but cannot differentiate per-pod (11-1a) |
| Server-side VRAM limiting on MIG | **Avoid** — `defaultPinnedDeviceMemoryLimit` broken on MIG (11-2a) |

**Future**: KEP-5075 (Consumable Capacity) will allow MPS parameters to be expressed as schedulable quantities, closing the scheduling vs. runtime gap.
