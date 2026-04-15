// Module 11-3a: Dual-MIG equal MPS CUDA stress test.
// Enumerates CUDA devices, benchmarks SAXPY per device,
// then runs concurrent multi-device benchmark via pthreads.

#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sys/time.h>

#define CHECK_CUDA(call) do { \
    cudaError_t err = (call); \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error at %s:%d — %s\n", \
                __FILE__, __LINE__, cudaGetErrorString(err)); \
        return -1; \
    } \
} while(0)

#define CHECK_CUDA_VOID(call) do { \
    cudaError_t err = (call); \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error at %s:%d — %s\n", \
                __FILE__, __LINE__, cudaGetErrorString(err)); \
        return; \
    } \
} while(0)

__global__ void saxpy(int n, float a, const float *x, float *y) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        y[i] = a * x[i] + y[i];
    }
}

static double get_time_ms() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

static double run_benchmark(int device_id, int n, int iterations) {
    cudaError_t err;

    err = cudaSetDevice(device_id);
    if (err != cudaSuccess) {
        fprintf(stderr, "  [Device %d] cudaSetDevice failed: %s\n",
                device_id, cudaGetErrorString(err));
        return -1.0;
    }

    size_t bytes = (size_t)n * sizeof(float);
    float *h_x = (float *)malloc(bytes);
    float *h_y = (float *)malloc(bytes);
    if (!h_x || !h_y) {
        fprintf(stderr, "  [Device %d] Host malloc failed\n", device_id);
        return -1.0;
    }

    for (int i = 0; i < n; i++) {
        h_x[i] = 1.0f;
        h_y[i] = 2.0f;
    }

    float *d_x = NULL, *d_y = NULL;
    int threads = 256;
    int blocks = (n + threads - 1) / threads;
    double t0, t1, elapsed_s, total_flops, gflops;

    err = cudaMalloc(&d_x, bytes);
    if (err != cudaSuccess) goto fail;
    err = cudaMalloc(&d_y, bytes);
    if (err != cudaSuccess) goto fail;

    cudaMemcpy(d_x, h_x, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_y, h_y, bytes, cudaMemcpyHostToDevice);

    // Warmup
    for (int i = 0; i < 5; i++) {
        saxpy<<<blocks, threads>>>(n, 2.0f, d_x, d_y);
    }
    cudaDeviceSynchronize();

    // Timed iterations
    t0 = get_time_ms();
    for (int i = 0; i < iterations; i++) {
        saxpy<<<blocks, threads>>>(n, 2.0f, d_x, d_y);
    }
    cudaDeviceSynchronize();
    t1 = get_time_ms();

    elapsed_s = (t1 - t0) / 1000.0;
    total_flops = 2.0 * (double)n * (double)iterations;
    gflops = total_flops / (elapsed_s * 1e9);

    cudaFree(d_x);
    cudaFree(d_y);
    free(h_x);
    free(h_y);
    return gflops;

fail:
    fprintf(stderr, "  [Device %d] cudaMalloc failed: %s\n",
            device_id, cudaGetErrorString(err));
    if (d_x) cudaFree(d_x);
    free(h_x);
    free(h_y);
    return -1.0;
}

typedef struct {
    int device_id;
    int n;
    int iterations;
    double gflops;
} thread_arg_t;

static void *bench_thread(void *arg) {
    thread_arg_t *ta = (thread_arg_t *)arg;
    ta->gflops = run_benchmark(ta->device_id, ta->n, ta->iterations);
    return NULL;
}

static int enumerate_devices(int *count) {
    cudaError_t err = cudaGetDeviceCount(count);
    if (err != cudaSuccess) {
        fprintf(stderr, "cudaGetDeviceCount failed: %s\n",
                cudaGetErrorString(err));
        fprintf(stderr, "Hint: CUDA_VISIBLE_DEVICES=%s\n",
                getenv("CUDA_VISIBLE_DEVICES") ? getenv("CUDA_VISIBLE_DEVICES") : "(unset)");
        fprintf(stderr, "Falling back to nvidia-smi enumeration...\n");
        int ret = system("nvidia-smi -L 2>/dev/null");
        if (ret != 0) {
            fprintf(stderr, "nvidia-smi also failed. No GPU visible.\n");
        }
        return -1;
    }
    return 0;
}

