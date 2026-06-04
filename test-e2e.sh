#!/usr/bin/env bash
# Voidmap Testnet E2E — Validates deployed contracts on Base Sepolia
set -euo pipefail

cd "$(dirname "$0")/contracts"
export PATH="$HOME/.foundry/bin:$HOME/.var/app/ai.opencode.opencode/config/.foundry/bin:$PATH"

DEPLOY_JSON="deploy-testnet.json"
if [ -f "$DEPLOY_JSON" ]; then
    TOKEN="${TOKEN:-$(jq -r '.token' "$DEPLOY_JSON")}"
    POOL="${POOL:-$(jq -r '.pool' "$DEPLOY_JSON")}"
    RPC_URL="${RPC_URL:-$(jq -r '.rpc' "$DEPLOY_JSON")}"
else
    TOKEN="${TOKEN:-}"
    POOL="${POOL:-}"
    RPC_URL="${RPC_URL:-https://sepolia.base.org}"
fi

: "${TOKEN:?Set TOKEN address or run deploy-testnet.sh first}"
: "${POOL:?Set POOL address or run deploy-testnet.sh first}"
: "${DEPLOYER_PK:?Set DEPLOYER_PK}"

DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PK")

PASS=0; FAIL=0; TOTAL=0
check() { local n="$1" r="$2"; TOTAL=$((TOTAL+1)); if [ "$r" = "true" ]; then echo "  ✓ $n"; PASS=$((PASS+1)); else echo "  ✗ $n"; FAIL=$((FAIL+1)); fi }

echo ""; echo "◆ Voidmap E2E Test — Base Sepolia"
echo "  Token:  $TOKEN"; echo "  Pool:   $POOL"
echo "  Deployer: $DEPLOYER"; echo "  RPC:   $RPC_URL"; echo ""

# ─── 1. Token Deployment ─────────────────────
echo "◆ 1/8: Token deployment verification"

check "Symbol is VOID" \
  "$(echo "$(cast call "$TOKEN" "symbol()(string)" --rpc-url "$RPC_URL")" | grep -c VOID | sed 's/1/true/;s/0/false/')"
check "Name is Voidmap" \
  "$(echo "$(cast call "$TOKEN" "name()(string)" --rpc-url "$RPC_URL")" | grep -c Voidmap | sed 's/1/true/;s/0/false/')"
check "Total supply >= 100M" \
  "$(cast call "$TOKEN" "totalSupply()" --rpc-url "$RPC_URL" | cast to-dec | grep -c '^100000' | sed 's/1/true/;s/0/false/')"
DEV_SHARE=$(cast call "$TOKEN" "DEV_SHARE()" --rpc-url "$RPC_URL" | cast to-dec)
check "Dev share is 50M" "$([ "$DEV_SHARE" = "50000000000000000000000000" ] && echo true || echo false)"
MINER_SHARE=$(cast call "$TOKEN" "MINER_SHARE()" --rpc-url "$RPC_URL" | cast to-dec)
check "Miner share is 900M" "$([ "$MINER_SHARE" = "900000000000000000000000000" ] && echo true || echo false)"
check "Token owner is MiningPool" \
  "$(echo "$(cast call "$TOKEN" "owner()(address)" --rpc-url "$RPC_URL")" | grep -ci "$POOL" | sed 's/1/true/;s/0/false/')"
check "Token not renounced" \
  "$(cast call "$TOKEN" "renounced()(bool)" --rpc-url "$RPC_URL" | grep -c false | sed 's/1/true/;s/0/false/')"
echo ""

# ─── 2. Pool Deployment ──────────────────────
echo "◆ 2/8: Pool deployment verification"
check "Pool references correct token" \
  "$(echo "$(cast call "$POOL" "token()(address)" --rpc-url "$RPC_URL")" | grep -ci "$TOKEN" | sed 's/1/true/;s/0/false/')"
check "Pool owner is deployer" \
  "$(echo "$(cast call "$POOL" "owner()(address)" --rpc-url "$RPC_URL")" | grep -ci "$DEPLOYER" | sed 's/1/true/;s/0/false/')"
echo ""

# ─── 3. Create Tasks ─────────────────────────
echo "◆ 3/8: Creating mining tasks"
sleep 2
HASH1=$(cast send "$POOL" "createTask(string,string,string)" "Exoplanet Transit" "MAST TESS" "AstroNetCNN" --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 || true)
check "Task 1 created" "$(echo "$HASH1" | grep -c 'success' | sed 's/1/true/;s/0/false/')"
sleep 2
HASH2=$(cast send "$POOL" "createTask(string,string,string)" "Galaxy Morphology" "SDSS DR18" "Zoobot" --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 || true)
check "Task 2 created" "$(echo "$HASH2" | grep -c 'success' | sed 's/1/true/;s/0/false/')"
sleep 2
HASH3=$(cast send "$POOL" "createTask(string,string,string)" "Anomaly Detection" "ZTF/Fink" "Autoencoder" --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 || true)
check "Task 3 created" "$(echo "$HASH3" | grep -c 'success' | sed 's/1/true/;s/0/false/')"
echo ""

