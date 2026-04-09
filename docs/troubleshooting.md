# Troubleshooting Guide

This document summarizes common issues and solutions encountered during the DRA Workshop.
Ordered by severity—from the most common "Stuck in ContainerCreating" to less frequent environment issues.

---

## 1. Pod Stuck in ContainerCreating (Expired Plugin Socket)

**Symptoms**:
- Pod scheduled successfully (`Scheduled` in Events), but stays in `ContainerCreating` forever.
- `kubectl describe pod` shows no further events, or error: `DRA driver gpu.nvidia.com is not registered`.
- Often happens after running multiple modules consecutively or creating/deleting many ResourceClaims.

**Root Cause**:
Kubelet communicates with the DRA plugin via a Unix socket, relying on `fsnotify` to monitor the `/var/lib/kubelet/plugins/` directory. In Kind environments, after multiple claim creations and deletions, `fsnotify` may lose track of the plugin socket. At this point, kubelet reports no error, but the `PrepareResources` RPC for new Pods fails silently.

**Solution**—Must be in order, kubelet first, then plugin:
```bash
# 1. Restart kubelet (it will automatically respawn after being killed in Kind)
docker exec workshop-dra-control-plane pkill -x kubelet

# 2. Wait for API server to recover
sleep 20
until kubectl get nodes &>/dev/null; do sleep 5; done

# 3. Restart DRA plugin (re-registers the socket with kubelet)
kubectl rollout restart daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin
kubectl rollout status daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin --timeout=120s
```

**Why the order matters**:
- Restarting only the plugin: kubelet's `fsnotify` is already broken and won't detect the new socket.
- Restarting only kubelet: the old socket file hasn't changed, the connection might remain stale.
- Kubelet then plugin: `fsnotify` resets + new socket registers, refreshing both ends.

**Prevention**: `run_all.sh` performs this refresh automatically before Phase 3. If "ContainerCreating" persists when running modules individually, execute the three steps above manually.

> **Note**: Kind does not use systemd, so `systemctl restart kubelet` is ineffective; `pkill` must be used.

---

## 2. vLLM Inference Failure (Image & GPU Architecture Incompatibility)

**Symptoms**:
- vLLM health check (`/health`) passes, but actual inference returns HTTP 500:
  ```json
  {"error":{"message":"EngineCore encountered an issue.","type":"InternalServerError","code":500}}
  ```
- Logs show `cudaErrorNoKernelImageForDevice` or `no kernel image is available`.
- `TRITON_ATTN` fallback allows the server to start, but it crashes during the `penalties.py` stage during inference.

**Root Cause**:
`vllm/vllm-openai:latest` (v0.8+) has removed pre-compiled CUDA kernels for `sm_80` (Ampere), supporting only `sm_89/sm_90` (Ada/Hopper) and later. While `--attention-backend TRITON_ATTN` covers JIT compilation for the Attention kernel, other modules like sampling and penalties still require pre-compiled CUDA extensions.

**Solution**—Choose the image based on your GPU architecture:

| GPU | Compute Capability | Recommended Image |
|-----|-------------------|-------------------|
| A100 / A30 (Ampere) | 8.0 | `vllm/vllm-openai:v0.6.6.post1` |
| L40S / RTX 4090 (Ada) | 8.9 | `vllm/vllm-openai:latest` |
| H100 / H200 (Hopper) | 9.0 | `vllm/vllm-openai:latest` |
| RTX 5090 (Blackwell) | 12.0 | `vllm/vllm-openai:latest` ✅ Verified |

Modify the `image` field in `manifests/module6/demo-vllm.yaml`, or use `sed` to replace it in a script:
```bash
# For A100 environment
sed -i 's|vllm/vllm-openai:latest|vllm/vllm-openai:v0.6.6.post1|' manifests/module6/demo-vllm.yaml
```

---

## 3. Helm Upgrade Conflict (Field Manager Conflict)

**Symptoms**:
- `run-module2-install-driver.sh` fails:
  ```
  UPGRADE FAILED: conflict occurred while applying object ...
  Apply failed with 1 conflict: conflict with "kubectl-patch" using apps/v1:
  .spec.template.spec.containers[name="gpus"].args
  ```

**Root Cause**:
The DRA DaemonSet args were previously modified using `kubectl patch` (e.g., adding a feature gate). Kubernetes Server-Side Apply recorded `kubectl-patch` as the field manager for that field. Subsequent Helm upgrades fail when trying to take over the same field.

