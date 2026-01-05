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

## 效果展示 (Demo)
當 MPS 啟用時，您在 Host 端執行 `nvidia-smi` 將會看到 `nvidia-cuda-mps-server` 作為主要代理人，而 Pod 內的 Process (Type M) 則作為客戶端連線：

```text
Mon Jan  5 10:36:01 2026       
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.95.05              Driver Version: 580.95.05      CUDA Version: 13.0     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 4090        Off |   00000000:01:00.0 Off |                  Off |
|  0%   35C    P8              5W /  450W |     228MiB /  24564MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A            1001      C   nvidia-cuda-mps-server                         28MiB |
|    0   N/A  N/A            2001      M   /app/sample_workload                          200MiB |
+-----------------------------------------------------------------------------------------+
```
*(註：PID 與具體數值僅供參考，實際結果依環境而異)*

---
[下一章: MPS Advanced (Resource Control)](./05-mps-advanced.md)
