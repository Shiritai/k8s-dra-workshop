# Module 1: 建構支援 DRA 的 Kind 叢集

本章節將建立一個支援 NVIDIA DRA (Structured Parameters) 的 Kind 叢集。

## 技術挑戰
在 Kind 中使用 DRA 的最大挑戰在於 **Driver Library 的可見性**。
Run-on-node 的 NVIDIA Driver (DaemonSet) 雖透過 CDI 運作，但在初始化階段仍需呼叫 NVML (`libnvidia-ml.so`) 來掃描設備。Kind 節點是一個封閉的容器，預設不包含這些 Host 端的 Library，且 Host 端的 Library 往往是 Symbolic Link，直接掛載會導致 Link Broken。

## 解決方案
我們設計了 `helper-generate-kind-config.sh` 腳本，它會：
1.  掃描 Host 端的 `nvidia-smi` 與 `libnvidia-ml.so`。
2.  解析 Symbolic Link，找出真正的目標檔案 (Target File)。
3.  產生包含完整 `extraMounts` 的 `kind-config.yaml`。
4.  設定必要的 Feature Gates (`DRAConsumableCapacity`)。
    - 依據 [KEP-5075: Consumable Resources](https://github.com/kubernetes/enhancements/issues/5075)，此功能允許更細粒度的資源共享 (e.g. VRAM slicing)。

## 實作步驟

### 1. 產生設定並建置叢集
執行我們的一鍵安裝腳本：

```bash
cd scripts
./run-module1-setup-kind.sh
```

### 2. 驗證結果
腳本執行完畢後，會自動執行 `docker exec` 測試。您也可以手動驗證：

```bash
# 檢查 GPU 是否在 Kind 節點內可見
docker exec workshop-dra-control-plane nvidia-smi
```

若能看到 GPU 資訊，代表基礎環境已就緒。

### 3. (進階) 了解 Config 內容
您可以查看生成的 `manifests/kind-config.yaml`，注意 `extraMounts` 區塊如何將 Host 的 library 對應進 Container。

```yaml
featureGates:
  "DRAConsumableCapacity": true
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".containerd]
      enable_cdi = true
```

--
[下一章: 安裝 NVIDIA DRA Driver](./02-driver-install.md)
