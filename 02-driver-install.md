# Module 2: 安裝 NVIDIA DRA Driver

本章節將在 Kind 叢集中安裝 NVIDIA DRA Driver，啟用基於 Structured Parameters 的資源管理。

## 架構說明
NVIDIA DRA Driver 包含兩個主要元件：
1.  **Central Controller (Deployment)**: 負責處理 `ResourceClaim` 的生命週期與分配決策。
2.  **Node Agent (DaemonSet)**: 跑在每個節點上，負責發現 GPU 資源 (透過 CDI/NVML) 並發布 `ResourceSlice`。

## 安裝指令 (Helm)

我們使用官方 Helm Chart [nvidia/nvidia-dra-driver-gpu](https://github.com/NVIDIA/k8s-dra-driver/tree/main/deployments/helm/nvidia-dra-driver-gpu)。

```bash
cd scripts
./run-module2-install-driver.sh
```

### 關鍵參數說明
在安裝腳本中，我們設定了以下關鍵參數：
- `--set gpuResourcesEnabledOverride=true`: 強制啟用 GPU 資源支援 (目前為 Alpha 功能的安全鎖)。
- `--set kubeletPlugin.enabled=true`: 確保安裝 Node Agent (DaemonSet)，否則叢集將無法發現底層 GPU。

## 驗證安裝
安裝完成後，指令 `kubectl get resourceslices` 應該要回傳您節點上的 GPU 資訊。
這代表 Node Agent 成功掃描到了我們在 Module 1 掛載進去的 GPU 設備。

```bash
NAME                                          NODE                       DRIVER
workshop-dra-control-plane-gpu.nvidia.com...  workshop-dra-control-plane gpu.nvidia.com
```

--
[下一章: 部署與驗證 Workloads](./03-workloads.md)
