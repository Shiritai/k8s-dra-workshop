# Module 5: MPS Advanced (Resource Control)

本章節介紹如何透過 MPS 控制客戶端的資源使用上限，實現更細粒度的 QoS (Quality of Service)。

## 資源控制機制
MPS 允許 Client 設定環境變數來限制與隔離資源：
1.  **最大執行緒 (Thread Percentage)**:
    `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=20` 代表該 Process 最多只能佔用 20% 的 SM 計算資源。
2.  **記憶體限制 (Memory Limit)**:
    `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=1G` 代表該 Process 在 Device 0 上最多只能配置 1GB VRAM。

## 實作步驟
1.  **確認環境**:
    延續 Module 4，確保 Host MPS Daemon 仍在執行。
2.  **執行驗證**:
    ```bash
    ./scripts/phase1/run-module5-mps-advanced.sh
    ```
3.  **預期結果**:
    - Script 部署 `mps-limited` Pod。
    - 檢查 Pod 內環境變數是否正確設定。
    - 若搭配實際 CUDA 負載 (如矩陣運算)，可觀察到效能與 VRAM 佔用被嚴格限制。

## 效果展示 (Demo)
當設定了 `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=1G` 後，即使 GPU 有 24GB VRAM，該 Process 也會被強制限制在 1GB：

```text
Mon Jan  5 10:42:15 2026       
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.95.05              Driver Version: 580.95.05      CUDA Version: 13.0     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 4090        Off |   00000000:01:00.0 Off |                  Off |
|  0%   38C    P8              8W /  450W |    1052MiB /  24564MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A            1001      C   nvidia-cuda-mps-server                         28MiB |
|    0   N/A  N/A            3005      M   /app/limited_workload                        1024MiB |
+-----------------------------------------------------------------------------------------+
```
*注意：Process 的 VRAM 使用量被精確鎖定在限制值 (1024MiB) 附近。*

---
**Phase 1 結束**。接下來請參考 Phase 2 文件進行 DRA 進階功能實作。
