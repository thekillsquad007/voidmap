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
echo "◆ Step 1/7: Building contracts..."
forge build --sizes 2>&1 | tail -3

BALANCE=$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL" || echo "0")
echo "  Balance: $(cast from-wei "$BALANCE" 2>/dev/null || echo "$BALANCE") ETH"

# Deploy order:
#   1. ResultRegistry (no deps)
#   2. MiningPool (with token=placeholder, registry=ResultRegistry)
#   3. VoidmapToken (with dev, dao)
#   4. migrateMinter(pool)  -- lock minter
#   5. registry.setRecorder(pool) -- authorize pool
#   6. Bootstrap proposer (deployer stakes 1 VOID)
#   7. Create 3 default tasks

echo ""
echo "◆ Step 2/7: Deploying ResultRegistry..."
REGISTRY_RAW=$(forge create ResultRegistry.sol:ResultRegistry \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PK" \
    --broadcast \
    --json 2>&1 || true)
REGISTRY_ADDR=$(echo "$REGISTRY_RAW" | jq -r '.deployedTo // empty' 2>/dev/null || echo "")
if [ -z "$REGISTRY_ADDR" ]; then
    echo "  ✗ Registry deployment failed"
    exit 1
fi
echo "  Registry: $REGISTRY_ADDR"

echo ""
echo "◆ Step 3/7: Deploying MiningPool (placeholder token + registry)..."
printf "%s\n%s\n" "0x0000000000000000000000000000000000000000" "$REGISTRY_ADDR" > /tmp/voidmap-pool-args.txt
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
echo "◆ Step 4/7: Deploying VoidmapToken (minter=pool via migrateMinter)..."
printf "%s\n%s\n" "$DEV_ADDR" "$DAO_ADDR" > /tmp/voidmap-token-args.txt
TOKEN_RAW=$(forge create VoidmapToken.sol:VoidmapToken \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PK" \
    --constructor-args-path /tmp/voidmap-token-args.txt \
    --broadcast \
    --json 2>&1 || true)
TOKEN_ADDR=$(echo "$TOKEN_RAW" | jq -r '.deployedTo // empty' 2>/dev/null || echo "")
if [ -z "$TOKEN_ADDR" ]; then
    echo "  ✗ Token deployment failed"
    exit 1
fi
echo "  Token: $TOKEN_ADDR"

echo ""
echo "◆ Step 5/7: Locking minter + setting registry recorder..."
cast send "$TOKEN_ADDR" "migrateMinter(address)" "$POOL_ADDR" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true
cast send "$REGISTRY_ADDR" "setRecorder(address,bool)" "$POOL_ADDR" "true" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true

echo ""
echo "◆ Step 6/7: Bootstrapping proposer (initial proposer = deployer)..."
# Dev fund already has 5% of supply. Transfer 1 VOID to deployer and stake.
cast send "$TOKEN_ADDR" "transfer(address,uint256)" "$DEPLOYER" "1000000000000000000" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -2 || true
cast send "$TOKEN_ADDR" "approve(address,uint256)" "$POOL_ADDR" "1000000000000000000" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -2 || true

echo ""
echo "◆ Step 7/7: Creating default tasks..."
for TASK_INFO in \
    "Exoplanet Transit:MAST TESS SPOC:AstroNetCNN" \
    "Galaxy Morphology:SDSS DR18:GalaxyClassifier" \
    "Anomaly Detection:ZTF Fink:AnomalyDetector"; do
    NAME=$(echo "$TASK_INFO" | cut -d: -f1)
    SOURCE=$(echo "$TASK_INFO" | cut -d: -f2)
    SPEC=$(echo "$TASK_INFO" | cut -d: -f3)
    cast send "$POOL_ADDR" "stakeAsProposer(uint256)" "1000000000000000000" \
        --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true
    cast send "$POOL_ADDR" "createTask(string,string,string)" "$NAME" "$SOURCE" "$SPEC" \
        --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true
done

echo ""
echo "◆ Verifying deployment..."
SYMBOL=$(cast call "$TOKEN_ADDR" "symbol()(string)" --rpc-url "$RPC_URL" 2>/dev/null || echo "?")
MINTER=$(cast call "$TOKEN_ADDR" "minter()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "?")
TASKS=$(cast call "$POOL_ADDR" "taskCount()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null || echo "?")
echo "  Symbol: $SYMBOL"
echo "  Minter: $MINTER (should be pool)"
echo "  Tasks:  $TASKS"

echo ""
echo "══════════════════════════════════════════════════"
echo "  ResultRegistry: $REGISTRY_ADDR"
echo "  VoidmapToken  : $TOKEN_ADDR"
echo "  MiningPool    : $POOL_ADDR"
echo "  Dev Fund      : $DEV_ADDR"
echo "  DAO/Treasury  : $DAO_ADDR"
echo "  Tasks Created : $TASKS"
echo "══════════════════════════════════════════════════"

jq -n \
    --arg token "$TOKEN_ADDR" \
    --arg pool "$POOL_ADDR" \
    --arg registry "$REGISTRY_ADDR" \
    --arg dev "$DEV_ADDR" \
    --arg dao "$DAO_ADDR" \
    --arg deployer "$DEPLOYER" \
    --arg rpc "$RPC_URL" \
    '{token: $token, pool: $pool, registry: $registry, dev: $dev, dao: $dao, deployer: $deployer, rpc: $rpc}' \
    > "$DEPLOY_OUT" 2>/dev/null || true
echo "  Saved to contracts/$DEPLOY_OUT"
