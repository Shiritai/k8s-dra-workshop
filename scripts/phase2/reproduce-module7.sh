#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "=== Reproduce Module 7 Results (End-to-End) ==="
echo "Logs will be available in the terminal."

# 1. Setup Kind Cluster (Module 1)
echo ">>> Step 1: Setting up Kind Cluster..."
"$WORKSHOP_DIR/scripts/phase1/run-module1-setup-kind.sh"

# 2. Install Driver (Module 2)
echo ">>> Step 2: Installing NVIDIA DRA Driver..."
"$WORKSHOP_DIR/scripts/phase1/run-module2-install-driver.sh"

# 3. Run Module 7 Verification
echo ">>> Step 3: Running Module 7 Verification (with RBAC Fix)..."
"$WORKSHOP_DIR/scripts/phase2/run-module7-consumable-capacity.sh"

echo "=== Reproduction Complete ==="
