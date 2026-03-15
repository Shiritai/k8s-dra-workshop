#!/bin/bash
set -e
echo "Starting all modules..."
./scripts/phase1/run-module0-check-env.sh
echo 'y' | ./scripts/phase1/run-module1-setup-kind.sh
./scripts/phase1/run-module2-install-driver.sh
./scripts/phase1/run-module3-verify-workload.sh
./scripts/phase1/run-module4-mps-basics.sh
./scripts/phase1/run-module5-mps-advanced.sh
./scripts/phase1/run-module6-vllm-verify.sh
./scripts/phase2/run-module7-consumable-capacity.sh
./scripts/phase2/run-module8-admin-access.sh
./scripts/phase2/run-module9-resilience.sh
echo "All modules completed successfully."
