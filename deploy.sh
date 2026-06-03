#!/usr/bin/env bash
set -euo pipefail

echo "◆ Voidmap Deploy"
: "${DEPLOYER_PK:?Set DEPLOYER_PK}"
: "${DEV_ADDR:?Set DEV_ADDR}"
RPC_URL="${RPC_URL:-https://mainnet.base.org}"

cd "$(dirname "$0")/contracts"

export PATH="$HOME/.foundry/bin:$PATH"
forge build --skip "lib/openzeppelin-contracts/fv" --sizes 2>&1 | tail -3

echo "◆ Deploying VoidmapToken..."
TOKEN=$(forge create \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  --constructor-args "$DEV_ADDR" "$DEV_ADDR" \
  VoidmapToken.sol:VoidmapToken \
  --json | jq -r '.deployedTo')
echo "  Token: $TOKEN"

echo "◆ Deploying MiningPool..."
POOL=$(forge create \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  --constructor-args "$TOKEN" \
  MiningPool.sol:MiningPool \
  --json | jq -r '.deployedTo')
echo "  Pool: $POOL"

echo "◆ Setting MiningPool as minter..."
cast send "$TOKEN" "transferOwnership(address)" "$POOL" \
  --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK"

echo ""
echo "══════════════════════════════════════"
echo "  VoidmapToken : $TOKEN"
echo "  MiningPool   : $POOL"
echo "  Dev Fund     : $DEV_ADDR (5% = 50M VOID, 4yr vesting)"
echo "  Miners       : 90% of supply"
echo "  Status       : MiningPool is the minter"
echo ""
echo "  After deploy, verify on BaseScan:"
echo "  https://basescan.org/address/$TOKEN"
echo "  https://basescan.org/address/$POOL"
echo "══════════════════════════════════════"
