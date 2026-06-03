#!/usr/bin/env bash
set -euo pipefail

# Voidmap Deploy Script
# Run from your distrobox:
#   bash deploy.sh
#
# Before running, set these environment variables:
#   DEPLOYER_PK=0x...       # Your wallet private key (with ETH on Base)
#   DEV_ADDR=0x...           # Your dev fund receive address (same for DAO)
#   RPC_URL=https://mainnet.base.org

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}◆ Voidmap Deploy${NC}"

# Check env vars
: "${DEPLOYER_PK:?Set DEPLOYER_PK to your deployer wallet private key}"
: "${DEV_ADDR:?Set DEV_ADDR to your dev fund / DAO treasury address}"
RPC_URL="${RPC_URL:-https://mainnet.base.org}"

cd "$(dirname "$0")/contracts"

echo -e "${GREEN}◆ Building contracts...${NC}"
forge build 2>&1 | tail -1

echo -e "${GREEN}◆ Deploying VoidmapToken...${NC}"
TOKEN=$(forge create \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  --constructor-args "$DEV_ADDR" "$DEV_ADDR" \
  VoidmapToken.sol:VoidmapToken \
  --json | jq -r '.deployedTo')
echo "  Token: $TOKEN"

echo -e "${GREEN}◆ Deploying DataMarketplace...${NC}"
MARKET=$(forge create \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  --constructor-args "$TOKEN" \
  DataMarketplace.sol:DataMarketplace \
  --json | jq -r '.deployedTo')
echo "  Market: $MARKET"

echo -e "${GREEN}◆ Deploying MiningPool...${NC}"
POOL=$(forge create \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  MiningPool.sol:MiningPool \
  --json | jq -r '.deployedTo')
echo "  Pool: $POOL"

echo -e "${GREEN}◆ Renouncing token ownership (immutable)...${NC}"
cast send "$TOKEN" "renounce()" \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK"
echo "  ✓ Token ownership renounced — nobody can change the supply"

echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Voidmap deployed!${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo "  VoidmapToken : $TOKEN"
echo "  Marketplace  : $MARKET"
echo "  MiningPool   : $POOL"
echo "  Chain        : Base"
echo "  Dev Fund     : $DEV_ADDR (120M + 150M VOID)"
echo "  Status       : Immutable (ownership renounced)"
echo ""
echo "  Update README.md with these addresses!"
