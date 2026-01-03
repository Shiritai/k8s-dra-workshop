#!/bin/bash
set -e

echo "=== Module 1 Cleanup: Teardown Kind Cluster ==="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Use common teardown script
"$ROOT_DIR/scripts/common/run-teardown.sh"

echo "✅ Module 1 Cleaned (Cluster Deleted)"
