#!/usr/bin/env bash
set -euo pipefail

echo "◆ Voidmap Deploy (Base Mainnet)"
echo ""

: "${DEPLOYER_PK:?Set DEPLOYER_PK}"
: "${DEV_ADDR:?Set DEV_ADDR}"
DAO_ADDR="${DAO_ADDR:-$DEV_ADDR}"
RPC_URL="${RPC_URL:-https://mainnet.base.org}"

cd "$(dirname "$0")/contracts"
export PATH="$HOME/.foundry/bin:$HOME/.var/app/ai.opencode.opencode/config/.foundry/bin:$PATH"

DEV_ADDR=$(echo "$DEV_ADDR" | tr -d '[:space:]')
DAO_ADDR=$(echo "$DAO_ADDR" | tr -d '[:space:]')

forge build --skip "lib/openzeppelin-contracts/fv" --sizes 2>&1 | tail -3

echo "◆ Deploying VoidmapToken..."
printf "%s\n%s\n" "$DEV_ADDR" "$DAO_ADDR" > /tmp/voidmap-token-args.txt
TOKEN_RAW=$(forge create VoidmapToken.sol:VoidmapToken \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PK" \
    --constructor-args-path /tmp/voidmap-token-args.txt \
    --broadcast \
    --json 2>&1 || true)
TOKEN_ADDR=$(echo "$TOKEN_RAW" | jq -r '.deployedTo // empty' 2>/dev/null || echo "")
if [ -z "$TOKEN_ADDR" ]; then
    echo "$TOKEN_RAW"
    echo "  ✗ Token deployment failed"
    exit 1
fi
echo "  Token: $TOKEN_ADDR"
rm -f /tmp/voidmap-token-args.txt

echo "◆ Deploying MiningPool..."
printf "%s\n" "$TOKEN_ADDR" > /tmp/voidmap-pool-args.txt
POOL_RAW=$(forge create MiningPool.sol:MiningPool \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PK" \
    --constructor-args-path /tmp/voidmap-pool-args.txt \
    --broadcast \
    --json 2>&1 || true)
POOL_ADDR=$(echo "$POOL_RAW" | jq -r '.deployedTo // empty' 2>/dev/null || echo "")
if [ -z "$POOL_ADDR" ]; then
    echo "$POOL_RAW"
    echo "  ✗ Pool deployment failed"
    exit 1
fi
echo "  Pool: $POOL_ADDR"
rm -f /tmp/voidmap-pool-args.txt

echo "◆ Setting MiningPool as minter..."
cast send "$TOKEN_ADDR" "transferOwnership(address)" "$POOL_ADDR" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK"

echo ""
echo "══════════════════════════════════════"
echo " VoidmapToken : $TOKEN_ADDR"
echo " MiningPool   : $POOL_ADDR"
echo " Dev Fund     : $DEV_ADDR (5% = 50M VOID, 4yr vesting)"
echo " DAO/Treasury : $DAO_ADDR (5% = 50M VOID)"
echo " Miners       : 90% of supply"
echo " Status       : MiningPool is the minter"
echo ""
echo " https://basescan.org/address/$TOKEN_ADDR"
echo " https://basescan.org/address/$POOL_ADDR"
echo "══════════════════════════════════════"
