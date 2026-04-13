# k8s DRA Features

| KEP ID | Feat. Name | v1.30 | v1.31 | v1.32 | v1.33 | v1.34 (2025/08) | v1.35 (2025/12) | v1.36 (2026/04) | Key Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [3063](https://github.com/kubernetes/enhancements/issues/3063) | Classic DRA | Alpha (v1.26~) | Alpha | **Removed** |  |  |  |  | Incompatible with Autoscaler, deprecated |
| [4381](https://github.com/kubernetes/enhancements/issues/4381) | Structured Parameters | Alpha | Alpha | Beta | Beta | **Stable** | Stable | Stable | Core DRA architecture, GA in v1.34 |
| [5018](https://github.com/kubernetes/enhancements/issues/5018) | Admin Access |  |  |  | Alpha | Beta | Beta | **Stable** | Device monitoring/debugging; GA in v1.36 |
| [4815](https://github.com/kubernetes/enhancements/issues/4815) | Partitionable Devices |  |  |  | Alpha | Alpha | Alpha | **Beta** | Supports resource partitioning like MIG |
| [4816](https://github.com/kubernetes/enhancements/issues/4816) | Prioritized List |  |  |  | Alpha | Beta | Beta | **Stable** | Fallback options for resource requests; GA in v1.36 |
| [5055](https://github.com/kubernetes/enhancements/issues/5055) | Device Taints/Tolerations |  |  |  | Alpha | Alpha | Alpha | **Beta** | Device-level fault isolation |
| [5075](https://github.com/kubernetes/enhancements/issues/5075) | Consumable Capacity |  |  |  |  | Alpha | Alpha | **Beta** | Bandwidth/VRAM capacity sharing |
| [4680](https://github.com/kubernetes/enhancements/issues/4680) | Resource Health Status |  | Alpha | Alpha | Alpha | Alpha2 | Alpha2 | **Beta** | Exposes device health in Pod Status; Beta in v1.36 (not v1.35) |
| [5004](https://github.com/kubernetes/enhancements/issues/5004) | Extended Resource Mapping |  |  |  |  | Alpha | Alpha | **Beta** | Legacy extended-resource compatibility layer |
| [4817](https://github.com/kubernetes/enhancements/issues/4817) | Resource Claim Device Status |  |  | Alpha | Beta | Beta | Beta | **Stable** | Standardized device status in ResourceClaim (e.g. network interfaces); GA in v1.36 |
| [5007](https://github.com/kubernetes/enhancements/issues/5007) | Device Binding Conditions |  |  |  |  | Alpha | Alpha | **Beta** | Pre-schedule device attachment (bind before pod scheduled) |
| [5304](https://github.com/kubernetes/enhancements/issues/5304) | DRA Attributes Downward API |  |  |  |  |  |  | **Alpha** | Expose DRA device attributes via downward API; new in v1.36 |
| [5677](https://github.com/kubernetes/enhancements/issues/5677) | Resource Availability Visibility |  |  |  |  |  |  | **Alpha** | ResourcePoolStatus API for resource availability; new in v1.36 |
