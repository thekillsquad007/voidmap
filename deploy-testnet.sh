#!/usr/bin/env bash
set -u

echo "◆ Voidmap Testnet Deploy (Base Sepolia)"
echo "  Chain ID: 84532"
echo ""

: "${DEPLOYER_PK:?Set DEPLOYER_PK}"

RPC_URL="${RPC_URL:-https://sepolia.base.org}"
DEPLOY_OUT="deploy-testnet.json"

cd "$(dirname "$0")/contracts"
export PATH="$HOME/.foundry/bin:$HOME/.var/app/ai.opencode.opencode/config/.foundry/bin:$PATH"

DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PK" | tr -d '[:space:]')
DEV_ADDR="${DEV_ADDR:-$DEPLOYER}"
DAO_ADDR="${DAO_ADDR:-$DEV_ADDR}"

echo "  Deployer: $DEPLOYER"
echo "  Dev fund: $DEV_ADDR"
echo "  DAO fund: $DAO_ADDR"

echo ""
echo "◆ Step 1/5: Building contracts..."
forge build --skip "lib/openzeppelin-contracts/fv" --sizes 2>&1 | tail -3

BALANCE=$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL" || echo "0")
echo "  Balance: $(cast from-wei "$BALANCE" 2>/dev/null || echo "$BALANCE") ETH"

echo ""
echo "◆ Step 2/5: Deploying VoidmapToken..."
printf "%s\n%s\n" "$DEV_ADDR" "$DAO_ADDR" > /tmp/voidmap-token-args.txt
TOKEN_RAW=$(forge create VoidmapToken.sol:VoidmapToken \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PK" \
    --constructor-args-path /tmp/voidmap-token-args.txt \
    --broadcast \
    --json 2>&1 || true)
echo "$TOKEN_RAW"
TOKEN_ADDR=$(echo "$TOKEN_RAW" | jq -r '.deployedTo // empty' 2>/dev/null || echo "")
if [ -z "$TOKEN_ADDR" ]; then
    echo "  ✗ Token deployment failed"
    exit 1
fi
echo "  Token: $TOKEN_ADDR"

echo ""
echo "◆ Step 3/5: Deploying MiningPool..."
printf "%s\n" "$TOKEN_ADDR" > /tmp/voidmap-pool-args.txt
POOL_RAW=$(forge create MiningPool.sol:MiningPool \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PK" \
    --constructor-args-path /tmp/voidmap-pool-args.txt \
    --broadcast \
    --json 2>&1 || true)
echo "$POOL_RAW"
POOL_ADDR=$(echo "$POOL_RAW" | jq -r '.deployedTo // empty' 2>/dev/null || echo "")
if [ -z "$POOL_ADDR" ]; then
    echo "  ✗ Pool deployment failed"
    exit 1
fi
echo "  Pool: $POOL_ADDR"

echo ""
echo "◆ Step 4/5: Transferring token ownership to MiningPool..."
cast send "$TOKEN_ADDR" "transferOwnership(address)" "$POOL_ADDR" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" || echo "  ⚠ Ownership transfer may have failed"

echo ""
echo "◆ Step 5/5: Verifying deployment..."
SYMBOL=$(cast call "$TOKEN_ADDR" "symbol()(string)" --rpc-url "$RPC_URL" 2>/dev/null || echo "?")
OWNER=$(cast call "$TOKEN_ADDR" "owner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "?")
echo "  Symbol: $SYMBOL"
echo "  Owner:  $OWNER"

echo ""
echo "══════════════════════════════════════════════════"
echo "  VoidmapToken  : $TOKEN_ADDR"
echo "  MiningPool    : $POOL_ADDR"
echo "  Dev Fund      : $DEV_ADDR"
echo "  DAO/Treasury  : $DAO_ADDR"
echo "══════════════════════════════════════════════════"

jq -n \
    --arg token "$TOKEN_ADDR" \
    --arg pool "$POOL_ADDR" \
    --arg dev "$DEV_ADDR" \
    --arg dao "$DAO_ADDR" \
    --arg deployer "$DEPLOYER" \
    --arg rpc "$RPC_URL" \
    '{token: $token, pool: $pool, dev: $dev, dao: $dao, deployer: $deployer, rpc: $rpc}' \
    > "$DEPLOY_OUT" 2>/dev/null || true
echo "  Saved to contracts/$DEPLOY_OUT"
