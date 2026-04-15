// Shared FMA benchmark for Module 11-1 (SM limit tests).
// Reports CUDA_MPS_ACTIVE_THREAD_PERCENTAGE and visible SMs,
// then runs a compute-bound FMA stress loop.
// When the env var is unset (11-1a server-side test), prints "(unset)".

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <cuda_runtime.h>
#include <sys/time.h>

#define N (16 * 1024 * 1024)
#define ITERATIONS 200
#define BLOCK_SIZE 256
#define INNER_ITERS 64

__global__ void fma_stress(const float* __restrict__ a,
                           const float* __restrict__ b,
                           float* __restrict__ c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n) return;
    float va = a[idx];
    float vb = b[idx];
    float vc = c[idx];
    #pragma unroll
    for (int i = 0; i < INNER_ITERS; i++) {
        vc = va * vb + vc;
    }
    c[idx] = vc;
}

static double now_sec() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec * 1e-6;
}

#define CHECK(call) do { \
    cudaError_t err = (call); \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__, \
                cudaGetErrorString(err)); \
        exit(1); \
    } \
} while(0)

int main() {
    const char* thread_pct = getenv("CUDA_MPS_ACTIVE_THREAD_PERCENTAGE");
    printf("[env] CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=%s\n",
           thread_pct ? thread_pct : "(unset)");

    cudaDeviceProp prop;
    CHECK(cudaGetDeviceProperties(&prop, 0));
    printf("[cuda] device: %s, SMs: %d\n", prop.name, prop.multiProcessorCount);
    fflush(stdout);

    size_t bytes = (size_t)N * sizeof(float);
    float *d_a, *d_b, *d_c;

    CHECK(cudaMalloc(&d_a, bytes));
    CHECK(cudaMalloc(&d_b, bytes));
    CHECK(cudaMalloc(&d_c, bytes));

    float *h = (float*)malloc(bytes);
    for (int i = 0; i < N; i++) h[i] = 1.0f;
    CHECK(cudaMemcpy(d_a, h, bytes, cudaMemcpyHostToDevice));
    for (int i = 0; i < N; i++) h[i] = 0.5f;
    CHECK(cudaMemcpy(d_b, h, bytes, cudaMemcpyHostToDevice));
    CHECK(cudaMemset(d_c, 0, bytes));
    free(h);

    int grid = (N + BLOCK_SIZE - 1) / BLOCK_SIZE;

    // Warmup
    for (int i = 0; i < 5; i++)
        fma_stress<<<grid, BLOCK_SIZE>>>(d_a, d_b, d_c, N);
    CHECK(cudaDeviceSynchronize());

    printf("[bench] starting: N=%d INNER_ITERS=%d ITERATIONS=%d\n",
           N, INNER_ITERS, ITERATIONS);
    fflush(stdout);

    double t0 = now_sec();
    for (int i = 0; i < ITERATIONS; i++) {
        fma_stress<<<grid, BLOCK_SIZE>>>(d_a, d_b, d_c, N);
    }
    CHECK(cudaDeviceSynchronize());
    double t1 = now_sec();

    double elapsed = t1 - t0;
    double total_ops = 2.0 * INNER_ITERS * (double)N * ITERATIONS;
    double gflops = total_ops / elapsed / 1e9;

    printf("[bench] iterations=%d elapsed=%.3fs throughput=%.2f GFLOPS\n",
           ITERATIONS, elapsed, gflops);
    fflush(stdout);

    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_c);

    printf("[bench] done, sleeping to keep pod alive...\n");
    fflush(stdout);
    sleep(3600);
    return 0;
}
