# Troubleshooting Guide

This guide compiles common issues encountered during the DRA Workshop Phase 1.

## 1. Driver Not Registered / ContainerCreating Stuck
**Symptoms**:
- Pod stuck in `ContainerCreating` or `Pending`.
- `kubectl describe pod` shows `FailedPrepareDynamicResources`: `DRA driver gpu.nvidia.com is not registered`.

**Root Cause**:
- The NVIDIA Driver Plugin (Kubelet Plugin) failing to register with Kubelet via the socket.
- Frequently happens after Kind Node restarts or aggressive pod deletions.

**Solution**:
1.  **Restart the Node Container** (Reset everything):
    ```bash
    docker restart workshop-dra-control-plane
    ```
2.  **Wait for Node Ready**:
    ```bash
    kubectl wait --for=condition=Ready node/workshop-dra-control-plane --timeout=60s
    ```
3.  **Ensure In-Cluster MPS is running**:
    ```bash
    docker exec workshop-dra-control-plane nvidia-cuda-mps-control -d
    ```
4.  **Restart Driver Pods**:
    ```bash
    kubectl delete pod -n nvidia-system --all
    ```

## 2. MPS: "Connection Refused" or Pipe Not Found
**Symptoms**:
- Module 4 fails with `❌ Failed to communicate with MPS Daemon`.
- `echo ps | nvidia-cuda-mps-control` returns nothing or error inside the Pod.

**Root Cause**:
- **In-Cluster MPS Daemon** is dead inside the Node.
- `/dev/shm` is not properly mounted (IPC isolation).

**Solution**:
1.  **Check Daemon inside Node** (Not Host!):
    ```bash
    docker exec workshop-dra-control-plane ps aux | grep mps
    ```
    If missing, start it:
    ```bash
    docker exec workshop-dra-control-plane nvidia-cuda-mps-control -d
    ```
2.  **Verify Shared Memory**:
    Ensure `hostIPC: true` is set in the Pod spec and `volumeMounts` includes `/tmp/nvidia-mps`.

## 3. CUDA Error: PTX JIT compiler library not found
**Symptoms**:
- Running CUDA benchmarks (Module 5) fails with this specific error.
- Occurs when running `nvcc` or JIT-compiling kernels inside the container.

**Root Cause**:
- The library `libnvidia-ptxjitcompiler.so` is missing from the Kind Node.
- CUDA requires this specifically for runtime compilation.

**Solution**:
1.  **Update Kind Config**: Ensure `scripts/common/helper-generate-kind-config.sh` includes `libnvidia-ptxjitcompiler.so.1`.
2.  **Rebuild Cluster**: You must destroy and recreate the cluster to apply the new mount.
    ```bash
    ./scripts/phase1/run-module1-setup-kind.sh
    ```

## 4. Kind Cluster Creation Failed
**Symptoms**:
- `run-module1-setup-kind.sh` fails to detect libraries.

**Root Cause**:
- Host driver installation is non-standard (e.g., Runfile instead of Deb).
- Libraries are in `lib` instead of `lib64` or `x86_64-linux-gnu`.

**Solution**:
- Check the output of the generation script.
- Manually edit `scripts/common/helper-generate-kind-config.sh` to add your specific library paths to the `TARGETS` array.
