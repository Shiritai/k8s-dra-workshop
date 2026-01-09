# pre-requisites for Phase 1 Workshop

Before starting the workshop, ensure your environment meets the following requirements. 

We provide a script to check your environment automatically:
```bash
./scripts/phase1/run-module0-check-env.sh
```

## 1. Hardware & OS
- **OS**: Linux (Ubuntu 22.04 LTS recommended)
- **GPU**: NVIDIA GPU (Pascal or newer)
- **Kernel**: 5.15+ (Required for some advanced eBPF featues, though not strictly for basic DRA)

## 2. Essential Tools
Ensure the following CLIs are installed:

| Tool              | Minimum Version | Installation Guide                                              |
| ----------------- | --------------- | --------------------------------------------------------------- |
| **Docker**        | 24.0+           | [Install Docker](https://docs.docker.com/engine/install/)       |
| **Kind**          | 0.24.0+         | [Install Kind](https://kind.sigs.k8s.io/docs/user/quick-start/) |
| **Helm**          | 3.10+           | [Install Helm](https://helm.sh/docs/intro/install/)             |
| **NVIDIA Driver** | 535+            | [NVIDIA Drivers](https://www.nvidia.com/Download/index.aspx)    |

## 3. NVIDIA Container Toolkit (CDI Support)
The DRA driver relies on **CDI (Container Device Interface)** for device changes injection. You must configure the NVIDIA Container Toolkit to generate the CDI specification.

1. **Install Toolkit**:
   ```bash
   sudo apt-get install -y nvidia-container-toolkit
   ```
2. **Configure Runtime**:
   ```bash
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```
3. **Generate CDI Spec**:
   ```bash
   sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
   ```
   *The check script (`run-module0-check-env.sh`) verifies this configuration.*

## 4. MPS Requirements (For Module 4 & 5)
For the **In-Cluster MPS** architecture, we mount the **Host's** MPS binaries into the Kind Node.

1. **Ensure Binaries Exist**:
   Verify that `/usr/bin/nvidia-cuda-mps-control` and `/usr/bin/nvidia-cuda-mps-server` exist on your host.
   *(These usually come with the NVIDIA driver or `nvidia-utils` package)*.

2. **Run Host MPS (Optional but recommended for testing host pipes)**:
   While our architecture runs the daemon *inside* the node, ensuring the host environment is clean (or explicitly managed) is good practice. The check script verifies if the control daemon is running, though for this specific workshop, the **In-Cluster** daemon is the critical one.

## Troubleshooting
If `run-module0-check-env.sh` fails:
- **Missing Tools**: Install using `apt` or official scripts.
- **Docker Runtime**: Run `docker info | grep nvidia` to check registration.
- **CDI Error**: Check if `/etc/cdi/nvidia.yaml` exists and is readable.
