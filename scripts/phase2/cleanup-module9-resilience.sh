#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Module 9 Cleanup: Resilience ===${NC}"

kubectl delete pod pod-resilience pod-owner pod-admin pod-victim pod-survivor pod-driver-victim pod-driver-survivor --ignore-not-found --wait=false 2>/dev/null || true
kubectl delete resourceclaim claim-resilience claim-owner claim-admin claim-victim claim-survivor claim-driver-victim claim-driver-survivor claim-ref claim-ref-1 --ignore-not-found --wait=false 2>/dev/null || true

echo "Waiting for resources to terminate..."
kubectl wait --for=delete pod pod-resilience pod-victim pod-survivor pod-driver-victim pod-driver-survivor --timeout=60s 2>/dev/null || true

echo -e "${GREEN}✅ Module 9 Cleaned${NC}"
