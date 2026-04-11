# Module 8: Admin Access & Observability

**Status**: ✅ **Verified**

## 1. Introduction
In a production HPC or AI environment, two "Day 2" operations are critical for Cluster Administrators:
1.  **Admin Access**: The ability to access a GPU node for debugging, even when it is fully allocated to users in "Exclusive Mode".
2.  **Observability**: The ability to monitor GPU metrics (Utilization, Memory, Power) using standard cloud-native tools like Prometheus.

This module validates how Kubernetes DRA handles these requirements.

---

## Part 1: Native Admin Access

### 1.1 Concept: The Exclusivity Problem
By default, when a GPU is allocated to a Pod (especially in Exclusive Mode), the Kubernetes Scheduler considers that device "Used". If a user's job hangs, the device remains locked. An administrator typically cannot schedule a debug pod onto that node because the scheduler sees "0 Available Devices".

### 1.2 The DRA Solution
Kubernetes DRA introduces a specific policy mechanism to override this limitation.
1.  **Namespace Labeling**: Mark a specific namespace as trusted for admin access.
2.  **Admin Claim**: Request a `ResourceClaim` with `adminAccess: true`.

When these conditions are met, the Scheduler ignores the "Exclusive" lock and allows the Admin Pod to bind to the device alongside the user's workload.

### 1.3 Implementation
**Namespace Label:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: default
  labels:
    resource.kubernetes.io/admin-access: "true"
```

**Resource Claim:**
```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: claim-admin
spec:
  devices:
    requests:
    - name: req-1
      exactly:
        deviceClassName: gpu-admin.nvidia.com
        adminAccess: true    # <--- Bypasses exclusivity lock
```

### 1.4 Verification
Run the automated scripts:
```bash
./scripts/phase2/run-module8-admin-access.sh
./scripts/phase2/run-module8-observability.sh
```
*Note: These scripts handle the necessary environment cleanup and driver setup automatically.*

**Expected Output:**
-   The `pod-admin` successfully enters `Running` state.
-   Inside the pod, you can access the GPU (e.g., `nvidia-smi`) even if other pods are using it.

---

## Part 2: Observability (DCGM)

### 2.1 Concept
To manage a GPU cluster effectively, administrators need visibility into hardware performance. NVIDIA provides the **DCGM Exporter** (Data Center GPU Manager) to export these metrics in Prometheus format.

### 2.2 The Challenge in DRA
In a Kubernetes DRA environment (especially with Kind), the monitoring container needs:
1.  **Access to Hardware**: It must bypass standard isolation to read GPU registers (`/proc/driver/nvidia`).
2.  **Driver Compatibility**: It needs access to the host's driver libraries (NVML) to query device status.

### 2.3 Implementation
We deploy `dcgm-exporter` as a DaemonSet with specific configurations:
-   **DRA Admin Access**: The DCGM exporter obtains GPU access through a `ResourceClaim` with `adminAccess: true`, allowing it to monitor devices even when they are fully allocated to user workloads.
-   **Elevated Capabilities**: `securityContext.capabilities.add: ["SYS_ADMIN"]` to access hardware counters (not full privileged mode).

### 2.4 Verification
The reproduction script automates the deployment and checking of the exporter.

**Manual Verification:**
```bash
# Forward port
kubectl port-forward -n nvidia-system ds/dcgm-exporter 9400:9400 &

# Check Metrics
curl localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL
```

**Expected Result:**
```prom
# HELP DCGM_FI_DEV_GPU_UTIL GPU utilization (in %).
# TYPE DCGM_FI_DEV_GPU_UTIL gauge
DCGM_FI_DEV_GPU_UTIL{gpu="0", ...} 98
```

---

## Appendix: Technical Notes & Troubleshooting

### known Issue: Driver Runtime Deadlock
*   **Symptom**: Admin Pod hangs in `ContainerCreating`.
*   **Cause**: The current NVIDIA Driver (v1beta1) has a state management issue where it fails to process Admin Claims if the internal MPS state is "dirty" from previous workloads.
*   **Workaround**: The `run-module8-admin-access.sh` script implements a "Safe Mode" that performs a clean re-installation of the driver before granting Admin Access. This ensures a pristine state for verification.
