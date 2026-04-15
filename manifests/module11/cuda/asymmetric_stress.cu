// Module 11-3b: Asymmetric MIG stress test (Exclusive vs MPS 30%).
// Benchmarks SAXPY (memory-bound) and compute-heavy (SM-bound) kernels
// per device, then compares exclusive vs MPS throughput.

#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#define CHECK_CUDA(call) do { \
    cudaError_t err = (call); \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error at %s:%d — %s\n", \
                __FILE__, __LINE__, cudaGetErrorString(err)); \
        return -1; \
    } \
} while(0)

__global__ void saxpy(int n, float a, const float *x, float *y) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        y[i] = a * x[i] + y[i];
    }
}

__global__ void compute_heavy(int n, float *data, int reps) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        float val = data[i];
        for (int r = 0; r < reps; r++) {
            val = val * 1.00001f + 0.00001f;
        }
        data[i] = val;
    }
}

static double get_time_ms() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

typedef struct {
    double saxpy_gflops;
    double heavy_gflops;
    double alloc_bw_gbps;
} bench_result_t;

static int run_full_benchmark(int device_id, int n, int iterations,
                              bench_result_t *result) {
    cudaError_t err;
    memset(result, 0, sizeof(*result));

    err = cudaSetDevice(device_id);
    if (err != cudaSuccess) {
        fprintf(stderr, "  [Dev %d] cudaSetDevice: %s\n",
                device_id, cudaGetErrorString(err));
        return -1;
    }

    size_t bytes = (size_t)n * sizeof(float);
    float *h_x = (float *)malloc(bytes);
    float *h_y = (float *)malloc(bytes);
    if (!h_x || !h_y) { free(h_x); free(h_y); return -1; }

    for (int i = 0; i < n; i++) {
        h_x[i] = 1.0f;
        h_y[i] = 2.0f;
    }

    float *d_x, *d_y;
    err = cudaMalloc(&d_x, bytes);
    if (err != cudaSuccess) { free(h_x); free(h_y); return -1; }
    err = cudaMalloc(&d_y, bytes);
    if (err != cudaSuccess) { cudaFree(d_x); free(h_x); free(h_y); return -1; }

    cudaMemcpy(d_x, h_x, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_y, h_y, bytes, cudaMemcpyHostToDevice);

    int threads = 256;
    int blocks = (n + threads - 1) / threads;

    // Warmup
    for (int i = 0; i < 10; i++)
        saxpy<<<blocks, threads>>>(n, 2.0f, d_x, d_y);
    cudaDeviceSynchronize();

    // Benchmark 1: SAXPY (memory-bound)
    double t0 = get_time_ms();
    for (int i = 0; i < iterations; i++)
        saxpy<<<blocks, threads>>>(n, 2.0f, d_x, d_y);
    cudaDeviceSynchronize();
    double t1 = get_time_ms();

    double elapsed_s = (t1 - t0) / 1000.0;
    result->saxpy_gflops = (2.0 * (double)n * iterations) / (elapsed_s * 1e9);
    result->alloc_bw_gbps = (3.0 * bytes * iterations) / (elapsed_s * 1e9);

    // Benchmark 2: Compute-heavy (SM-bound)
    cudaMemcpy(d_y, h_y, bytes, cudaMemcpyHostToDevice);

    int fma_reps = 200;
    for (int i = 0; i < 5; i++)
        compute_heavy<<<blocks, threads>>>(n, d_y, fma_reps);
    cudaDeviceSynchronize();

    int heavy_iters = iterations / 2;
    t0 = get_time_ms();
    for (int i = 0; i < heavy_iters; i++)
        compute_heavy<<<blocks, threads>>>(n, d_y, fma_reps);
    cudaDeviceSynchronize();
    t1 = get_time_ms();

    elapsed_s = (t1 - t0) / 1000.0;
    result->heavy_gflops = (2.0 * fma_reps * (double)n * heavy_iters) / (elapsed_s * 1e9);

    cudaFree(d_x);
    cudaFree(d_y);
    free(h_x);
    free(h_y);
    return 0;
}

static int enumerate_devices(int *count) {
    cudaError_t err = cudaGetDeviceCount(count);
    if (err != cudaSuccess) {
        fprintf(stderr, "cudaGetDeviceCount failed: %s\n",
                cudaGetErrorString(err));
        fprintf(stderr, "CUDA_VISIBLE_DEVICES=%s\n",
                getenv("CUDA_VISIBLE_DEVICES") ? getenv("CUDA_VISIBLE_DEVICES") : "(unset)");
        fprintf(stderr, "Falling back to nvidia-smi:\n");
        system("nvidia-smi -L 2>/dev/null");
        return -1;
    }
    return 0;
}

