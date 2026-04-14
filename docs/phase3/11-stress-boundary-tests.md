# Module 11: Stress & Boundary Tests

> Status: Verified (2026-04-13, K8s v1.34.0, NVIDIA A100-PCIE-40GB x2 (both MIG-enabled), DRA driver v25.8.1)

## Introduction

Module 11 explores the boundary conditions of NVIDIA DRA with MPS sharing on MIG devices. These tests intentionally push resource requests beyond normal limits to observe how the Kubernetes scheduler, DRA driver, and MPS runtime handle oversubscription and multi-device allocation.

These are **exploratory tests** -- the outcomes depend on driver version, GPU model, and Kubernetes version.

## Cluster Configuration

All tests run on a cluster with **3 MIG devices** across 2 physical A100-PCIE-40GB GPUs:

| Device Name | Parent GPU | MIG Profile | SMs | Memory |
|---|---|---|---|---|
| `gpu-0-mig-9-4-4` | GPU-0 | 3g.20gb | 42 | ~20096 MiB |
| `gpu-0-mig-5-0-4` | GPU-0 | 4g.20gb | 56 | ~20096 MiB |
| `gpu-1-mig-0-0-8` | GPU-1 | 7g.40gb | 98 | ~40320 MiB |

All devices are published via a single ResourceSlice with `deviceClassName: mig.nvidia.com`.

## Core Concepts

- **MPS Thread Percentage**: `defaultActiveThreadPercentage` in GpuConfig controls how many SMs a client process can use. MPS does not strictly enforce this as a hard cap in all cases.
- **Pinned Device Memory Limit**: `defaultPinnedDeviceMemoryLimit` sets a per-client VRAM ceiling. Exceeding it may cause `cudaErrorMemoryAllocation`.
- **Shared ResourceClaim**: Multiple pods referencing the same ResourceClaim share a single MIG device via MPS.
- **Multiple ResourceClaims per Pod**: A pod can reference multiple claims, potentially spanning multiple MIG devices (even on the same physical GPU).

## Test 11.1: MPS Oversubscription

### 11.1a -- SM Oversubscription

| Property | Value |
|---|---|
| File | `manifests/module11/11.1a-sm-oversub.yaml` |
| Setup | 1 ResourceClaim (MPS, 50% threads), 3 Pods sharing it |
| Target | MIG device via `mig.nvidia.com` |
| Total thread request | 150% (3 x 50%) |

**Design**: Three pods share a single MIG device via one MPS-enabled ResourceClaim. The claim uses `defaultActiveThreadPercentage: 50`.

**Expected behavior**:
- The scheduler schedules all 3 pods, since DRA treats the claim as a single shared device.
- MPS `ActiveThreadPercentage` is a per-daemon setting, not per-client. All 3 pods share the same 50% limit cooperatively.
- No hard enforcement of per-pod SM limits.

**Actual Results**:
- All 3 pods were scheduled and reached Running state successfully.
- The claim was allocated to `gpu-0-mig-9-4-4` (3g.20gb, 42 SMs) and shared by all 3 pods via MPS.
- `nvidia-smi` query returned `[Insufficient Permissions]` for memory/utilization fields -- expected for MIG devices under MPS (nvidia-smi cannot query per-MIG-client stats).
- **Conclusion**: The scheduler does **not** enforce per-pod SM thread limits on MIG devices. `defaultActiveThreadPercentage` is a per-daemon setting applied to the MPS control daemon, and all clients share the same limit cooperatively. 3 x 50% = 150% is allowed because the scheduler sees one shared ResourceClaim, not three separate requests. The behavior is identical to full-GPU MPS: oversubscription is permitted.

### 11.1b -- VRAM Oversubscription

| Property | Value |
|---|---|
| File | `manifests/module11/11.1b-vram-oversub.yaml` |
| Setup | 1 ResourceClaim (MPS, 8Gi pinned memory limit), 3 Pods each allocating 8Gi |
| Target | MIG device via `mig.nvidia.com` |
| Total VRAM request | 24 GiB (on a ~20 GiB MIG slice) |

**Design**: Three pods share a MIG device with `defaultPinnedDeviceMemoryLimit: 8Gi`. Each pod compiles and runs a CUDA C program that queries `cudaMemGetInfo` and attempts to allocate 8 GiB of VRAM via `cudaMalloc`.

**Expected behavior**:
- All 3 pods are scheduled (scheduler sees one shared claim).
- The `pinnedDeviceMemoryLimit` is per-MPS-client. Each pod gets an 8 GiB ceiling.
- Since the MIG device has ~20 GiB physical VRAM and 3 x 8 GiB = 24 GiB, later allocations should fail with `cudaErrorMemoryAllocation` if all attempt max allocation simultaneously.

