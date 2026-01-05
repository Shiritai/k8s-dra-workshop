#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_success() { echo -e "${GREEN}✅  $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️   $1${NC}"; }
log_error()   { echo -e "${RED}❌  $1${NC}"; }

check_cmd() {
    local cmd=$1
    local label=${2:-$cmd}
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$label not found."
        return 1
    fi
    log_success "$label detected."
}

echo "=== 🔍 NVIDIA DRA Workshop: Environment Check ==="

# 1. Check Essential Tools
REQUIRED_TOOLS=(
    "nvidia-smi:NVIDIA Driver"
    "docker:Docker"
    "kind:Kind"
    "helm:Helm"
)

EXIT_CODE=0

for tool in "${REQUIRED_TOOLS[@]}"; do
    IFS=":" read -r binary name <<< "$tool"
    if ! check_cmd "$binary" "$name"; then
        EXIT_CODE=1
    fi
done

if [ $EXIT_CODE -ne 0 ]; then
    echo
    log_error "Missing required tools. Please install them and retry."
    exit 1
fi

# 2. Check Docker NVIDIA Runtime
if docker info 2>/dev/null | grep -q "Runtimes.*nvidia"; then
    log_success "Docker NVIDIA runtime detected."
else
    log_warn "NVIDIA runtime might not be configured in Docker."
    echo "    👉 Fix: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
fi

# 3. Check NVIDIA CTK (Optional but recommended)
if command -v nvidia-ctk &> /dev/null; then
    log_success "NVIDIA Container Toolkit (nvidia-ctk) detected."
else
    log_warn "nvidia-ctk not found (Recommended for CDI config verification)."
fi

# 4. Check MPS Control Daemon
if pgrep -f "nvidia-cuda-mps-control" >/dev/null; then
    echo -e "${GREEN}✅  MPS Control Daemon is running.${NC}"
else
    echo -e "${YELLOW}⚠️   MPS Control Daemon is NOT running.${NC}"
    echo "    (Required for Module 4 & 5. Run 'nvidia-cuda-mps-control -d' on host)"
fi

# 5. Check MPS Pipe Permissions
if [ -d "/tmp/nvidia-mps" ]; then
    if [ -r "/tmp/nvidia-mps" ] && [ -w "/tmp/nvidia-mps" ] && [ -x "/tmp/nvidia-mps" ]; then
         echo -e "${GREEN}✅  MPS Pipe Directory (/tmp/nvidia-mps) is accessible.${NC}"
    else
         echo -e "${YELLOW}⚠️   MPS Pipe Directory exists but may have permission issues.${NC}"
         echo "    (Try 'chmod -R 777 /tmp/nvidia-mps' if pods fail to connect)"
    fi
else
    echo -e "${YELLOW}⚠️   MPS Pipe Directory (/tmp/nvidia-mps) not found.${NC}"
fi

# 6. Check NVIDIA CTK CDI Config
if nvidia-ctk cdi list >/dev/null 2>&1; then
    echo -e "${GREEN}✅  NVIDIA CTK CDI is configured.${NC}"
else
    echo -e "${YELLOW}⚠️   NVIDIA CTK CDI config issue detected.${NC}"
    echo "    (Ensure 'nvidia-ctk cdi generate' has been run)"
fi

echo
echo "=== 🎉 Environment Check Passed! ==="