int main() {
    printf("====== Asymmetric MIG CUDA Stress (Exclusive vs MPS 30%%) ======\n\n");

    const char *cvd = getenv("CUDA_VISIBLE_DEVICES");
    printf("CUDA_VISIBLE_DEVICES = %s\n\n", cvd ? cvd : "(unset)");

    int device_count = 0;
    if (enumerate_devices(&device_count) != 0) return 1;

    printf("CUDA device count: %d\n\n", device_count);
    if (device_count == 0) {
        fprintf(stderr, "No CUDA devices found.\n");
        system("nvidia-smi -L 2>/dev/null");
        return 1;
    }

    // Phase 1: Device properties
    printf("--- Phase 1: Device Properties ---\n");
    for (int i = 0; i < device_count; i++) {
        cudaDeviceProp prop;
        if (cudaGetDeviceProperties(&prop, i) != cudaSuccess) continue;
        printf("\n[Device %d] %s\n", i, prop.name);
        printf("  Compute: %d.%d | SMs: %d | Clock: %d MHz\n",
               prop.major, prop.minor, prop.multiProcessorCount,
               prop.clockRate / 1000);
        printf("  Memory: %.1f MiB | Bus width: %d-bit | Mem clock: %d MHz\n",
               (double)prop.totalGlobalMem / (1024.0 * 1024.0),
               prop.memoryBusWidth, prop.memoryClockRate / 1000);

        if (cudaSetDevice(i) == cudaSuccess) {
            size_t free_mem, total_mem;
            if (cudaMemGetInfo(&free_mem, &total_mem) == cudaSuccess) {
                printf("  Free memory: %.1f / %.1f MiB\n",
                       (double)free_mem / (1024.0 * 1024.0),
                       (double)total_mem / (1024.0 * 1024.0));
            }
        }
    }

    // Phase 2: Benchmarks
    int n = 1 << 22;
    int iterations = 500;

    printf("\n--- Phase 2: Per-Device Benchmarks ---\n");
    printf("  Vector size: %d elements (%zu MiB), iterations: %d\n\n",
           n, (size_t)n * sizeof(float) / (1024 * 1024), iterations);

    bench_result_t *results = (bench_result_t *)calloc(device_count, sizeof(bench_result_t));

    for (int i = 0; i < device_count; i++) {
        printf("[Device %d] Running benchmarks...\n", i);
        int rc = run_full_benchmark(i, n, iterations, &results[i]);
        if (rc != 0) {
            printf("[Device %d] FAILED\n\n", i);
            continue;
        }
        printf("[Device %d] SAXPY:     %8.2f GFlop/s  (mem BW: %.1f GB/s)\n",
               i, results[i].saxpy_gflops, results[i].alloc_bw_gbps);
        printf("[Device %d] Compute:   %8.2f GFlop/s\n\n",
               i, results[i].heavy_gflops);
    }

    // Phase 3: Comparison
    if (device_count >= 2) {
        printf("--- Phase 3: Exclusive vs MPS Comparison ---\n");
        printf("  Device 0 = Exclusive MIG (no sharing)\n");
        printf("  Device 1 = MPS 30%% MIG\n\n");

        double saxpy_ratio = 0, heavy_ratio = 0;
        if (results[0].saxpy_gflops > 0 && results[1].saxpy_gflops > 0) {
            saxpy_ratio = results[1].saxpy_gflops / results[0].saxpy_gflops * 100.0;
        }
        if (results[0].heavy_gflops > 0 && results[1].heavy_gflops > 0) {
            heavy_ratio = results[1].heavy_gflops / results[0].heavy_gflops * 100.0;
        }

        printf("                   Exclusive    MPS 30%%     Ratio\n");
        printf("  SAXPY GFlop/s:   %8.2f    %8.2f    %5.1f%%\n",
               results[0].saxpy_gflops, results[1].saxpy_gflops, saxpy_ratio);
        printf("  Compute GFlop/s: %8.2f    %8.2f    %5.1f%%\n",
               results[0].heavy_gflops, results[1].heavy_gflops, heavy_ratio);
        printf("  Mem BW GB/s:     %8.1f    %8.1f\n",
               results[0].alloc_bw_gbps, results[1].alloc_bw_gbps);

        printf("\n--- Analysis ---\n");
        if (heavy_ratio > 0) {
            if (heavy_ratio < 50.0) {
                printf("  MPS 30%% shows significant compute throttling (%.1f%% of exclusive).\n", heavy_ratio);
                printf("  MPS thread percentage IS effectively limiting SM usage.\n");
            } else if (heavy_ratio < 80.0) {
                printf("  MPS 30%% shows moderate throttling (%.1f%% of exclusive).\n", heavy_ratio);
                printf("  MPS limits are partially effective.\n");
            } else {
                printf("  MPS 30%% shows minimal throughput difference (%.1f%% of exclusive).\n", heavy_ratio);
                printf("  Possible causes: workload is memory-bound, not enough SM pressure,\n");
                printf("  or MPS thread limit does not constrain this workload.\n");
            }
        }

        if (saxpy_ratio > 0 && heavy_ratio > 0) {
            printf("\n  SAXPY (memory-bound) ratio: %.1f%%\n", saxpy_ratio);
            printf("  Compute (SM-bound) ratio:   %.1f%%\n", heavy_ratio);
            if (saxpy_ratio > heavy_ratio + 10.0) {
                printf("  => MPS primarily limits compute (SM threads), not memory bandwidth.\n");
            } else if (heavy_ratio > saxpy_ratio + 10.0) {
                printf("  => Both compute and memory are affected similarly by MPS limits.\n");
            } else {
                printf("  => Compute and memory throughput affected equally.\n");
            }
        }
    } else {
        printf("\n(Need >= 2 devices for comparison)\n");
    }

    printf("\n====== Test Complete ======\n");
    free(results);
    return 0;
}
