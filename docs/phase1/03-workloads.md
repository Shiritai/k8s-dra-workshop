# Module 3: Basic Workload & DRA Mechanics

## 1. Overview
This module validates the fundamental "Claim-Bind-Run" cycle of Dynamic Resource Allocation.
Before attempting advanced features like MPS, we must confirm that the **Default Scope** (Exclusive Access) works as intended.

## 2. Default Behavior: Exclusive Access
In the current implementation of the NVIDIA DRA Driver, a GPU is treated as an **atomic, exclusive resource** unless configured otherwise (via MPS).
- **Scenario**: You have 1 Physical GPU.
- **Action**: You deploy `pod-1` claiming a GPU.
- **Result**: `pod-1` Runs. The GPU is LOCKED.
- **Action**: You deploy `pod-2` claiming a GPU.
- **Result**: `pod-2` Pends. No resources available.

This behavior contrasts with the classic Device Plugin, which often allowed oversubscription if not configured strictly, but DRA makes the availability explicit.

## 3. The DRA Workflow for Developers

Gone are the days of requests: `nvidia.com/gpu: 1`.
The new workflow decouples the **Need** (Pod) from the **Request** (Claim).

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Pod as Pod Spec
    participant Claim as ResourceClaim
    participant Sched as K8s Scheduler
    participant Driver as DRA Driver
    participant Node as Kubelet/CDI

    Dev->>Claim: Create ResourceClaim (Request GPU)
    Dev->>Pod: Create Pod (Reference Claim)
    Pod->>Sched: "I need Claim X"
    Sched->>Driver: "Is Claim X satisfiable?"
    Driver->>Sched: "Yes, on Node A (UUID: GPU-xxxxx)"
    Sched->>Node: Schedule Pod on Node A
    Node->>Claim: Reserve Device
    Node->>Pod: Inject Device (via CDI)
```

## 4. Manifest Deep Dive

Let's dissect `manifests/module3/demo-gpu.yaml` to understand the binding.

### 4.1. The Claim
```yaml
apiVersion: resource.k8s.io/v1           # 1. GA API (K8s 1.34+)
kind: ResourceClaim
metadata:
  name: gpu-claim-1
spec:
  devices:
    requests:
    - name: req-1                         # 2. Request name (internal reference)
      exactly:
        deviceClassName: gpu.nvidia.com   # 3. Selects the Driver's DeviceClass
```

### 4.2. The Pod
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-gpu-1
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.1-base-ubuntu22.04
    command: ["sleep", "inf"]
    resources:
      claims:
      - name: claim-ref-1              # 4. Defines a local name for the claim
  resourceClaims:
  - name: claim-ref-1                  # 5. Maps local name to external object
    resourceClaimName: gpu-claim-1     # 6. References the ResourceClaim above
  restartPolicy: Never
```

## 5. Verification

Run the automated verification:
```bash
./scripts/phase1/run-module3-verify-workload.sh
```

### Success Indicators
1.  `pod-gpu-1` status becomes `Running`.
2.  `nvidia-smi` inside the pod shows the GPU.
3.  `pod-gpu-2` (if deployed on single-GPU node) typically remains `Pending` (SchedulingGated), proving the scheduler correctly tracks the GPU as "Occupied".

## 6. Official References
- [Kubernetes Docs: ResourceClaims](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/)
