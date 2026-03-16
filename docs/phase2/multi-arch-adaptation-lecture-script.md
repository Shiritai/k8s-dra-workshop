# Lecture Script: Adaptive Infrastructure for Heterogeneous Computing

## Slide 1: Title Slide
**Speaker Script**:
"Welcome to this special session of our NVIDIA DRA workshop. Today, we delve into a critical engineering challenge: **Multi-Architecture Adaptation**. As data centers transition towards heterogeneous computing—mixing x86_64 and AArch64 processors—how do we ensure our GPU-accelerated Kubernetes environment remains resilient and portable? Today, we will see how to build a 'Self-Adapting' infrastructure."

---

## Slide 2: The Architecture Gap
**Speaker Script**:
"Why is this hard? When we move from x86 to ARM, we face 'The Library Gap'. Linux distributions use different directory structures for libraries. In x86, it is `x86_64-linux-gnu`; in ARM, it is `aarch64-linux-gnu`. 

Most DRA drivers and Docker images are hard-coded for x86. If you run them on an ARM node, they simply won't find the NVIDIA Management Library (NVML), and your GPU becomes invisible to Kubernetes. Furthermore, ARM platforms often exhibit different timing during NVML initialization, leading to container start-up failures."

---

## Slide 3: Dynamic Discovery Strategy
**Speaker Script**:
"Our solution is **Dynamic Infrastructure Adaptation**. Instead of maintaining two separate sets of scripts, we use a 'Detect and Inject' pattern.

In our setup scripts, we call `uname -m` at the very beginning. We then use this information to decide which host paths to mount into our Kind nodes and pods. This ensures that whether you are on a laptop or a Grace Hopper supercomputer, the environment 'just works'."

---

## Slide 4: Patching the Driver - skipPrestart
**Speaker Script**:
"One of our biggest breakthroughs was the `skipPrestart` patch. On certain ARM instances, the standard NVIDIA pre-start check—which tries to handshake with the GPU before the container is even ready—can time out or fail with an 'Unknown Error'.

By implementing a `skipPrestart: true` toggle in our Helm chart specifically for ARM, we allow the driver to start first and then initialize NVML lazily. This small change in the initialization sequence is what makes the difference between a crash-looping pod and a stable production driver."

---

## Slide 5: Scheduler RBAC Fix
**Speaker Script**:
"Beyond simple path changes, we also addressed a core Kubernetes limitation. The default Kind scheduler often lacks the permissions to manage the new `resource.k8s.io` API group used by DRA.

We developed an supplemental RBAC fix that 'teaches' the scheduler how to handle `DeviceClasses` and `ResourceClaims`. This fix is architecture-independent but essential for making Dynamic Resource Allocation work reliably in a Kind-based lab environment."

---

## Slide 6: Results & Conclusion
**Speaker Script**:
"By applying these patches, we've transformed this workshop into a **Universal DRA Blueprint**. 
- We have 100% feature parity between ARM and x86.
- We have the same throughput results for workloads like vLLM.
- And most importantly, we have a unified codebase.

This proves that with the right abstraction and dynamic detection, high-performance computing on Kubernetes can be truly cross-platform. Let's start the hands-on and see the adaptation in action!"
