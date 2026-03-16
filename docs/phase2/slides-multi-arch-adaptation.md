---
marp: true
theme: default
paginate: true
header: "NVIDIA DRA Workshop - Adaptive Infrastructure"
footer: "Multi-Architecture Adaptation Guide (AArch64/x64)"
style: |
  section {
    background-color: #ffffff;
    color: #000000;
    font-size: 28px;
  }
  h1, h2, h3, h4, h5, h6 {
    color: #76b900 !important; /* NVIDIA Green */
  }
  p, li, table, th, td {
    color: #000000 !important;
  }
  img[alt~="center"] {
    display: block;
    margin: 0 auto;
  }
  pre, code {
    background-color: #f4f4f4 !important;
    color: #d63384 !important;
    border: 1px solid #ddd;
  }
---

<!-- class: default -->
# Adaptive Infrastructure
## For Heterogeneous AI Computing (ARM & x86)

**Goal**: Seamless Kubernetes DRA Portability across CPU Architectures

---

# The Challenge: The Architecture Gap

Why can't we just "run it" on ARM?

1.  **Library Path Discrepancy**:
    - x86: `/usr/lib/x86_64-linux-gnu`
    - ARM: `/usr/lib/aarch64-linux-gnu`
2.  **NVML Init Death Loop**: 
    - Specific timing issues on ARM platforms cause pre-start check failures.
3.  **Distroless Limitations**:
    - No `ldconfig` or dynamic search paths in minimal driver containers.

---

# Strategy: Dynamic Architecture Detection

Stop hardcoding. Start detecting.

```bash
# Architecture-Aware Pathing
ARCH=$(uname -m)
LIB_DIR="x86_64-linux-gnu"
if [ "$ARCH" = "aarch64" ]; then
    LIB_DIR="aarch64-linux-gnu"
fi
```

**Key Benefits**:
- Single codebase for both platforms.
- Automatic library mapping for Kind nodes.
- Future-proof for new hardware (Graviton, Grace).

---

# Patching the Driver: `skipPrestart`

**Problem**: The standard NVIDIA init-sequence crashes on certain ARM/Kind setups.

**Solution**:
- Implement a `skipPrestart` toggle in Helm.
- **ARM**: `true` (Lazy initialization).
- **x86**: `false` (Standard behavior).

> *Result: 100% stability on ARM without sacrificing x86 compatibility.*

---

# Infrastructure Fix: Scheduler RBAC

DRA introduces new API groups that the default Kind scheduler cannot see.

**The Fix**:
- Apply `ClusterRole` permissions for `resource.k8s.io`.
- Allow the scheduler to "get", "list", and "watch" `DeviceClasses`.

**Impact**:
- Transparent across all architectures.
- Eliminates "Pending" state in ResourceClaims.

---

# Verified Performance: 100% Parity

| Architecture | Module 1-3 (Setup) | Module 4-6 (MPS/vLLM) | Status |
| :--- | :--- | :--- | :--- |
| **x86_64** | ✅ Success | ✅ Success | Stable |
| **AArch64** | ✅ Success | ✅ Success | **Adapted** |

**Conclusion**:
NVIDIA DRA + Our Adaptive Patches = **Truly Cross-Platform AI Infra.**

---

<!-- class: default -->

# Thank You
## Any Questions on Multi-Arch Porting?
