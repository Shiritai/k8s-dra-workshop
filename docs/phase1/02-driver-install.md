# Module 2: NVIDIA DRA Driver Installation

## 1. Overview
The **NVIDIA DRA Driver** (Dynamic Resource Allocation) is the brain of this operation. Unlike the legacy "Device Plugin" which simply advertises an integer count of GPUs, the DRA driver manages GPUs as complex objects with attributes (memory, compute capability, topology).

## 2. Component Architecture
When installed, the driver deploys several components:
1.  **DRA Controller**: Runs in the Control Plane. Handles the binding logic (which claim gets which GPU).
2.  **Kubelet Plugin (Node Agent)**: Runs on every Node. Discovers local GPUs using CDI and publishes them as `ResourceSlices`.

## 3. Installation Guide

We use Helm for deployment. The script encapsulated the complexity:

```bash
./scripts/phase1/run-module2-install-driver.sh
```

### Critical Helm Options
We use specific experimental flags required for the current "Structured Parameters" model of DRA.

| Flag                          | Value  | Purpose                                                                                                                                   |
| :---------------------------- | :----- | :---------------------------------------------------------------------------------------------------------------------------------------- |
| `gpuResourcesEnabledOverride` | `true` | **Critical**. Enables the modern DRA APIs (Structured Parameters). Without this, the driver falls back to legacy modes or fails to start. |
| `kubeletPlugin.enabled`       | `true` | Deploys the Node Agent responsible for `ResourceSlice` creation.                                                                          |

## 4. Verification: The ResourceSlice

The **ResourceSlice** is the proof of life. It is a Custom Resource Definition (CRD) that represents a chunk of available hardware.

**Command:**
```bash
kubectl get resourceslices
```

**Understanding the Object:**
If you inspect the JSON output (`kubectl get resourceslices -o json`), you will see:

```json
{
    "apiVersion": "resource.k8s.io/v1alpha2",
    "kind": "ResourceSlice",
    "metadata": { ... },
    "spec": {
        "driver": "gpu.nvidia.com",
        "pool": {
            "name": "workshop-dra-control-plane",
            "generation": 1,
            "resourceSliceCount": 1
        },
        "devices": [
            {
                "name": "gpu-0",
                "basic": {
                    "attributes": {
                        "index": 0,
                        "model": "NVIDIA GeForce RTX 4090",
                        "memory": "24564MB"
                    }
                }
            }
        ]
    }
}
```
*Note: The actual attributes depend on the driver version.*

## 5. Troubleshooting

### "No ResourceSlices found"
1.  **Check Pod Status**:
    ```bash
    kubectl get pods -n nvidia-system
    ```
    Ensure `nvidia-dra-driver-kubelet-plugin-*` is **Running**, not `Error` or `CrashLoopBackOff`.

2.  **Check Logs**:
    ```bash
    kubectl logs -n nvidia-system -l app.kubernetes.io/name=nvidia-dra-driver-kubelet-plugin -c kubelet-plugin
    ```
    *   **"CDI spec not found"**: Indicates Module 0 (Prerequisites) failed.
    *   **"NVML initialization failed"**: Indicates Module 1 (Kind Setup) mounts are wrong or missing libraries.

## 6. Resources
- [KEP-4381: DRA Structured Parameters](https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/4381-dra-structured-parameters)
- [NVIDIA DRA Driver GitHub](https://github.com/NVIDIA/k8s-dra-driver)
