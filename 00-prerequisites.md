# Module 0: 預備知識與環境檢查

在開始本工作坊之前，請確保您的環境滿足以下需求。

## 1. 知識準備
本工作坊將深度使用以下技術：
- **Kubernetes v1.34+**: 這是 [KEP-4381: Structured Parameters](https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/4381-dra-structured-parameters) 成為 GA 版本的基礎環境。Structured Parameters 讓 K8s 排程器能直接理解硬體拓樸與資源屬性。
- **DRA (Dynamic Resource Allocation)**: K8s 的新一代資源管理介面，旨在取代傳統 [Device Plugin](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/)。更多細節可參考 [Kubernetes DRA 官方文件](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/)。
- **Kind (Kubernetes in Docker)**: 我們將利用 Kind 在單機模擬 K8s 叢集，並透過 [Container Device Interface (CDI)](https://github.com/cncf-tags/container-device-interface) 機制將 Host GPU 掛載進去。

## 2. 硬體需求
- **NVIDIA GPU**: 至少一張支援 CUDA 的 NVIDIA 顯示卡 (建議 RTX 30/40系列或資料中心等級 GPU)。
- **Linux OS**: 建議 Ubuntu 20.04/22.04 LTS。

## 3. 軟體依賴 (Prerequisites)
請確保 Host 端已安裝：

1.  **NVIDIA Drivers**: 需能執行 `nvidia-smi`。
    - [官方下載頁面](https://www.nvidia.com/Download/index.aspx)
2.  **Docker**: 容器 runtime。
    - [Install Docker Engine](https://docs.docker.com/engine/install/)
3.  **NVIDIA Container Toolkit**: 這是讓 Docker/Containerd 能夠存取 GPU 的關鍵。
    - [安裝指南](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
    - **重要**：必須設定 Docker Runtime 支援 CDI。
    - 驗證: `docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi`
    - 若失敗，請執行 `nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`。
4.  **Kind**: `go install sigs.k8s.io/kind@latest`
    - [Kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)
5.  **Helm**: 用於安裝 Driver Chart。
    - [Helm 安裝指南](https://helm.sh/docs/intro/install/)
6.  **Kubectl**: K8s CLI 工具。
    - [Install Tools](https://kubernetes.io/docs/tasks/tools/)

## 4. 自動檢查
我們提供了一個腳本來快速檢查您的環境：

```bash
cd scripts
./run-module0-check-env.sh
```

如果出現 `✅ Environment Check Passed!`，即可進入下一章節。

---
[下一章: 建構支援 DRA 的 Kind 叢集](./01-kind-setup.md)
