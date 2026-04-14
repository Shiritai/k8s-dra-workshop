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

**Compute Benchmark Results** (FMA stress test: N=16M, INNER_ITERS=64, 200 launches):

| Pod | Throughput (GFLOPS) | Elapsed (s) |
|---|---|---|
| Pod 1 | 1801.18 | 0.238 |
| Pod 2 | 1807.46 | 0.238 |
| Pod 3 | 1828.38 | 0.235 |

All 3 pods achieved nearly identical throughput (~1800 GFLOPS). This confirms:
1. `defaultActiveThreadPercentage: 50` is a **per-daemon ceiling**, not per-client. All 3 clients share the same MPS daemon and the same 50% SM limit cooperatively.
2. The benchmark runs were effectively serialized by the MPS scheduler (each ~0.24s), so all pods saw the same throughput rather than degraded performance from true concurrent contention.
3. **Conclusion**: The scheduler does **not** enforce per-pod SM thread limits. 3 × 50% = 150% is allowed because the scheduler sees one shared ResourceClaim, not three separate requests.

### 11.1b -- Server-Side Memory Limit Verification

| Property | Value |
|---|---|
| File | `manifests/module11/11.1b-server-limit-test.yaml` |
| Setup | 1 ResourceClaim (MPS, 8Gi pinned memory limit, 50% threads), 3 Pods with asymmetric allocation sizes |
| Target | MIG device via `mig.nvidia.com` |
| Pod allocation sizes | Pod 1: 6 GiB, Pod 2: 12 GiB, Pod 3: 6 GiB |

**Design**: Test whether `defaultPinnedDeviceMemoryLimit: 8Gi` is actually enforced on MIG devices. By using asymmetric allocation sizes (Pod 2 requests 12 GiB, exceeding the 8 GiB limit), we can distinguish server-side enforcement from physical OOM.

**Preliminary experiment** (`manifests/module11/11.1b-vram-oversub.yaml`, deprecated): 3 pods each allocating 8 GiB with 8 GiB limit — 2 succeed, 1 OOM. This was inconclusive because 8 GiB < 20 GiB physical, so success didn't prove the limit was working.

**Actual Results** (allocated to `gpu-0-mig-5-0-4`, 4g.20gb, ~20096 MiB):

| Pod | ALLOC_MIB | free before | Result | free after |
|---|---|---|---|---|
| Pod 2 | 12288 | 19760 MiB | **Success** (12 GiB allocated + memset OK) | 7472 MiB |
| Pod 1 | 6144 | 7368 MiB | **Success** (6 GiB allocated + memset OK) | 1224 MiB |
| Pod 3 | 6144 | 1114 MiB | **FAILED** (`cudaErrorMemoryAllocation`, code 2) | -- |

**Critical finding: `defaultPinnedDeviceMemoryLimit: 8Gi` is NOT enforced on MIG devices.**

Pod 2 successfully allocated 12 GiB of VRAM despite the 8 GiB per-client limit. This is 50% over the configured limit, and the allocation succeeded without error. The `cudaMemset` call also succeeded, confirming the memory was genuinely usable.

Pod 3 failed not because of the per-client limit, but because Pods 1 and 2 had already consumed ~18 GiB of the ~20 GiB physical MIG memory, leaving only ~1.1 GiB free.

**Conclusions**:
1. **`defaultPinnedDeviceMemoryLimit` has no effect on MIG devices**: The MPS daemon accepts the configuration (`set_default_device_pinned_mem_limit MIG-... 8192M`), but the CUDA runtime does not enforce it. A client can allocate far beyond the configured limit.
2. **`cudaMemGetInfo` reports full physical memory**: All clients see 20096 MiB total — the full MIG partition, not the 8 GiB per-client limit.
3. **Physical MIG memory is the only real constraint**: On MIG devices, the only hard limit is the physical memory of the MIG slice.
4. **Oversubscription is allowed at the scheduler level**: The scheduler scheduled all pods without error. Failure only occurred at CUDA runtime.
5. **Race condition matters**: Pod execution order determines which pods succeed (first-come-first-served).

### Root Cause Analysis: Why MPS Memory Limit Fails on MIG

Investigation of the DRA driver source code (`k8s-dra-driver-gpu v25.8.1`) reveals two compounding bugs:

