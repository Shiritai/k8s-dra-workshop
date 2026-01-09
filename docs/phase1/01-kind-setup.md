# Module 1: Kind Cluster Setup (In-Cluster MPS Architecture)

Because this workshop requires **MPS (Multi-Process Service)**, we cannot use a standard Kind cluster. MPS relies on IPC (Inter-Process Communication) via shared memory (`/dev/shm`) and specific pipes, which are isolated by default in Kind.

To solve this, we implement an **In-Cluster MPS Architecture**:
1. Mount the Host's MPS binaries and libraries into the Kind Node container.
2. Start the MPS Control Daemon *inside* the Node container.
3. Use `/dev/shm` bridging to allow Pods to talk to this Node-local daemon.

## 1. Automated Setup
We provide scripts to handle the complex configuration automatically:

```bash
./scripts/phase1/run-module1-setup-kind.sh
```

## 2. Technical Details

### Kind Configuration Generator
The script `scripts/common/helper-generate-kind-config.sh` dynamically discovers your host's NVIDIA environment and generates a `kind-config.yaml`.

It mounts the following critical components:
- **Binaries**: `nvidia-smi`, `nvidia-cuda-mps-control`, `nvidia-cuda-mps-server`.
- **Libraries**: `libnvidia-ml`, `libcuda`, and **`libnvidia-ptxjitcompiler`** (Crucial for CUDA JIT compilation inside containers).
- **IPC**: `/dev/shm` (System V Shared Memory).
- **CDI**: `/etc/cdi/nvidia.yaml` (For device injection).

### Verification
After the script completes, you can verify the In-Cluster MPS daemon is running:

```bash
docker exec workshop-dra-control-plane ps aux | grep mps
```
*Expected Output:*
```
root ... /usr/bin/nvidia-cuda-mps-control -d
root ... /usr/bin/nvidia-cuda-mps-server
```

### Why "In-Cluster"?
Standard approaches often run MPS on the *Host* and bind-mount `/tmp/nvidia-mps`. However, Kind nodes run in a separate IPC namespace. Even with `hostIPC: true` in a Pod, the Pod only sees the *Node's* IPC, not the *Host's* IPC. By moving the Daemon *into* the Node, we align the IPC namespaces (Node == Pod's Host), allowing standard `hostIPC` connectivity to work.
