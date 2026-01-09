# Module 2: NVIDIA DRA Driver Installation

With the environment ready and Kind cluster running (with MPS support), we now deploy the NVIDIA DRA Driver. This driver is responsible for discovering GPU resources and publishing them via the new **ResourceSlice** API.

## 1. Installation
Run the automated script:
```bash
./scripts/phase1/run-module2-install-driver.sh
```

### Under the Hood (Helm Command)
The script executes:
```bash
helm upgrade -i nvidia-dra-driver nvidia/nvidia-dra-driver-gpu \
  --namespace nvidia-system \
  --create-namespace \
  --set gpuResourcesEnabledOverride=true \
  --set kubeletPlugin.enabled=true \
  --wait
```
- **`gpuResourcesEnabledOverride=true`**: Required for enabling the structured parameters feature (Key for DRA).
- **`kubeletPlugin.enabled=true`**: Ensures the Node Agent (plugin) runs on every node to register devices.

## 2. Verification (ResourceSlice)
The most critical indicator of success is the **ResourceSlice**. In DRA, devices are no longer just "counted" (like `nvidia.com/gpu: 1`); they are advertised as detailed objects.

Verify via:
```bash
kubectl get resourceslices
```

**Expected Output**:
```text
NAME                                           DRIVER                      POOL
workshop-dra-control-plane-gpu.nvidia.com...   gpu.nvidia.com              workshop-dra...
```
If you see a ResourceSlice, the driver has successfully:
1. Detected the GPU inside the Kind Node.
2. Communicated with the Kubelet.
3. Published the resource capability to the Control Plane.