int main() {
    printf("====== Dual MIG CUDA Stress Test (Equal MPS 50%%) ======\n\n");

    const char *cvd = getenv("CUDA_VISIBLE_DEVICES");
    printf("CUDA_VISIBLE_DEVICES = %s\n\n", cvd ? cvd : "(unset)");

    int device_count = 0;
    if (enumerate_devices(&device_count) != 0) return 1;

    printf("CUDA device count: %d\n\n", device_count);
    if (device_count == 0) {
        fprintf(stderr, "No CUDA devices found. Trying nvidia-smi:\n");
        system("nvidia-smi -L 2>/dev/null");
        return 1;
    }

    // Phase 1: Enumerate and print device info
    printf("--- Phase 1: Device Information ---\n");
    for (int i = 0; i < device_count; i++) {
        cudaDeviceProp prop;
        CHECK_CUDA(cudaGetDeviceProperties(&prop, i));
        printf("\n[Device %d] %s\n", i, prop.name);
        printf("  Compute capability: %d.%d\n", prop.major, prop.minor);
        printf("  Total global memory: %.1f MiB\n",
               (double)prop.totalGlobalMem / (1024.0 * 1024.0));
        printf("  SMs: %d\n", prop.multiProcessorCount);
        printf("  Max threads/block: %d\n", prop.maxThreadsPerBlock);
        printf("  Clock rate: %d MHz\n", prop.clockRate / 1000);
        printf("  Memory clock: %d MHz\n", prop.memoryClockRate / 1000);

        printf("  (MIG slice presented as standalone CUDA device)\n");
    }

    // Phase 2: Sequential per-device benchmarks
    int n = 1 << 22;  // ~4M elements = 16 MiB per array
    int iterations = 500;

    printf("\n--- Phase 2: Sequential Per-Device Benchmark ---\n");
    printf("  Vector size: %d elements, iterations: %d\n\n", n, iterations);

    double *seq_gflops = (double *)calloc(device_count, sizeof(double));
    for (int i = 0; i < device_count; i++) {
        printf("[Device %d] Running SAXPY benchmark...\n", i);
        seq_gflops[i] = run_benchmark(i, n, iterations);
        if (seq_gflops[i] < 0) {
            printf("[Device %d] FAILED\n", i);
        } else {
            printf("[Device %d] Throughput: %.2f GFlop/s\n", i, seq_gflops[i]);
        }
    }

    double seq_total = 0;
    for (int i = 0; i < device_count; i++) {
        if (seq_gflops[i] > 0) seq_total += seq_gflops[i];
    }
    printf("\nSequential total: %.2f GFlop/s\n", seq_total);

    // Phase 3: Concurrent benchmark (all devices in parallel via pthreads)
    if (device_count >= 2) {
        printf("\n--- Phase 3: Concurrent Multi-Device Benchmark ---\n");

        thread_arg_t *args = (thread_arg_t *)calloc(device_count, sizeof(thread_arg_t));
        pthread_t *threads = (pthread_t *)calloc(device_count, sizeof(pthread_t));

        double t0 = get_time_ms();
        for (int i = 0; i < device_count; i++) {
            args[i].device_id = i;
            args[i].n = n;
            args[i].iterations = iterations;
            args[i].gflops = 0;
            pthread_create(&threads[i], NULL, bench_thread, &args[i]);
        }
        for (int i = 0; i < device_count; i++) {
            pthread_join(threads[i], NULL);
        }
        double t1 = get_time_ms();

        double conc_total = 0;
        for (int i = 0; i < device_count; i++) {
            if (args[i].gflops < 0) {
                printf("[Device %d] FAILED\n", i);
            } else {
                printf("[Device %d] Throughput: %.2f GFlop/s\n", i, args[i].gflops);
                conc_total += args[i].gflops;
            }
        }
        printf("\nConcurrent aggregate: %.2f GFlop/s\n", conc_total);
        printf("Wall-clock time: %.1f ms\n", t1 - t0);
        printf("Speedup vs sequential: %.2fx\n",
               conc_total > 0 && seq_total > 0 ? conc_total / seq_total : 0.0);

        free(args);
        free(threads);
    } else {
        printf("\n(Skipping concurrent test — need >= 2 devices)\n");
    }

    printf("\n====== Test Complete ======\n");
    free(seq_gflops);
    return 0;
}