**Bug 1 — Config timing (primary cause)**: In `templates/mps-control-daemon.tmpl.yaml`, the MPS daemon is started with `nvidia-cuda-mps-control -d` **before** sending `set_default_device_pinned_mem_limit`. Per [NVIDIA MPS docs](https://docs.nvidia.com/deploy/mps/appendix-tools-and-interface-reference.html): *"If there is already a server spawned, this command will only affect the **next** server."* If an MPS server auto-spawns after the daemon starts (before the limit command is sent), the memory limit only applies to the next server — not the active one.

**Bug 2 — EXCLUSIVE_PROCESS incompatibility**: `sharing.go:282` calls `setComputeMode("EXCLUSIVE_PROCESS")` on the parent GPU UUID. However, [NVIDIA MIG documentation](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/latest/) states: *"EXCLUSIVE_PROCESS mode is not supported when the GPU is in MIG mode."* This call silently fails on MIG-enabled GPUs. MPS memory limit enforcement depends on EXCLUSIVE_PROCESS mode to guarantee the MPS server is the sole GPU context owner.

**Note: `defaultActiveThreadPercentage` works because it is set via a different mechanism** — it controls the MPS control daemon's thread scheduling policy, which does not depend on EXCLUSIVE_PROCESS or config timing.

**Workarounds**:
- **Client-side env var**: Set `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=8192M` in the workload container. This is client-enforced (not server-enforced), but is the most reliable approach on MIG.
- **Fix the DRA driver template**: Send `set_default_device_pinned_mem_limit` **before** starting the MPS server, or use `set_device_pinned_mem_limit <PID>` after the server spawns.

**Source code references**:
- `k8s-dra-driver-gpu/cmd/gpu-kubelet-plugin/sharing.go:203-229` — `set_default_device_pinned_mem_limit` invocation
- `k8s-dra-driver-gpu/cmd/gpu-kubelet-plugin/sharing.go:282` — `setComputeMode("EXCLUSIVE_PROCESS")`
- `k8s-dra-driver-gpu/templates/mps-control-daemon.tmpl.yaml:37` — MPS daemon startup sequence

### 11.1c -- Client-Side MPS Memory Limit Workaround

| Property | Value |
|---|---|
| File | `manifests/module11/11.1c-client-limit-workaround.yaml` |
| Setup | 1 ResourceClaim (MPS, 4Gi pinned memory limit, 50% threads), 3 Pods with client-side env var |
| Target | MIG device via `mig.nvidia.com` |
| Workaround | `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=4096M` set in each pod's env |

**Design**: Since server-side `defaultPinnedDeviceMemoryLimit` is not enforced on MIG (see root cause above), this test uses the **client-side** env var `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=4096M` to enforce a 4 GiB per-client memory limit. Three pods share one MIG device:
- Pod 1: 4.5 GiB alloc (4608 MiB) — should fail (exceeds 4 GiB MPS client limit, but fits physically)
- Pod 2: 3 GiB alloc (3072 MiB) — should succeed (within 4 GiB limit)
- Pod 3: 3 GiB alloc (3072 MiB) — should succeed (within 4 GiB limit)

**Actual Results** (allocated to MIG 3g.20gb, ~20096 MiB physical):

| Pod | ALLOC_MIB | `cudaMemGetInfo` free | Result | Why |
|---|---|---|---|---|
| Pod 1 | 4608 | 4004 MiB | **FAILED** (code 2) | 4608 > 4004 MiB (MPS limit enforced) |
| Pod 2 | 3072 | 4004 MiB | **Success** (memset OK) | 3072 < 4004 MiB (within limit) |
| Pod 3 | 3072 | 4004 MiB | **Success** (memset OK) | 3072 < 4004 MiB (within limit) |

**Critical findings**:

1. **`CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` works on MIG**: The client-side env var successfully enforces per-client memory limits on MIG devices, unlike the server-side `defaultPinnedDeviceMemoryLimit`.
2. **`cudaMemGetInfo` is virtualized**: All 3 pods report `free=4004 MiB` (≈4096M limit minus ~92 MiB context overhead), **not** the physical ~19761 MiB. The client-side env var virtualizes the CUDA memory query to reflect the per-client limit.
3. **Pod 1 failure is MPS enforcement, not physical OOM**: The device has ~20 GiB physical memory, but Pod 1's 4.5 GiB request is rejected because it exceeds the 4 GiB client limit. This definitively proves MPS enforcement.
4. **Pods 2 and 3 coexist successfully**: Both allocate 3 GiB each (6 GiB total), well within both the per-client 4 GiB limit and the ~20 GiB physical limit. After allocation, each pod sees `free=932 MiB` remaining in its 4 GiB client window.

**Single-pod verification** (deployed separately on clean device): A single pod with `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=4096M` on a fresh MIG device saw `free=4004 MiB` (vs ~19761 MiB without the env var). 2 GiB allocation succeeded; 4 GiB allocation failed. This confirms the env var is the sole cause of the limit, independent of other pods.

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
- Claims allocated: `m11-2a-stress-mig0` → `gpu-0-mig-5-0-4` (4g.20gb, 56 SMs), `m11-2a-stress-mig1` → `gpu-1-mig-0-0-8` (7g.40gb, 98 SMs).
- The two MIG slices are on **different physical GPUs** (GPU-0 and GPU-1).
- `nvidia-smi` inside the pod confirmed both parent GPUs visible, with MIG devices listed.
- MPS control daemon was active (`CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps`).

**CUDA Benchmark Results** (SAXPY, 4M elements, 500 iterations):

| Metric | Value |
|---|---|
| CUDA device count | **1** (only `gpu-1-mig-0-0-8` 7g.40gb visible) |
| Reported SMs | 48 (~50% of 98, MPS-limited) |
| SAXPY throughput | 168.40 GFlop/s |

**Critical finding: Only 1 of the 2 allocated MIG devices is visible to CUDA.** Despite having 2 ResourceClaims allocated to 2 different MIG devices, `cudaGetDeviceCount()` returns 1. The DRA driver's CDI device injection with MPS exposes only one device to the CUDA runtime context. The MPS daemon binds to a single GPU/MIG device, and all MPS clients within that daemon see only that device.

- `nvidia-smi` sees both parent GPUs and all MIG devices (because it uses NVML directly, not CUDA), but the CUDA runtime only sees the MPS-managed device.
- **Key finding**: A single Pod cannot use CUDA to compute on 2 separate MPS-enabled MIG devices simultaneously. This is a fundamental MPS limitation — one MPS daemon manages one GPU/MIG device. To use multiple MIG devices with MPS, separate Pods (each with its own MPS daemon) are needed.

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
- Claims allocated: `m11-2b-stress-exclusive` → `gpu-0-mig-5-0-4` (4g.20gb, exclusive), `m11-2b-stress-mps30` → `gpu-1-mig-0-0-8` (7g.40gb, MPS 30%).
- The two MIG slices are on different physical GPUs.

**CUDA Benchmark Results** (SAXPY + Compute-heavy, 4M elements, 500 iterations):

| Metric | Value |
|---|---|
| CUDA device count | **1** (only `gpu-1-mig-0-0-8` 7g.40gb visible) |
| Reported SMs | 28 (~30% of 98, matching MPS 30% config) |
| SAXPY throughput | 95.13 GFlop/s (mem BW: 570.8 GB/s) |
| Compute throughput | 3224.41 GFlop/s |
| Free memory | 28850 / 40442 MiB |

**Key findings**:
1. **Same single-device limitation as 11.2a**: Only the MPS-configured claim's device is visible to CUDA. The exclusive claim's MIG device (`gpu-0-mig-5-0-4`) is not accessible via the CUDA runtime.
2. **MPS thread percentage is reflected in SM count**: The reported `multiProcessorCount` of 28 matches 30% of the 7g.40gb's 98 SMs, confirming MPS `defaultActiveThreadPercentage: 30` is applied.
3. **The exclusive claim is effectively wasted**: Since only the MPS device is visible to CUDA, the exclusive MIG device cannot be used for computation. This means mixing exclusive + MPS in a single Pod does NOT give access to both devices.
4. **MPS daemon takes precedence**: When both exclusive and MPS claims are in the same Pod, the DRA driver starts the MPS daemon for the MPS claim, and that daemon's device becomes the only CUDA-visible device.

**Implication**: To use an exclusive MIG device alongside an MPS-shared MIG device, they must be in separate Pods (or separate containers with distinct MPS pipe directories). Single-Pod multi-MIG with mixed sharing modes is not practical with the current DRA driver.

### Root Cause Analysis: Single-Device CUDA Visibility in Multi-Claim Pods

Both 11.2a and 11.2b show the same symptom: `cudaGetDeviceCount()` returns 1 despite 2 MIG devices being allocated. The root cause is a **CDI container path collision** in the DRA driver's MPS implementation, compounded by a fundamental MPS architecture constraint.

#### Evidence Chain

**1. CDI Spec Analysis**

Each MPS-enabled ResourceClaim generates a CDI spec with identical container-side mount paths. Examining the live CDI specs on the node (`/var/run/cdi/k8s.gpu.nvidia.com-claim_*.yaml`), every MPS claim contains:

```yaml
containerEdits:
  env:
    - CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
  mounts:
    - hostPath: /var/lib/kubelet/plugins/gpu.nvidia.com/mps/<claimUID>-<hash>/shm
      containerPath: /dev/shm          # <-- same for all claims
    - hostPath: /var/lib/kubelet/plugins/gpu.nvidia.com/mps/<claimUID>-<hash>/pipe
      containerPath: /tmp/nvidia-mps   # <-- same for all claims
```

The **host-side** paths are unique per claim (different `<claimUID>-<hash>` directories, each with its own MPS daemon). But the **container-side** paths are hardcoded to `/dev/shm` and `/tmp/nvidia-mps` for every claim.

**2. DRA Driver Source Code Confirmation**

In `k8s-dra-driver-gpu/cmd/gpu-kubelet-plugin/sharing.go`, the `GetCDIContainerEdits()` method (line 355-375) hardcodes the container paths:

```go
func (m *MpsControlDaemon) GetCDIContainerEdits() *cdiapi.ContainerEdits {
    return &cdiapi.ContainerEdits{
        ContainerEdits: &cdispec.ContainerEdits{
            Env: []string{
                fmt.Sprintf("CUDA_MPS_PIPE_DIRECTORY=%s", "/tmp/nvidia-mps"),  // hardcoded
            },
            Mounts: []*cdispec.Mount{
                {
                    ContainerPath: "/dev/shm",          // hardcoded
                    HostPath:      m.shmDir,
                },
                {
                    ContainerPath: "/tmp/nvidia-mps",   // hardcoded
                    HostPath:      m.pipeDir,
                },
            },
        },
    }
}
```

**3. Mount Collision Behavior**

When kubelet processes a pod with 2 MPS claims, it applies both CDI specs' mounts sequentially. Since both mount to `/tmp/nvidia-mps`, the **second bind mount overwrites the first** (standard Linux bind mount behavior). The container ends up connected to only one MPS daemon's pipe directory.

Similarly, `/dev/shm` is overwritten, so only one daemon's shared memory segment is accessible.

**4. MPS Daemon State**

Each claim gets its own MPS control daemon (separate Deployment in the `nvidia-system` namespace). The host-side directory structure confirms this:

```
/var/lib/kubelet/plugins/gpu.nvidia.com/mps/
├── <claim1-UID>-<hash>/pipe/   → MPS daemon for MIG device A
├── <claim2-UID>-<hash>/pipe/   → MPS daemon for MIG device B
```

Both daemons run correctly on the host, but only one is reachable from inside the container.

**5. NVIDIA MPS Architecture Constraint**

Even if the container path collision were resolved (e.g., by using per-claim subdirectories like `/tmp/nvidia-mps-0` and `/tmp/nvidia-mps-1`), a single process can only set one `CUDA_MPS_PIPE_DIRECTORY` environment variable. The CUDA runtime reads this variable once at initialization to determine which MPS daemon to connect to. A process cannot simultaneously use two MPS daemons.

To use N MPS-managed devices from a single process, all N devices would need to be served by a single MPS daemon with `CUDA_VISIBLE_DEVICES` listing all N device UUIDs. However, `nvidia-cuda-mps-control` only supports one GPU (or one MIG device) per daemon instance.

#### Summary of Root Causes

| Layer | Issue | Fixable? |
|---|---|---|
| **CDI spec generation** | Hardcoded `containerPath: /tmp/nvidia-mps` and `/dev/shm` causes mount collision when 2+ MPS claims exist in one pod | Yes (driver change needed) |
| **Environment variable** | `CUDA_MPS_PIPE_DIRECTORY` is a single value; cannot point to 2 daemons simultaneously | No (CUDA runtime limitation) |
| **MPS daemon architecture** | One `nvidia-cuda-mps-control` daemon manages exactly one GPU/MIG device | No (NVIDIA MPS design) |

The fundamental limitation is at the MPS architecture level: **one MPS daemon = one device = one `CUDA_MPS_PIPE_DIRECTORY`**. Even if the DRA driver fixed the CDI mount collision, a single CUDA process cannot multiplex across two MPS daemons. Multi-MIG-device computation via MPS requires separate processes (i.e., separate pods or separate containers with distinct `CUDA_MPS_PIPE_DIRECTORY` values).

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
| 11.1b | Server-side memory limit on MIG | Is `defaultPinnedDeviceMemoryLimit: 8Gi` enforced? | **No** -- 12 GiB allocation succeeds despite 8 GiB limit; server-side limit is not enforced on MIG |
| 11.1c | Client-side `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` | Does client-side env var enforce limits on MIG? | **Yes** -- 4.5 GiB rejected (4 GiB limit), 3 GiB succeeds; `cudaMemGetInfo` virtualized to client limit |
| 11.2a | Multi-MIG MPS (equal, both MPS) | Can one pod use CUDA on 2 MPS MIG slices? | **Scheduled yes, but CUDA sees only 1 device** -- MPS daemon binds to single device |
| 11.2b | Multi-MIG MPS (asymmetric) | Can one pod mix exclusive + MPS across MIG? | **Scheduled yes, but CUDA sees only MPS device** -- exclusive claim is wasted |

## Analysis

### Key Insights

1. **`GpuConfig` vs `MigDeviceConfig`**: The DRA driver uses different config types for full GPUs and MIG devices. Using `kind: GpuConfig` with `mig.nvidia.com` devices causes the driver to silently fall back to `DefaultMigDeviceConfig()` (TimeSlicing, no MPS). **You must use `kind: MigDeviceConfig`** for MIG devices to enable MPS sharing. The driver does not log a warning for this mismatch.

2. **MPS memory limit is ineffective on MIG (DRA driver bug)**: `defaultPinnedDeviceMemoryLimit` is silently ignored on MIG devices — a client configured with 8 GiB limit can allocate 12 GiB without error. Root cause: (a) the DRA driver's MPS daemon template sends `set_default_device_pinned_mem_limit` **after** starting the daemon (too late if server already spawned), and (b) `EXCLUSIVE_PROCESS` mode — required for full enforcement — is not supported on MIG-enabled GPUs. Workaround: use client-side `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` env var.

3. **MPS oversubscription is always allowed at the scheduler level**: The DRA scheduler treats a shared ResourceClaim as a single allocation unit. It does not sum up per-client thread percentages or memory limits. Oversubscription is only detected (and possibly rejected) at CUDA runtime.

4. **MIG devices behave as independent compute units for DRA**: Two claims targeting `mig.nvidia.com` get allocated to two different MIG slices, even when both slices reside on the same physical GPU. This is a useful property for workload isolation within a single GPU.

5. **`nvidia-smi` limitations on MIG + MPS**: When running inside a MIG-backed MPS container, `nvidia-smi --query-gpu` returns `[Insufficient Permissions]` for memory and utilization fields. This is an nvidia-smi limitation, not a DRA issue. Use `DCGM` or CUDA runtime APIs for per-MIG-client monitoring.

6. **MPS daemon = single-device CUDA context**: When MPS is configured on a ResourceClaim, the DRA driver starts one MPS daemon per MIG device. A Pod with 2 MPS claims gets 2 MPS daemons, but the CUDA runtime only connects to one. `cudaGetDeviceCount()` returns 1, not 2. This is a fundamental MPS architecture constraint — to use N MIG devices concurrently via CUDA, use N separate Pods.

7. **Scheduling vs. runtime enforcement gap**: The DRA scheduler is capacity-unaware for MPS parameters. It schedules pods based on device availability (is the claim allocated?), not on whether the total MPS resource requests (thread%, VRAM) fit within physical limits. This gap is by design -- MPS parameters are opaque driver config, not schedulable quantities. KEP-5075 (Consumable Capacity) aims to address this in the future.