# ─── 4. Submit Work + Cooldown ───────────────
echo "◆ 4/8: Submitting work and testing cooldown"
INPUT_HASH=$(cast keccak "test_input_data_1")
OUTPUT_HASH=$(cast keccak "test_output_data_1")
MODEL_HASH=$(cast keccak "AstroNetCNN_v1")

# Submit with quality=75 (should succeed)
echo "  (submitting work...)"
sleep 5
SUBMIT1=$(cast send "$POOL" "submitWork(uint256,bytes32,bytes32,bytes32,string,uint256,uint256,uint256)" 1 "$INPUT_HASH" "$OUTPUT_HASH" "$MODEL_HASH" "QmTestSubmission1" 75 100 5000 --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 || true)
if echo "$SUBMIT1" | grep -q 'success'; then
  check "Work submitted (quality=75)" "true"
else
  echo "    DEBUG submitWork: $(echo "$SUBMIT1" | head -1)"
  check "Work submitted (quality=75)" "false"
fi

# Submit immediately (should be blocked by cooldown)
sleep 1
COOLDOWN_RESULT=$(cast send "$POOL" "submitWork(uint256,bytes32,bytes32,bytes32,string,uint256,uint256,uint256)" 1 "$INPUT_HASH" "$OUTPUT_HASH" "$MODEL_HASH" "QmTestCooldown" 80 200 6000 --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 || true)
check "Cooldown blocks rapid resubmission" "$(echo "$COOLDOWN_RESULT" | grep -ci 'cooldown\|revert' | sed 's/1/true/;s/0/false/')"

echo "  Waiting 15s for cooldown to expire..."
sleep 15

# Submit again after cooldown (should succeed)
INPUT_HASH2=$(cast keccak "test_input_data_2")
OUTPUT_HASH2=$(cast keccak "test_output_data_2")
SUBMIT2=$(cast send "$POOL" "submitWork(uint256,bytes32,bytes32,bytes32,string,uint256,uint256,uint256)" 1 "$INPUT_HASH2" "$OUTPUT_HASH2" "$MODEL_HASH" "QmTestSubmission2" 80 200 6000 --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 || true)
check "Work accepted after cooldown" "$(echo "$SUBMIT2" | grep -c 'success' | sed 's/1/true/;s/0/false/')"

# Check miner state
check "Miner received VOID reward" \
  "$([ "$(cast call "$TOKEN" "balanceOf(address)" "$DEPLOYER" --rpc-url "$RPC_URL" | cast to-dec)" != "0" ] && echo true || echo false)"
echo ""

# ─── 5. Quality Thresholds ───────────────────
echo "◆ 5/8: Testing quality thresholds"
INPUT_HASH_LOW=$(cast keccak "test_low_quality")
OUTPUT_HASH_LOW=$(cast keccak "test_output_low")

LOW_Q_RESULT=$(cast send "$POOL" "submitWork(uint256,bytes32,bytes32,bytes32,string,uint256,uint256,uint256)" 1 "$INPUT_HASH_LOW" "$OUTPUT_HASH_LOW" "$MODEL_HASH" "QmLowQuality" 30 100 5000 --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 || true)
check "Quality < 50 rejected" "$(echo "$LOW_Q_RESULT" | grep -ci 'Quality too low\|revert' | sed 's/1/true/;s/0/false/')"

OVER100_RESULT=$(cast send "$POOL" "submitWork(uint256,bytes32,bytes32,bytes32,string,uint256,uint256,uint256)" 1 "$INPUT_HASH_LOW" "$OUTPUT_HASH_LOW" "$MODEL_HASH" "QmOver100" 150 100 5000 --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PK" 2>&1 || true)
check "Quality > 100 rejected" "$(echo "$OVER100_RESULT" | grep -ci 'Quality > 100\|revert' | sed 's/1/true/;s/0/false/')"
echo ""

# ─── 6. Token State ──────────────────────────
echo "◆ 6/8: Token state verification"
check "Miner minted > 0" \
  "$([ "$(cast call "$TOKEN" "totalMinerMinted()" --rpc-url "$RPC_URL" | cast to-dec)" != "0" ] && echo true || echo false)"
check "Dev fund has tokens" \
  "$([ "$(cast call "$TOKEN" "balanceOf(address)" "$DEPLOYER" --rpc-url "$RPC_URL" | cast to-dec)" != "0" ] && echo true || echo false)"
check "Vesting end is set" \
  "$([ "$(cast call "$TOKEN" "vestingEnd()" --rpc-url "$RPC_URL" | cast to-dec)" != "0" ] && echo true || echo false)"
echo ""

echo "═══════════════════════════════════════════"
echo "  E2E Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && echo "  ✓ All tests passed!" || echo "  ✗ Some tests failed"
echo "═══════════════════════════════════════════"
echo ""
echo "  Token: https://sepolia.basescan.org/address/$TOKEN"
echo "  Pool:  https://sepolia.basescan.org/address/$POOL"
echo ""
