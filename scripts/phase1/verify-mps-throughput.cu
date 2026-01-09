#include <cuda_runtime.h>
#include <iostream>
#include <chrono>
#include <vector>

#define CHECK_CUDA(call) { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        std::cerr << "CUDA Error: " << cudaGetErrorString(err) << " at line " << __LINE__ << std::endl; \
        exit(1); \
    } \
}

__global__ void matmul_kernel(const float* A, const float* B, float* C, int N) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (row < N && col < N) {
        float sum = 0.0f;
        for (int k = 0; k < N; ++k) {
            sum += A[row * N + k] * B[k * N + col];
        }
        C[row * N + col] = sum;
    }
}

int main(int argc, char** argv) {
    int N = 4096; 
    int iterations = 5;
    if (argc > 1) N = std::atoi(argv[1]);
    if (argc > 2) iterations = std::atoi(argv[2]);

    size_t size = (size_t)N * N * sizeof(float);
    std::cout << "Allocating " << size / (1024*1024) << " MB for 3 matrices..." << std::endl;

    float *d_A, *d_B, *d_C;
    CHECK_CUDA(cudaMalloc(&d_A, size));
    CHECK_CUDA(cudaMalloc(&d_B, size));
    CHECK_CUDA(cudaMalloc(&d_C, size));

    dim3 threadsPerBlock(32, 32);
    dim3 numBlocks((N + threadsPerBlock.x - 1) / threadsPerBlock.x, (N + threadsPerBlock.y - 1) / threadsPerBlock.y);

    std::cout << "Testing Matrix Multiplication N=" << N << " (" << iterations << " iterations)..." << std::endl;

    // Warmup
    matmul_kernel<<<numBlocks, threadsPerBlock>>>(d_A, d_B, d_C, N);
    CHECK_CUDA(cudaGetLastError());
    CHECK_CUDA(cudaDeviceSynchronize());

    auto start = std::chrono::high_resolution_clock::now();

    for (int i = 0; i < iterations; ++i) {
        matmul_kernel<<<numBlocks, threadsPerBlock>>>(d_A, d_B, d_C, N);
    }
    CHECK_CUDA(cudaGetLastError());
    CHECK_CUDA(cudaDeviceSynchronize());

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> diff = end - start;

    double avg_time = diff.count() / iterations;
    double tflops = (2.0 * N * N * N) * 1e-12 / avg_time;

    std::cout << "Avg Time: " << avg_time << " s" << std::endl;
    std::cout << "Throughput: " << tflops << " TFLOPS" << std::endl;

    cudaFree(d_A);
    cudaFree(d_B);
    cudaFree(d_C);

    return 0;
}
