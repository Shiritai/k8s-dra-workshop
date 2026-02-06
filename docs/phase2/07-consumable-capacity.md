# Module 7: Consumable Capacity (Shared Pool)

## Goal

Verify the **Consumable Resources** mechanism in Kubernetes DRA.
We will configure the GPU as a Shared Pool and verify:
1.  **Capacity Accounting**: Check if the Scheduler correctly deducts allocated memory capacity.
2.  **Shared Access**: Verify if multiple Pods can share the same GPU (within architectural limits).

## Environment Configuration

We use `GpuConfig` (v1beta1) to define the sharing strategy:

- **Sharing Strategy**: `MPS` (or `TimeSlicing`)
- **ResourceSlice**: Automatically published by the Driver.

### Manifest: `gpu-class-capacity.yaml`

```yaml
apiVersion: resource.k8s.io/v1
kind: DeviceClass
metadata:
  name: gpu-capacity.nvidia.com
spec:
  config:
  - opaque:
      driver: gpu.nvidia.com
      parameters:
        apiVersion: resource.nvidia.com/v1beta1
        kind: GpuConfig
        sharing:
          strategy: MPS
          mpsConfig:
            defaultActiveThreadPercentage: 100
```

## Steps

Run the automated script:

```bash
./scripts/phase2/run-module7-consumable-capacity.sh
```

### Expected Results

1.  **Driver Initialization**: The driver restarts and publishes the `ResourceSlice`.
2.  **Pod 1 (pod-small, 4Gi)**: Successfully scheduled and running (Running).
3.  **Pod 2 (pod-4gi, 4Gi)**: State is `Pending`.
4.  **Pod 4 (pod-overflow, 50Gi)**: State is `Pending`.

## 🔍 Deep Dive: Concurrency & Architecture Analysis

In our verification, Pod 1 successfully claimed 4GB with MPS enabled, but Pod 2 (`pod-4gi`) remained `Pending`.
Through source code analysis of `nvidia-dra-driver-source` and Scheduler behavior, we confirmed this is an **Architectural Limitation caused by Opaque Parameters**, not a configuration error.

### Root Cause: Opaque Constraint & Blind Scheduler

#### 1. The Mandatory Opaque Constraint (Source Code)
The current NVIDIA Driver (`v0.12.0` / `v25.8.1`) enforces a **hard check**.
We found the enforcement logic in `cmd/gpu-kubelet-plugin/device_state.go`:

```go
// cmd/gpu-kubelet-plugin/device_state.go
func GetOpaqueDeviceConfigs(...) {
    for _, config := range candidateConfigs {
        // Strict enforcement of Opaque Parameters
        if config.Opaque == nil {
             return nil, fmt.Errorf("only opaque parameters are supported by this driver")
        }
        // ...
    }
}
```

This limits us to **Opaque Parameters** as the *only* mechanism for dynamic configuration (MPS/TimeSlicing).

#### 2. The Blind Scheduler
- **The Problem**: Opaque parameters are a **Black Box** to the Kubernetes Scheduler.
- **Impact**: The Scheduler cannot read the capacity details (e.g., "TimeSlicing: 10 replicas") inside the opaque blob.
- **Fallback**: It falls back to **Counting Mode**, relying solely on the number of device items published in the `ResourceSlice` (1 Physical GPU = 1 Item).

#### 3. The Consequence: 1-to-1 Mapping Lock
- Once `pod-small` binds to `gpu-0`, the Scheduler considers the *entire* device item "Used" (1/1).
- When `pod-4gi` requests resources, the Scheduler sees "0 Items Available" (not "20GB Remaining").
- **Verdict**: Pod 2 is `Pending` due to `Insufficient Devices`.

### Engineering Challenges: A Debugging Journey

Beyond the architectural limits, we resolved two critical engineering issues during development:

#### 1. The Schema Barrier
Initially, following documentation to use `DeviceClassParameters` failed with `no kind "DeviceClassParameters" is registered`.
Auditing `api/nvidia.com/resource/v1beta1/register.go` confirmed that the driver only registers `GpuConfig`:

```go
// abstract source code
func addKnownTypes(scheme *runtime.Scheme) error {
    scheme.AddKnownTypes(SchemeGroupVersion,
        &GpuConfig{},       // ✅ Registered
        // DeviceClassParameters -> ❌ MISSING
    )
}
```

#### 2. Stability & Race Conditions
During rapid iteration, the Kubelet often reported `Driver not registered` after driver restarts.
**Solution**: We implemented **Robust Driver Restart Logic** in our automation scripts, enforcing a wait for `ResourceSlice` publication before scheduling workloads.

---

### Alternatives Analysis

Since native Consumable Capacity is blocked, here are the alternatives:

| Option | Description | Pros | Cons |
| :--- | :--- | :--- | :--- |
| **1. MIG (Static Slicing)** | Pre-partition GPU into physical slices (e.g., 7x 3g.20gb) using `mig-parted`. | **Hardware Isolation**, QoS Guarantee, Scheduler Visible. | Requires High-End GPUs (A100/H100), Inflexible. |
| **2. Host IPC (Hack Mode)** | Run Global Daemon on Node (as in Mod 4/5/6), Pods use `hostIPC: true`. | **Immediate Availability**, Supports Consumer GPUs, Flexible. | **Insecure**, Breaks Isolation, Anti-pattern. |
| **3. Structured Parameters** | Wait for K8s 1.31+ and NVIDIA Driver Structured Parameters support. | **Ultimate Solution**, Secure & Flexible. | **Immature** (Waiting Game). |

### Conclusion

This module confirms that **Consumable Capacity (Shared Pool)** is **not feasible** in the current Driver architecture.
The blocker is the **Mandatory Opaque Constraint**, which causes the **Blind Scheduler** effect.

**Recommendations**:
- **Short-term (Verify/Dev)**: Continue using **Host IPC Mode** (verified in Module 4/5/6) if sharing is required.
- **Long-term (Production)**: Wait for **Structured Parameters** (KEP-4381) support.

