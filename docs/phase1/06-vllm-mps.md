# Module 6: vLLM Verification with MPS

## 1. Objective

This module aims to verify whether vLLM (LLM Inference Engine) can successfully start and perform inference tasks under NVIDIA MPS (Multi-Process Service) resource constraints. This is a fundamental step to confirm the effectiveness of the Kubernetes resource isolation mechanism.

## 2. Environment

- **Kubernetes Cluster**: Kind (v1.32.0 node image)
- **DRA Driver**: NVIDIA DRA Driver (v0.8.0+)
- **GPU**: NVIDIA GPU (MPS support required, VRAM >= 8GB recommended)
- **Model**: `Qwen/Qwen2.5-1.5B-Instruct`
- **Inference Engine**: vLLM (v0.6.3+)

## 3. Execution Steps

We provide an automated script to execute the verification process:

1. Clean up existing vLLM Pod and ResourceClaim.
2. Deploy vLLM Server with **MPS Active Thread Percentage** limit (default 50%).
3. Wait for the Server to be ready.
4. Send a simple inference request.
5. Verify if text is generated successfully.

Command:

```bash
./scripts/phase1/run-module6-vllm-verify.sh
```

## 4. Expected Result

If verification is successful, you will see output similar to the following:

```text
Step 4: Running Inference Verification...
Inference Output:
{
    "id": "cmpl-...",
    "object": "text_completion",
    "created": ...,
    "model": "Qwen/Qwen2.5-1.5B-Instruct",
    "choices": [
        {
            "text": "...",
            ...
        }
    ],
    ...
}

✅ Verification Successful: vLLM generated text under MPS constraints.
```

This confirms that:
1. MPS resource limits are effective (Pod successfully scheduled and running).
2. vLLM can operate normally under restricted compute resources.
