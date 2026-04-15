// Shared VRAM allocation test for Module 11-2 (VRAM limit tests).
// Reports CUDA_MPS_PINNED_DEVICE_MEM_LIMIT env var status,
// queries cudaMemGetInfo, then attempts a sized allocation.
// When the env var is unset (11-2a server-side test), prints "(unset)".

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <cuda_runtime.h>

int main() {
    const char* env_alloc = getenv("ALLOC_MIB");
    size_t alloc_mib = env_alloc ? (size_t)atol(env_alloc) : 4096;
    size_t alloc_bytes = alloc_mib * 1024ULL * 1024ULL;

    const char* mps_limit = getenv("CUDA_MPS_PINNED_DEVICE_MEM_LIMIT");
    printf("[env] CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=%s\n",
           mps_limit ? mps_limit : "(unset)");

    size_t free_mem, total_mem;
    cudaError_t err = cudaMemGetInfo(&free_mem, &total_mem);
    if (err != cudaSuccess) {
        printf("[cuda] cudaMemGetInfo FAILED: %s (code %d)\n",
               cudaGetErrorString(err), (int)err);
        return 1;
    }
    printf("[cuda] GPU memory: total=%zu MiB, free=%zu MiB\n",
           total_mem / (1024*1024), free_mem / (1024*1024));
    printf("[cuda] Attempting to allocate %zu MiB...\n", alloc_mib);
    fflush(stdout);

    void* ptr = NULL;
    err = cudaMalloc(&ptr, alloc_bytes);
    if (err != cudaSuccess) {
        printf("[cuda] FAILED: %s (code %d)\n",
               cudaGetErrorString(err), (int)err);
        printf("[cuda] Conclusion: allocation of %zu MiB was rejected.\n",
               alloc_mib);
        fflush(stdout);
        sleep(60);
        return 1;
    }

    printf("[cuda] Success: %zu MiB allocated at %p\n", alloc_mib, ptr);
    printf("[cuda] Writing to allocated memory (cudaMemset)...\n");
    fflush(stdout);

    err = cudaMemset(ptr, 0xAB, alloc_bytes);
    if (err != cudaSuccess) {
        printf("[cuda] cudaMemset FAILED: %s (code %d)\n",
               cudaGetErrorString(err), (int)err);
        fflush(stdout);
        sleep(60);
        return 1;
    }

    printf("[cuda] Memory write verified OK (%zu MiB written).\n", alloc_mib);

    size_t free_after, total_after;
    cudaMemGetInfo(&free_after, &total_after);
    printf("[cuda] GPU memory after alloc: total=%zu MiB, free=%zu MiB\n",
           total_after / (1024*1024), free_after / (1024*1024));
    fflush(stdout);

    printf("[cuda] Sleeping 300s to keep allocation alive...\n");
    fflush(stdout);
    sleep(300);

    cudaFree(ptr);
    return 0;
}