**Solution**—Force Helm to take over:
```bash
# Method 1: Uninstall and reinstall Helm chart
helm uninstall nvidia-dra-driver -n nvidia-system
# Then re-run run-module2-install-driver.sh

# Method 2: Manually remove the conflicting field manager without reinstallation
kubectl get daemonset -n nvidia-system nvidia-dra-driver-gpu-kubelet-plugin -o json | \
  jq '.metadata.managedFields |= map(select(.manager != "kubectl-patch"))' | \
  kubectl replace -f -
```

**Prevention**: Avoid direct `kubectl patch` on DRA driver resources. If feature gate modification is needed, use the patch method in `scripts/phase2/run-module7-consumable-capacity.sh` (which includes `--force-conflicts`).

---

## 4. Phase 3 MIG Module Failure (Insufficient MIG Configuration)

**Symptoms**:
- Module 10.1 Case C (3g.20gb) and Case D (4g.20gb) Pods stuck in `Pending`:
  ```
  FailedScheduling: 0/1 nodes are available: 1 cannot allocate all claims.
  ```
- Only `7g.40gb` exists in `ResourceSlice`, other profiles are missing.

**Root Cause**:
The GPU's MIG configuration does not match the requirements of Phase 3. Module 10.x requires at least two MIG instances: `3g.20gb` and `4g.20gb`.

**Solution**:
```bash
# Requires sudo privileges
sudo scripts/common/mig-reconfig.sh mig
```

This will:
1. Enable MIG mode on GPU 0 (if not already enabled).
2. Create two instances: `3g.20gb + 4g.20gb`.
3. Restart kubelet and the DRA plugin to update `ResourceSlice`.

**Verification**:
```bash
kubectl get resourceslices -o json | \
  jq -r '.items[].spec.devices[] | select(.attributes.type.string == "mig") | "\(.name) \(.attributes.profile.string)"'
```
You should see `3g.20gb` and `4g.20gb` (if there is a second GPU, `7g.40gb` might also be present).

> **Note**: RTX series (e.g., RTX 5090) do not support MIG; Phase 3 will be skipped automatically.

---

## 5. CUDA Error: PTX JIT compiler library not found

**Symptoms**:
- Execution of `nvcc` or JIT compilation of CUDA kernels fails inside the container.
- Error message: `PTX JIT compiler library not found`.

**Root Cause**:
The `libnvidia-ptxjitcompiler.so` is missing in the Kind node. Kind bind-mounts host NVIDIA libraries into the container. If this file is missing from `extraMounts` in `kind-config.yaml`, errors occur.

**Solution**:
1. Ensure the `TARGETS` array in `scripts/common/helper-generate-kind-config.sh` includes `libnvidia-ptxjitcompiler.so.1`.
2. Rebuild the cluster:
   ```bash
   ./scripts/common/run-teardown.sh
   ./scripts/phase1/run-module1-setup-kind.sh
   ```

---

## 6. Kind Cluster Creation Failure (Library Path Detection)

**Symptoms**:
- `run-module1-setup-kind.sh` fails to detect NVIDIA libraries.
- Error similar to: `Cannot find libcuda.so`.

**Root Cause**:
Host driver installation is non-standard (e.g., using a Runfile instead of Deb/RPM), placing libraries in unexpected paths (e.g., `lib` instead of `lib64` or `x86_64-linux-gnu`).

**Solution**:
```bash
# Find the actual path
find / -name "libcuda.so*" 2>/dev/null

# Manually edit helper-generate-kind-config.sh to add the path to TARGETS
```

---

## 7. nvidia-ctk Not Installed (CDI Warning)

**Symptoms**:
- Module 0 environment check shows:
  ```
  ⚠️  nvidia-ctk not found
  ⚠️  NVIDIA CTK CDI config issue detected
  ```

**Root Cause**:
NVIDIA Container Toolkit (`nvidia-ctk`) is not installed on the host.

**Impact**: **Non-fatal**. The DRA driver generates its own CDI configuration inside the Kind node and does not depend on `nvidia-ctk` on the host. This warning only affects host-level CDI verification tools.

**Solution** (Optional):
```bash
# For Ubuntu/Debian
sudo apt install nvidia-container-toolkit

# Or follow official NVIDIA documentation for installation
```

---

## Quick Diagnosis Flow

```
Pod Stuck?
  ├── ContainerCreating → Issue 1 (Expired plugin socket)
  ├── Pending + "cannot allocate all claims"
  │     ├── Are there devices in ResourceSlice? → kubectl get resourceslices
  │     │     └── None → Restart plugin (Issue 1, Step 3)
  │     ├── Incorrect MIG profile? → Issue 4
  │     └── Only 1 GPU? → Expected behavior (Exclusive allocation)
  └── Running but Application Fails
        └── vLLM 500 error → Issue 2 (Image incompatibility)
```