**Actual Results**:
- All 3 pods were scheduled and started Running on `gpu-0-mig-9-4-4` (3g.20gb, ~20096 MiB).
- MPS control daemon was started by the DRA driver with:
  - `set_default_active_thread_percentage 50`
  - `set_default_device_pinned_mem_limit MIG-... 8192M`
- `CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps` was set in each pod, confirming MPS was active.
- CUDA stress test results (each pod attempts `cudaMalloc(8192 MiB)`):
  - **Pod 2**: `free=19667 MiB` → allocated 8192 MiB **successfully**
  - **Pod 3**: `free=11475 MiB` → allocated 8192 MiB **successfully**
  - **Pod 1**: `free=3283 MiB` → allocated 8192 MiB **FAILED** (`cudaErrorMemoryAllocation`, code 2)
- `cudaMemGetInfo` reported `total=20096 MiB` for all pods -- the full MIG device physical memory, **not** the 8 GiB per-client limit.
- **Key findings**:
  1. **`set_default_device_pinned_mem_limit` on MIG does NOT virtualize `cudaMemGetInfo`**: Unlike full-GPU MPS where `cudaMemGetInfo` reports the per-client limit as available memory, on MIG devices it reports physical MIG memory. This is a significant behavioral difference between full-GPU MPS and MIG MPS.
  2. **Physical memory exhaustion causes OOM, not per-client limit**: The OOM occurred because Pod 2 + Pod 3 consumed ~16384 MiB of the ~20096 MiB physical MIG memory, leaving only ~3283 MiB for Pod 1. The 8192M per-client limit was not the binding constraint.
  3. **Oversubscription is allowed at the scheduler level**: The scheduler scheduled all 3 pods (total 24 GiB > 20 GiB physical) without error. The failure only occurred at CUDA runtime.
  4. **Race condition matters**: Pod execution order determines which pods succeed. The first two pods to call `cudaMalloc` succeed; the third fails.

## Test 11.2: Multi-Device MPS per Pod

### 11.2a -- Equal Split (2 MIG slices, both MPS)

| Property | Value |
|---|---|
| File | `manifests/module11/11.2a-dual-gpu-equal.yaml` |
| Setup | 2 ResourceClaims (both MPS 50%), 1 Pod |
| Target | 2 different MIG devices via `mig.nvidia.com` |

**Design**: One pod references two claims, both targeting `mig.nvidia.com` with MPS 50%. DRA must allocate each claim to a different MIG device (one-claim-one-device constraint).

**Expected behavior**:
- The pod sees both MIG devices.
- Both claims are allocated to different MIG slices.
- MPS daemon is active.

**Actual Results**:

- **Pod scheduled and Running successfully.**
- Claims allocated: `m11-2a-claim-gpu0` -> `gpu-0-mig-9-4-4` (3g.20gb), `m11-2a-claim-gpu1` -> `gpu-0-mig-5-0-4` (4g.20gb).
- Both MIG slices are on the **same physical GPU** (GPU-0). DRA correctly allocates two different MIG devices to satisfy the two claims.
- `nvidia-smi -L` showed: `GPU 0: NVIDIA A100-PCIE-40GB`, `MIG 3g.20gb Device 0`, `MIG 4g.20gb Device 1`.
- `CUDA_VISIBLE_DEVICES` was empty (Kind CDI limitation -- `NVIDIA_VISIBLE_DEVICES=void`), but the pod could see the MIG devices via `nvidia-smi`.
- **Key finding**: DRA successfully allocates two different MIG slices (even from the same physical GPU) to a single pod with MPS sharing. Each claim gets a distinct MIG device, respecting the one-claim-one-device constraint. The scheduler does not restrict multiple MIG claims from the same parent GPU.

### 11.2b -- Asymmetric Split (MIG exclusive + MIG MPS)

| Property | Value |
|---|---|
| File | `manifests/module11/11.2b-dual-gpu-asymmetric.yaml` |
| Setup | Claim 1: exclusive (MIG). Claim 2: MPS 30% (MIG). |
| Target | 2 different MIG devices via `mig.nvidia.com` |

**Design**: Tests mixing exclusive and MPS access in one pod across different MIG devices:
- Claim 1: `mig.nvidia.com`, no sharing config (exclusive)
- Claim 2: `mig.nvidia.com`, MPS at 30%

**Expected behavior**:
- Pod sees both MIG devices.
- One device is exclusively owned; the other runs through MPS with 30% thread limit.

**Actual Results**:

- **Pod scheduled and Running successfully.**
- Claims allocated: `m11-2b-claim-exclusive` -> `gpu-0-mig-9-4-4` (3g.20gb), `m11-2b-claim-mps` -> `gpu-0-mig-5-0-4` (4g.20gb).
- Both MIG slices are again from the same physical GPU (GPU-0).
- `CUDA_VISIBLE_DEVICES` was empty (Kind CDI limitation).
- `nvidia-smi -L` output was truncated in pod logs but the pod started successfully.
- **Key finding**: When a pod has both an exclusive claim and an MPS claim on different MIG devices, the DRA driver schedules the pod successfully. Both MIG slices are accessible. The interaction between exclusive and MPS modes at the pod level (whether MPS daemon is started or suppressed) requires further investigation with actual CUDA workloads to determine if the MPS configuration on the second claim takes effect.
- **Implication**: Unlike the previous GPU+MIG test (where exclusive mode on a full GPU suppressed MPS entirely), MIG-only configurations may behave differently because each MIG device is an independent compute unit.

## How to Run

```bash
# From the workshop root
./scripts/phase3/module11/run-11-1-oversubscription.sh
./scripts/phase3/module11/run-11-2-multi-gpu-mps.sh
```

Both scripts are idempotent (cleanup at start) and source `ensure-ready.sh`.

## Summary

| Test | What it verifies | Key question | Result |
|---|---|---|---|
| 11.1a | SM thread oversubscription on MIG | Does MPS/scheduler allow total thread% > 100%? | **Yes** -- scheduler allows it; thread% is per-daemon, not per-client |
| 11.1b | VRAM oversubscription on MIG | Does pinnedDeviceMemoryLimit cause OOM? | **Yes** -- 2/3 pods succeed, 1 OOM; physical memory exhaustion (not per-client limit) is the binding constraint on MIG |
| 11.2a | Multi-MIG MPS (equal, both MPS) | Can one pod use MPS on 2 MIG slices? | **Yes** -- both claims allocated (even from same physical GPU), pod runs successfully |
| 11.2b | Multi-MIG MPS (asymmetric) | Can one pod mix exclusive MIG + MPS MIG? | **Yes** -- both claims allocated and pod runs; MPS interaction behavior TBD |

## Analysis

### Key Insights

1. **`GpuConfig` vs `MigDeviceConfig`**: The DRA driver uses different config types for full GPUs and MIG devices. Using `kind: GpuConfig` with `mig.nvidia.com` devices causes the driver to silently fall back to `DefaultMigDeviceConfig()` (TimeSlicing, no MPS). **You must use `kind: MigDeviceConfig`** for MIG devices to enable MPS sharing. The driver does not log a warning for this mismatch.

2. **MPS memory limit behavior differs on MIG vs full GPU**: On full GPUs, `set_default_device_pinned_mem_limit` virtualizes `cudaMemGetInfo` so each MPS client sees only its allocated portion. On MIG devices, `cudaMemGetInfo` still reports the **full MIG physical memory** (e.g., 20096 MiB), and the per-client limit appears to be not enforced at the `cudaMemGetInfo` level. OOM occurs only when physical MIG memory is exhausted.

3. **MPS oversubscription is always allowed at the scheduler level**: The DRA scheduler treats a shared ResourceClaim as a single allocation unit. It does not sum up per-client thread percentages or memory limits. Oversubscription is only detected (and possibly rejected) at CUDA runtime.

4. **MIG devices behave as independent compute units for DRA**: Two claims targeting `mig.nvidia.com` get allocated to two different MIG slices, even when both slices reside on the same physical GPU. This is a useful property for workload isolation within a single GPU.

5. **`nvidia-smi` limitations on MIG + MPS**: When running inside a MIG-backed MPS container, `nvidia-smi --query-gpu` returns `[Insufficient Permissions]` for memory and utilization fields. This is an nvidia-smi limitation, not a DRA issue. Use `DCGM` or CUDA runtime APIs for per-MIG-client monitoring.

6. **Kind CDI limitation**: `CUDA_VISIBLE_DEVICES` is empty in all tests due to Kind's CDI integration. Pods still see the correct devices via `nvidia-smi -L`. This is a known Kind limitation, not a DRA or MPS issue.

7. **Scheduling vs. runtime enforcement gap**: The DRA scheduler is capacity-unaware for MPS parameters. It schedules pods based on device availability (is the claim allocated?), not on whether the total MPS resource requests (thread%, VRAM) fit within physical limits. This gap is by design -- MPS parameters are opaque driver config, not schedulable quantities. KEP-5075 (Consumable Capacity) aims to address this in the future.
