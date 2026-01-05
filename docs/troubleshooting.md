# Troubleshooting Guide

本指南彙整了在執行 DRA Workshop 時可能遇到的常見問題與解決方案。

## 1. Driver Not Registered / ContainerCreating Stuck
**症狀**:
- Pod 狀態一直卡在 `ContainerCreating` 或 `Pending`。
- `kubectl describe pod` 顯示 `FailedPrepareDynamicResources`: `DRA driver gpu.nvidia.com is not registered`。
- 或者顯示 `old ResourceClaim with same name ... still exists`。

**原因**:
- NVIDIA Driver Plugin 可能因為 Node 重啟或頻繁刪除 Pod 而與 Kubelet 失去同步。
- 殘留的 ResourceClaim 導致 Driver 認為資源已被佔用。

**解決方案**:
1.  **執行全域清理**:
    ```bash
    ./scripts/common/cleanup-all-workloads.sh
    ```
2.  **重置 Driver**:
    ```bash
    ./scripts/common/reset-driver.sh
    ```
    此腳本會強制重啟 Driver Pods，觸發重新註冊流程。

## 2. MPS Connection Failed
**症狀**:
- Module 4 失敗，顯示 `❌ Failed. MPS Control Pipe NOT found.`。

**原因**:
- Host 端的 MPS Control Daemon 未啟動。
- `/tmp/nvidia-mps` 權限不足，Kind Node 無法掛載或寫入。

**解決方案**:
1.  **檢查 Host Daemon**:
    ```bash
    ps aux | grep nvidia-cuda-mps-control
    ```
    若未執行，請啟動：
    ```bash
    nvidia-cuda-mps-control -d
    ```
2.  **檢查權限**:
    確保 `/tmp/nvidia-mps` 對所有使用者可讀寫 (或是至少對 Kind Node 內的 User 可用)：
    ```bash
    chmod -R 777 /tmp/nvidia-mps
    ```

## 3. Kind Cluster Creation Failed
**症狀**:
- `run-module1-setup-kind.sh` 失敗，顯示 `failed to create cluster` 或 Mount 錯誤。

**原因**:
- Docker 未執行。
- Host 缺少必要的 NVIDIA Library (如 `libnvidia-ml.so`)，導致自動生成 Config 失敗。

**解決方案**:
- 確認 Docker 正常運作 (`docker ps`)。
- 檢查 `scripts/common/helper-generate-kind-config.sh` 的輸出，確認是否抓到正確的 Library 路徑。若路徑異常，可能需要手動調整腳本中的 `find` 邏輯。
