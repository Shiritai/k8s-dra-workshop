# Module 3: 部署與驗證 Workloads

本章節將部署實際的 Pod 來驗證 DRA 的功能。

## ResourceClaim API (v1)
在 K8s 1.34+ (Structured Parameters) 中，我們使用 `resource.k8s.io/v1` API。
Pod 不再像過去那樣在 `resources.limits` 中直接寫 `nvidia.com/gpu: 1`，而是透過 `resourceClaims` 欄位引用一個獨立的 `ResourceClaim` 物件。

範例 (`manifests/demo-gpu.yaml`):

```yaml
kind: ResourceClaim
spec:
  devices:
    requests:
    - name: req-1
      exactly:
        deviceClassName: gpu.nvidia.com
---
kind: Pod
spec:
  resourceClaims:
  - name: claim-ref-1
    resourceClaimName: gpu-claim-1 # 指向上面的 Claim
```

## 實驗步驟

### 1. 部署 Demo
```bash
cd scripts
./run-module3-verify-workload.sh
```

### 2. 觀察調度行為
- **Pod 1**: 應該會成功進入 `Running` 狀態，並能執行 `nvidia-smi`。
- **Pod 2**: 若您的機器只有一張 GPU，Pod 2 將會處於 `Pending` 狀態。這是因為預設的 Claim 是 **獨佔 (Exclusive)** 的，整張卡被 Pod 1 佔用了。

## 進階主題：共享 GPU (Consumable Capacity)
若要讓多個 Pod 共享同一張 GPU，需要在 Claim 中指定更細粒度的參數：
- **Admin Access**: [KEP-5018](https://github.com/kubernetes/enhancements/issues/5018) 提供管理員專用的存取模式。
- **Consumable Capacity**: [KEP-5075](https://github.com/kubernetes/enhancements/issues/5075) 支援 VRAM/Bandwidth 等可消耗資源的共享。

--
[回到首頁](../README.md)


