# k8s x NVIDIA DRA (Structured Parameters) on Kind Workshop

歡迎來到 k8s x NVIDIA DRA 工作坊！

本工作坊旨在協助 Kubernetes 工程師與開發者，在本地 Kind 環境中快速體驗並驗證 **Dynamic Resource Allocation (DRA)** 的 ResourceSlice 與 Structured Parameters 等機制。

## 專案結構
```
dra-workshop/
├── docs/
│   ├── phase1/           # Phase 1: Basic Setup & Verification
│   │   ├── 00-prerequisites.md   # [Module 0] 環境準備
│   │   ├── 01-kind-setup.md      # [Module 1] 叢集建置 (核心技術)
│   │   ├── 02-driver-install.md  # [Module 2] Driver 安裝
│   │   └── 03-workloads.md       # [Module 3] 驗證與實戰 (基礎獨佔)
│   └── phase2/           # Phase 2: Advanced Features (Consumable)
│       ├── 04-consumable-capacity.md # [Module 4] 資源共享 (Consumable) (Coming Soon)
│       ├── 05-admin-access.md    # [Module 5] 管理員存取 (Coming Soon)
│       └── 06-resilience.md      # [Module 6] 韌性與調度 (Coming Soon)
├── k8s-dra-features.md   # Kubernetes DRA 功能演進詳情
├── scripts/              # 自動化腳本
│   ├── common/           # 共用工具 (Teardown, Config Gen)
│   └── phase1/           # Phase 1 執行腳本
└── manifests/            # K8s YAML 檔案
```

## 快速開始 (Quick Start)

### Workshop Phase 1: Environment Setup & DRA Verification

請依序執行以下步驟：

1.  **環境檢查**:
    ```bash
    ./scripts/phase1/run-module0-check-env.sh
    ```
2.  **建立叢集**:
    ```bash
    ./scripts/phase1/run-module1-setup-kind.sh
    ```
3.  **安裝 Driver**:
    ```bash
    ./scripts/phase1/run-module2-install-driver.sh
    ```
4.  **驗證 Workload**:
    ```bash
    ./scripts/phase1/run-module3-verify-workload.sh
    ```

## 清理環境 (Clean Up)
實驗結束後，執行以下指令可完全移除叢集：
```bash
./scripts/common/run-teardown.sh
```

## 技術亮點
- **Dynamic Library Discovery**: 自動偵測 Host 端 NVIDIA Driver 路徑並掛載至 Kind 節點，解決斷鏈問題。
- **Automated Config Generation**: 自動生成包含正確 Mounts 的 Kind Config。
- **Latest DRA API Support**: 支援 K8s 1.34+ `resource.k8s.io/v1` API。

## Kubernetes DRA 功能演進 (Feature Matrix)

下表整理了 DRA 相關功能的演進歷程與 KEP 連結：

| KEP ID                                                         | Feat. Name            | v1.34 (2025/08) | v1.35 (2025/12) | Key Notes                                     |
| -------------------------------------------------------------- | --------------------- | --------------- | --------------- | --------------------------------------------- |
| [4381](https://github.com/kubernetes/enhancements/issues/4381) | Structured Parameters | **Stable**      | **Stable**      | Core DRA architecture, officially GA in v1.34 |
| [5075](https://github.com/kubernetes/enhancements/issues/5075) | Consumable Capacity   | **Alpha**       | **Alpha**       | Supports bandwidth/VRAM capacity sharing      |
| [5018](https://github.com/kubernetes/enhancements/issues/5018) | Admin Access          | **Beta**        | **Beta**        | Used for device monitoring and debugging      |

更多詳細資訊請參考 [Kubernetes Enhancements](https://github.com/kubernetes/enhancements) 或檢視本專案整理的 [DRA 功能演進](k8s-dra-features.md)。

Enjoy hacking! 🚀
