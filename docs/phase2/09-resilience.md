# Module 9: Resilience (High Availability & Fault Tolerance)

**Status**: ✅ **Verified & Automated**

## 🎯 Goal
Demonstrate the high availability (HA) and fault tolerance of the NVIDIA Dynamic Resource Allocation (DRA) architecture. A key architectural advantage of DRA is the strict decoupling of the **Control Plane** (Resource Allocation & Preparation) from the **Data Plane** (Execution & GPU Access).

In this module, we conduct three destructive ("Chaos Engineering" style) experiments to prove which failures are transparent to workloads, and which represent the fundamental "Achilles Heel" of software-based GPU sharing.

---

## 🏗️ Architectural Concept: Decoupling via CDI
When Kubelet starts a container, the DRA Kubelet Plugin does not continuously proxy GPU traffic. Instead, its job is to dynamically generate a **CDI (Container Device Interface)** JSON document. Once the low-level container runtime (e.g., `containerd`) consumes this CDI file and injects the device paths (`/dev/nvidia0`) and libraries into the container namespace, the plugin's job is done. 

From that moment on, the container workload communicates **directly with the physical GPU via the PCIe bus**.

---

## 🧪 Chaos Experiments & Verification Results

Our automated scripts execute and validate the following three scenarios:
- `run-module9-resilience.sh` — Experiment 1 (Controller)
- `run-module9-resilience-driver.sh` — Experiment 2 (Kubelet Plugin)
- `run-module9-resilience-mps.sh` — Experiment 3 (MPS Daemon)

### 1. Control Plane Failure (Driver Controller)
- **Scenario**: We simulate a catastrophic failure of the central orchestrator by force-deleting the `nvidia-dra-driver-gpu-controller` pod while a workload (`pod-resilience`) is actively running.
- **Expected Outcome**: The running pod must **NOT** crash.
- **Verification Result**: ✅ **Survives**. 
  Because GPU access is natively injected via CDI, the death of the K8s Controller has zero impact on the running Data Plane. Once the Controller respawns, it successfully rebuilds its internal cache by interrogating the API server and Kubelet, allowing new pods to be scheduled immediately.

### 2. Node Agent Failure (Kubelet Plugin)
- **Scenario**: We simulate the failure of the node-level DRA daemon (`nvidia-dra-driver-gpu-kubelet-plugin`). 
- **Expected Outcome**: Existing pods must survive. New pods on that node will remain `Pending` until the plugin recovers.
- **Verification Result**: ✅ **Survives**. 
  Similar to the Controller, the plugin is only responsible for the *Preparation* phase (writing the CDI file). Its death does not sever the established PCIe link. 

### 3. Data Plane / Runtime Failure (MPS Daemon)
- **Scenario**: We deploy an MPS (Multi-Process Service) workload, which relies on the `nvidia-mps-control-daemon` DaemonSet for spatial GPU sharing. We then abruptly kill this Daemon.
- **Expected Outcome**: **Fatal Crash (Fail Fast)**.
- **Verification Result**: ❌ **Workload Dies (As Expected)**.
  **Why?** Unlike native PCIe access, MPS relies on an Active Memory Pipe (Unix Domain Socket + System V Shared Memory at `/tmp/nvidia-mps`) to facilitate Inter-Process Communication (IPC) between the container's CUDA context and the host's MPS Server. 
  When the Daemon dies, this memory pipeline is severed instantly. The container attempts to access invalid memory (Segfault) and triggers an immediate `CUDA Error`. This represents the **"Shared Fate"** tradeoff of software-based spatial sharing.

---

## ⚠️ Engineering Realities & Environment Fixes

During the development of these verification scripts, we solved two critical engineering challenges that workshop attendees should note:

### 1. The `fsnotify` Limit on Kind/Containerd
We discovered a stability issue in **Kind/Containerd** environments where the Kubelet failed to re-register the Driver after a restart (yielding a `DRA driver is not registered` error).
- **Root Cause**: The default `fs.inotify.max_user_watches` limit on standard Kind nodes is too low. When the Driver pod restarts and creates a new UNIX socket in the Kubelet plugin directory, Kubelet's `fsnotify` watcher fails to catch the event.
- **Mandatory Fix** (Applied during Module 8/Setup):
  ```bash
  sysctl -w fs.inotify.max_user_watches=524288
  systemctl restart kubelet
  ```

### 2. Idempotency & Nuclear Cleanup
In distributed systems testing, abrupt terminations leave trailing states (Zombie ResourceClaims) in the API server because the normal Graceful Termination process is bypassed. 
To make our resilience scripts fully idempotent (rerunnable anytime), we employed a "Nuclear Cleanup" strategy:
```bash
kubectl delete pod ... --force --grace-period=0
kubectl delete resourceclaim ... --force --grace-period=0
```
*Note: This is an educational hack to guarantee a clean slate in 15-minute workshops. In production, rely on standard Garbage Collection to avoid orphaned device allocations in the Container Runtime.*
