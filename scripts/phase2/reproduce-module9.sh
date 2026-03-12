#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}        Reproducing Module 9: Resilience            ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

echo -e "\n${GREEN}[Pre-flight] Cleaning up before starting tests...${NC}"
"$SCRIPT_DIR/cleanup-module9-resilience.sh"

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${GREEN}[1/3] Running Control Plane Driver Controller Failure Test...${NC}"
echo -e "${BLUE}====================================================${NC}\n"
"$SCRIPT_DIR/run-module9-resilience.sh"

echo -e "\n${GREEN}[2/3] Cleaning up between tests...${NC}"
"$SCRIPT_DIR/cleanup-module9-resilience.sh"

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${GREEN}[3/3] Running Data Plane MPS Failure Test...${NC}"
echo -e "${BLUE}====================================================${NC}\n"
"$SCRIPT_DIR/run-module9-resilience-mps.sh"

echo -e "\n${GREEN}[4/4] Cleaning up between tests...${NC}"
"$SCRIPT_DIR/cleanup-module9-resilience.sh"

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${GREEN}[5/5] Running Driver Daemon Failure Test...${NC}"
echo -e "${BLUE}====================================================${NC}\n"
"$SCRIPT_DIR/run-module9-resilience-driver.sh"

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}      ✅ All Module 9 Resilience Tests Passed!      ${NC}"
echo -e "${GREEN}====================================================${NC}\n"
