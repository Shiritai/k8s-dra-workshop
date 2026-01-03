# Module 4: MPS Basics (Spatial Sharing)

本章節將引導您啟用 NVIDIA MPS (Multi-Process Service)，體驗比傳統 Context Switching 更高效的 Spatial Sharing。

## 概念
當多個 Pod 共享同一顆 GPU 時，預設行為是 **Time-Slicing (Temporal Sharing)**，即輪流使用 GPU。
啟用 MPS 後，多個行程可同時在 GPU 上執行 (**Spatial Sharing**)，提升小模型或低負載任務的總吞吐量。

## 架構要求
1.  **Host 端**: 必須執行 MPS Control Daemon (`nvidia-cuda-mps-control -d`)。
2.  **Kind Node**: 必須掛載 Host 的 IPC Pipe (`/tmp/nvidia-mps`)。
3.  **Pod**: 必須能存取該 Pipe (透過 `hostIPC: true` 或 Volume Mount)。

## 實作步驟
1.  **啟動 Daemon (Host)**:
    ```bash
    nvidia-cuda-mps-control -d
    ```
2.  **執行驗證**:
    ```bash
    ./scripts/phase1/run-module4-mps-basics.sh
    ```
3.  **預期結果**:
    - Script 會部署 `mps-basic` Pod。
    - Pod 內部執行 `echo ps | nvidia-cuda-mps-control` 成功回傳 Daemon 狀態。
    - 代表 Pod 成功「穿透」Kind Node 連線至 Host 的 MPS 服務。

---
[下一章: MPS Advanced (Resource Control)](./05-mps-advanced.md)
