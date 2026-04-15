# Module 11: Stress & Boundary Tests — Overall Analysis

**Status**: ✅ **Verified** (K8s v1.34.0, NVIDIA A100-PCIE-40GB x2, DRA driver v25.8.1)

Module 11 explores the boundary conditions of NVIDIA DRA with MPS sharing on MIG devices. These tests intentionally push resource requests beyond normal limits to determine where the DRA scheduler's awareness ends and where CUDA runtime enforcement begins.

- [Module 11.1: MIG MPS SM Limits](11.1-sm-limits.md)
- [Module 11.2: MIG MPS VRAM Limits](11.2-vram-limits.md)
- [Module 11.3: Multi-MIG MPS per Pod](11.3-multi-mig-mps.md)

---

## Cross-Module Summary

| Test | Key Question | Result |
|---|---|---|
| 11-1a | Does MPS/scheduler allow total thread% > 100%? | **Yes** — scheduler allows it; thread% is per-daemon |
| 11-1b | Does client-side env var enforce per-pod SM limits? | **Yes** — throughput proportional to thread% |
| 11-2a | Is `defaultPinnedDeviceMemoryLimit` enforced on MIG? | **No** — DRA driver bug |
| 11-2b | Does client-side env var enforce VRAM limits on MIG? | **Yes** — `cudaMemGetInfo` virtualized |
| 11-3a | Can one pod use CUDA on 2 MPS MIG slices? | Scheduled yes, **CUDA sees only 1 device** |
| 11-3b | Can one pod mix exclusive + MPS across MIG? | Scheduled yes, **only MPS device visible** |

---

## Key Insights

1. **`GpuConfig` vs `MigDeviceConfig`**: The DRA driver uses different config types for full GPUs and MIG devices. Using `kind: GpuConfig` with `mig.nvidia.com` devices causes the driver to silently fall back to `DefaultMigDeviceConfig()` (TimeSlicing, no MPS). **You must use `kind: MigDeviceConfig`** for MIG devices to enable MPS sharing.

2. **MPS memory limit is ineffective on MIG (DRA driver bug)**: `defaultPinnedDeviceMemoryLimit` is silently ignored on MIG devices (11-2a). Root cause: config timing + EXCLUSIVE_PROCESS incompatibility. Workaround: client-side `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` env var (11-2b).

3. **Client-side env vars provide reliable per-pod resource isolation on MIG**: Both `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` (11-1b) and `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` (11-2b) work correctly on MIG, unlike their server-side counterparts.

4. **MPS oversubscription is always allowed at the scheduler level**: The DRA scheduler treats a shared ResourceClaim as a single allocation unit. It does not sum up per-client thread percentages or memory limits. Oversubscription is only detected at CUDA runtime.

5. **MIG devices behave as independent compute units for DRA**: Two claims targeting `mig.nvidia.com` get allocated to two different MIG slices, even on the same physical GPU.

6. **`nvidia-smi` limitations on MIG + MPS**: Inside a MIG-backed MPS container, `nvidia-smi --query-gpu` returns `[Insufficient Permissions]` for memory/utilization fields. Use DCGM or CUDA runtime APIs instead.

7. **MPS daemon = single-device CUDA context**: A Pod with 2 MPS claims gets 2 MPS daemons, but CUDA only connects to one (11-3a, 11-3b). To use N MIG devices via CUDA, use N separate Pods.

8. **Scheduling vs. runtime enforcement gap**: The DRA scheduler is capacity-unaware for MPS parameters — it schedules based on device availability, not resource fit. KEP-5075 (Consumable Capacity) aims to close this gap.

---

## The Scheduling vs. Runtime Gap

```text
┌─────────────────────────────┐     ┌─────────────────────────────┐
│     DRA Scheduler           │     │     CUDA Runtime            │
│                             │     │                             │
│  ✅ Device availability     │     │  ✅ Physical memory limits   │
│  ✅ CEL attribute matching  │     │  ✅ SM execution             │
│  ❌ MPS thread% totals      │     │  ⚠️  Per-client VRAM (MIG)   │
│  ❌ MPS VRAM totals         │     │  ✅ Per-client VRAM (GPU)    │
│                             │     │                             │
│  "Is the device free?"      │     │  "Does the memory fit?"     │
└─────────────────────────────┘     └─────────────────────────────┘
```

---

## Recommendations

| Scenario | Solution |
|----------|----------|
| Per-pod SM isolation on MIG | `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` env var (11-1b) |
| Per-pod VRAM isolation on MIG | `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` env var (11-2b) |
| Multi-MIG concurrent compute | Separate Pods, not multi-claim single Pod (11-3a/3b) |
| Server-side MPS config on MIG | **Avoid** — `defaultPinnedDeviceMemoryLimit` broken (11-2a); `defaultActiveThreadPercentage` works but is per-daemon only (11-1a) |

**Future**: KEP-5075 (Consumable Capacity) will allow MPS parameters to be expressed as schedulable quantities, closing the scheduling vs. runtime gap.
