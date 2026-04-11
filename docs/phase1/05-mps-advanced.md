# Module 5: DRA-Managed MPS Advanced (Experimental)

## 1. Overview

Module 5 demonstrates how to enforce MPS resource limits (SM thread percentage, memory) centrally via the **GpuConfig in the ResourceClaim**, rather than relying on per-Pod environment variables that users could modify or remove.

## 2. GpuConfig MPS Parameters

The `resource.nvidia.com/v1beta1` GpuConfig of the DRA Driver supports the following MPS configurations:

```yaml
sharing:
  strategy: MPS
  mpsConfig:
    defaultActiveThreadPercentage: 20        # SM computing power limit (%)
    defaultPinnedDeviceMemoryLimit: 1Gi      # Memory hard limit (resource.Quantity)
    defaultPerDevicePinnedMemoryLimit:       # Optional: per-device override
      "GPU-xxxx": 2Gi
```

### GpuConfig Parameters and CUDA Environment Variable Equivalents

| GpuConfig Field | Equivalent CUDA Env Var | Notes |
|-----------------|-------------------------|-------|
| `defaultActiveThreadPercentage: 20` | `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=20` | SM computing power limit, managed by Driver |
| `defaultPinnedDeviceMemoryLimit: 1Gi` | `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=1G` | Uses K8s `resource.Quantity` format |

### Key Finding: Memory Limit Enforcement

The DRA-managed `defaultPinnedDeviceMemoryLimit` constrains both pinned host memory and device memory allocation:

| Test | Result |
|------|--------|
| `cudaMalloc(100MB)` with limit=1Gi | ✅ Success |
| `cudaMalloc(2GB)` with limit=1Gi | ✅ **OOM Refusal** (limit enforced) |

## 3. Part A: Single Pod Resource Limits

### Manifest (`manifests/module5/demo-dra-mps-limits.yaml`)

```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: gpu-claim-dra-mps-limited
spec:
  devices:
    config:
    - opaque:
        driver: gpu.nvidia.com
        parameters:
          apiVersion: resource.nvidia.com/v1beta1
          kind: GpuConfig
          sharing:
            strategy: MPS
            mpsConfig:
              defaultActiveThreadPercentage: 20
              defaultPinnedDeviceMemoryLimit: 1Gi
    requests:
    - name: gpu-req
      exactly:
        count: 1
        deviceClassName: gpu.nvidia.com
---
apiVersion: v1
kind: Pod
metadata:
  name: dra-mps-limited
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-devel-ubuntu22.04
    command: ["sh", "-c", "nvidia-smi; sleep 3600"]
    resources:
      claims: [{name: gpu}]
  resourceClaims: [{name: gpu, resourceClaimName: gpu-claim-dra-mps-limited}]
```

Note that the Pod spec contains no MPS-related configuration at all.

### Verification Results

```
Claim config:
{
  "apiVersion": "resource.nvidia.com/v1beta1",
  "kind": "GpuConfig",
  "sharing": {
    "mpsConfig": {
      "defaultActiveThreadPercentage": 20,
      "defaultPinnedDeviceMemoryLimit": "1Gi"
    },
    "strategy": "MPS"
  }
}

CDI injected env var: CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
Allocating 100MB: ✅ succeeded
Allocating 2GB:   ✅ out of memory (limit enforced)
```

## 4. Part B: Multiple Pods Sharing a Claim

### Manifest (`manifests/module5/demo-dra-mps-shared.yaml`)

3 Pods sharing the same ResourceClaim, with each Pod limited to 30% SM:

```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: gpu-claim-dra-mps-shared
spec:
  devices:
    config:
    - opaque:
        driver: gpu.nvidia.com
        parameters:
          apiVersion: resource.nvidia.com/v1beta1
          kind: GpuConfig
          sharing:
            strategy: MPS
            mpsConfig:
              defaultActiveThreadPercentage: 30
    requests:
    - name: gpu-req
      exactly:
        count: 1
        deviceClassName: gpu.nvidia.com
```

Three Pods each reference `gpu-claim-dra-mps-shared`, and the Driver creates only one MPS daemon.

### Verification Results

```
dra-mps-s1: GPU 0: NVIDIA A100-PCIE-40GB (UUID: GPU-d675772b-...)
dra-mps-s2: GPU 0: NVIDIA A100-PCIE-40GB (UUID: GPU-d675772b-...)
dra-mps-s3: GPU 0: NVIDIA A100-PCIE-40GB (UUID: GPU-d675772b-...)
✅ 3 pods share the same GPU
```

## 5. Blind Scheduler Limitations

Since DRA-managed MPS uses opaque parameters, the Scheduler cannot see the MPS configuration. This means:

- The Scheduler assumes one GPU can only be allocated to one ResourceClaim.
- If you create 3 independent Claims (each with `sharing.strategy: MPS`), the Scheduler will not schedule them onto the same GPU.
- **Solution**: Have multiple Pods share the same ResourceClaim (as in the Part B pattern).

This limitation is expected to be resolved when the driver API is upgraded to support Named Resources (non-opaque).

## 6. Verification

```bash
./scripts/phase1/run-module5-mps-advanced.sh
```

## 7. Driver Source Code: How Limits Take Effect

The startup template for the MPS Control Daemon receives parameters from the GpuConfig:

```go
// cmd/gpu-kubelet-plugin/sharing.go
if config != nil && config.DefaultActiveThreadPercentage != nil {
    templateData.DefaultActiveThreadPercentage = fmt.Sprintf("%d", *config.DefaultActiveThreadPercentage)
}

if config != nil {
    limits, err := config.DefaultPerDevicePinnedMemoryLimit.Normalize(
        deviceUUIDs, config.DefaultPinnedDeviceMemoryLimit)
    templateData.DefaultPinnedDeviceMemoryLimits = limits
}
```

These parameters are rendered into the Deployment template of the MPS Control Daemon and take effect when the daemon starts. Resource limits are enforced at the MPS Server level, and all clients connecting to that daemon are constrained.

## 8. Resources
- [NVIDIA DRA GPU Driver - GpuConfig API](https://github.com/NVIDIA/k8s-dra-driver-gpu/blob/main/api/nvidia.com/resource/v1beta1/sharing.go)
- [NVIDIA MPS Resource Limits](https://docs.nvidia.com/deploy/mps/index.html#topic_5_1_1)
