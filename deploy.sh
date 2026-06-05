#!/usr/bin/env bash
set -euo pipefail

echo "◆ Voidmap Mainnet Deploy (Base)"
echo ""

: "${DEPLOYER_PK:?Set DEPLOYER_PK}"
: "${DEV_ADDR:?Set DEV_ADDR}"
DAO_ADDR="${DAO_ADDR:-$DEV_ADDR}"
RPC_URL="${RPC_URL:-https://mainnet.base.org}"

cd "$(dirname "$0")/contracts"
export PATH="$HOME/.foundry/bin:$HOME/.var/app/ai.opencode.opencode/config/.foundry/bin:$PATH"

DEV_ADDR=$(echo "$DEV_ADDR" | tr -d '[:space:]')
DAO_ADDR=$(echo "$DAO_ADDR" | tr -d '[:space:]')

forge build --sizes 2>&1 | tail -3

# Deploy order:
#   1. ResultRegistry (no deps)
#   2. MiningPool (with token=placeholder, registry=ResultRegistry)
#   3. VoidmapToken (with dev, dao)
#   4. migrateMinter(pool)  -- lock minter
#   5. registry.setRecorder(pool) -- authorize pool
#   6. Bootstrap proposer (deployer stakes 1 VOID)
#   7. Create 3 default tasks

echo ""
echo "◆ Step 1/4: Deploying ResultRegistry..."
REGISTRY_RAW=$(forge create ResultRegistry.sol:ResultRegistry \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PK" \
    --broadcast \
    --json 2>&1 || true)
REGISTRY_ADDR=$(echo "$REGISTRY_RAW" | jq -r '.deployedTo // empty' 2>/dev/null || echo "")
if [ -z "$REGISTRY_ADDR" ]; then
    echo "$REGISTRY_RAW"
    echo "  ✗ Registry deployment failed"
    exit 1
fi
echo "  Registry: $REGISTRY_ADDR"

echo ""
echo "◆ Step 2/4: Deploying MiningPool (placeholder token + registry)..."
printf "%s\n%s\n" "0x0000000000000000000000000000000000000000" "$REGISTRY_ADDR" > /tmp/voidmap-pool-args.txt
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

echo ""
echo "◆ Step 3/4: Deploying VoidmapToken (ownerless)..."
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

echo ""
echo "◆ Step 4/4: Locking minter + setting recorder + bootstrapping..."
cast send "$TOKEN_ADDR" "migrateMinter(address)" "$POOL_ADDR" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true
cast send "$REGISTRY_ADDR" "setRecorder(address,bool)" "$POOL_ADDR" "true" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true
cast send "$TOKEN_ADDR" "transfer(address,uint256)" "$DEPLOYER" "1000000000000000000" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true
cast send "$TOKEN_ADDR" "approve(address,uint256)" "$POOL_ADDR" "1000000000000000000" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true
cast send "$POOL_ADDR" "stakeAsProposer(uint256)" "1000000000000000000" \
    --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true

# Create the 3 default tasks
for TASK_INFO in \
    "Exoplanet Transit:MAST TESS SPOC:AstroNetCNN" \
    "Galaxy Morphology:SDSS DR18:GalaxyClassifier" \
    "Anomaly Detection:ZTF Fink:AnomalyDetector"; do
    NAME=$(echo "$TASK_INFO" | cut -d: -f1)
    SOURCE=$(echo "$TASK_INFO" | cut -d: -f2)
    SPEC=$(echo "$TASK_INFO" | cut -d: -f3)
    cast send "$POOL_ADDR" "createTask(string,string,string)" "$NAME" "$SOURCE" "$SPEC" \
        --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 | tail -1 || true
done

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ResultRegistry: $REGISTRY_ADDR"
echo "  VoidmapToken  : $TOKEN_ADDR"
echo "  MiningPool    : $POOL_ADDR"
echo "  Dev Fund      : $DEV_ADDR (5% = 50M VOID, 4yr vesting)"
echo "  DAO/Treasury  : $DAO_ADDR (5% = 50M VOID)"
echo "  Miners        : 90% of supply (900M VOID, halving every 210K subs)"
echo "  Token Owner   : NONE (ownerless from day one)"
echo "  Pool Minter   : MiningPool (only minter)"
echo "  Registry      : ResultRegistry (queryable scientific record)"
echo ""
echo "  https://basescan.org/address/$TOKEN_ADDR"
echo "  https://basescan.org/address/$POOL_ADDR"
echo "  https://basescan.org/address/$REGISTRY_ADDR"
echo "══════════════════════════════════════════════════════════════"
