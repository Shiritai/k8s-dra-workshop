# Module 0: Multi-Architecture Adaptation (x86_64 & AArch64)

This module provides a technical guide on how to adapt the Kubernetes DRA Workshop for both **x86_64** and **AArch64 (ARM64)** architectures. It addresses the fundamental challenges of hardware-software impedance mismatch, library path discovery, and initialization race conditions.

## 1. Problem Statement: The Architecture Gap

When porting high-performance computing (HPC) workloads from x86 to ARM, three critical barriers often emerge:

1.  **Library Path Discrepancy**: x86_64 libraries reside in `/usr/lib/x86_64-linux-gnu`, while AArch64 libraries are in `/usr/lib/aarch64-linux-gnu`. Hardcoded paths in scripts and Helm charts lead to "Library not found" errors.
2.  **NVML Initialization Sensitivity**: NVIDIA Management Library (NVML) initialization on ARM platforms can encounter race conditions during container pre-start checks within Kind/Docker environments.
3.  **Path Visibility in Distroless Containers**: Modern DRA drivers often use Distroless images, which lack `ldconfig` or standard linker search paths.

## 2. Solution: Dynamic Infrastructure Adaptation

We implemented a **Dynamic Detection** strategy across the workshop to ensure seamless execution on any host architecture.

### 2.1 Dynamic Library Discovery
All infrastructure scripts now include a `uname -m` check to identify the host architecture and map the correct library directory.

```bash
ARCH=$(uname -m)
LIB_DIR="x86_64-linux-gnu"
if [ "$ARCH" = "aarch64" ]; then
    LIB_DIR="aarch64-linux-gnu"
fi
```

### 2.2 Mount Path Hijacking (Kind Node)
During the Kind cluster setup (`Module 1`), we dynamically mount the host's NVIDIA libraries into the Kind node at their native architectural paths. This ensures that `nvidia-smi` and other tools inside the node work out-of-the-box.

### 2.3 Driver Initialization Patching (`skipPrestart`)
To prevent the "Initialization Death Loop" on AArch64, we introduced the `skipPrestart` toggle in the DRA Driver's Helm chart. 

*   **x86_64**: Defaults to `false` (standard NVIDIA behavior).
*   **AArch64**: Automatically set to `true` to bypass unstable pre-boot NVML handshakes, allowing the driver to initialize and self-heal after the container is fully up.

## 3. Verification Checklist

To verify your multi-arch setup, ensure the following:

- [ ] **Architecture Check**: Run `uname -m`. Is it identified correctly by the setup scripts?
- [ ] **Library Visibility**: Inside the Kind node, run `ls /usr/lib/aarch64-linux-gnu/libnvidia-ml.so.1` (on ARM) to confirm the mount.
- [ ] **Driver Stability**: Check if `nvidia-dra-driver-gpu-kubelet-plugin` reaches `Running (2/2)` state without frequent restarts.

## 4. Summary

By decoupling the management logic from hardcoded architecture assumptions, we transformed the workshop into a **Platform-Agnostic** learning environment. This setup allows developers to leverage the cost-efficiency of ARM instances (like AWS Graviton or Grace Hopper) while maintaining full compatibility with legacy x86 workflows.

---
*Next Module: [Module 1: Kind Setup](01-kind-setup.md)*
