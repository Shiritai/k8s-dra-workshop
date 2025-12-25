# k8s DRA Features

| KEP ID | Feat. Name | v1.30 | v1.31 | v1.32 | v1.33 | v1.34 (2025/08) | v1.35 (2025/12) | Key Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [3063](https://github.com/kubernetes/enhancements/issues/3063) | Classic DRA | Alpha (v1.26~) | Alpha | **Removed** |  |  |  | Incompatible with Autoscaler, deprecated |
| [4381](https://github.com/kubernetes/enhancements/issues/4381) | Structured Parameters | Alpha | Alpha | Beta | Beta | Stable | Stable | Core DRA architecture, officially GA (Stable) in v1.34 |
| [5018](https://github.com/kubernetes/enhancements/issues/5018) | Admin Access |  |  |  | Alpha | Beta | Beta | Used for device monitoring and debugging |
| [4815](https://github.com/kubernetes/enhancements/issues/4815) | Partitionable Devices |  |  |  | Alpha | Alpha | Alpha | Supports resource partitioning like MIG (Nvidia DRA driver: GPUs) |
| [4816](https://github.com/kubernetes/enhancements/issues/4816) | Prioritized List |  |  |  | Alpha | Beta | Beta | Provides fallback options (device list) for resource requests |
| [5055](https://github.com/kubernetes/enhancements/issues/5055) | Device Taints/Tolerations |  |  |  | Alpha | Alpha | Alpha | Device-level fault isolation |
| [5075](https://github.com/kubernetes/enhancements/issues/5075) | Consumable Capacity |  |  |  |  | Alpha | Alpha | Supports bandwidth/VRAM capacity sharing |
| [4680](https://github.com/kubernetes/enhancements/issues/4680) | Resource Health Status |  | Alpha | Alpha | Alpha | Alpha2 | Beta | Exposes device health status in Pod Status |
| [5004](https://github.com/kubernetes/enhancements/issues/5004) | Extended Resource Mapping |  |  |  |  | Alpha | Alpha | Transition solution compatible with legacy request syntax |
