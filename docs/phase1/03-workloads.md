# Module 3: Basic Workload Verification

Before diving into MPS sharing, we must verify the standard **Exclusive Allocation** flow. This confirms that the DRA driver is correctly intercepting Pod scheduling requests and injecting the GPU device.

## 1. Deploy Workload
Run the verification script:
```bash
./scripts/phase1/run-module3-verify-workload.sh
```

## 2. The Concept: ResourceClaim
In DRA, scheduling is decoupled into three parts:
1. **ResourceClass**: Defines "what" kind of device (e.g., `gpu.nvidia.com`).
2. **ResourceClaim**: A request for a specific device instance (e.g., "Give me 1 GPU").
3. **Pod**: References the Claim.

### Sample Manifest (`manifests/demo-gpu.yaml`)
```yaml
apiVersion: resource.k8s.io/v1alpha2
kind: ResourceClaim
metadata:
  name: gpu-claim-1
spec:
  resourceClassName: gpu.nvidia.com
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-gpu-1
spec:
  containers:
  - name: ctr
    image: nvidia/cuda:11.7.1-base-ubuntu22.04
    resources:
      claims:
      - name: claim-1 # Links to the Claim Template below
  resourceClaims:
  - name: claim-1
    resourceClaimName: gpu-claim-1 # Binds to the actual ResourceClaim object
```

## 3. Verification Details
The script performs two key checks:
1. **Successful Run**: `pod-gpu-1` should reach `Running` state and execute `nvidia-smi`.
2. **Exclusive Lock**: `pod-gpu-2` (if deployed on a single-GPU node) should stay `Pending` because the first claim has exclusively reserved the GPU.

*If this passes, your DRA scheduler and CDI injection are working correctly.*
