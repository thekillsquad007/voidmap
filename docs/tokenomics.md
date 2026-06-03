# Tokenomics

## Token Overview

| Property | Value |
|----------|-------|
| Name | Voidmap |
| Symbol | VOID |
| Standard | ERC-20 |
| Chain | Base (L2) |
| Total Supply | 1,000,000,000 VOID |
| Decimals | 18 |

---

## Token Distribution

| Allocation | Percentage | Amount | Purpose |
|------------|------------|--------|---------|
| GPU Miners | 90% | 900,000,000 VOID | Rewards for useful computation |
| Developer Fund | 5% | 50,000,000 VOID | Development, audits, partnerships |
| Treasury | 5% | 50,000,000 VOID | Community grants, ecosystem |

---

## Emission Schedule

### GPU Miner Rewards (90%)

- **Total**: 900,000,000 VOID
- **Distribution**: Continuous, based on work submitted
- **Quality-based**: Higher quality work earns more VOID
- **No halving**: Rewards scale with quality, not time

### Reward Calculation

```
reward = BASE_REWARD × quality × multiplier

Where:
- BASE_REWARD = 1 VOID per quality point
- quality = 50-100 (from model metrics)
- multiplier:
  - 50-69: 1x (base)
  - 70-89: 1.2x (good)
  - 90-100: 1.5x (excellent)
```

### Example Rewards

| Quality | Multiplier | VOID Earned |
|---------|------------|-------------|
| 50 | 1x | 50 VOID |
| 70 | 1.2x | 84 VOID |
| 90 | 1.5x | 135 VOID |
| 100 | 1.5x | 150 VOID |

---

## Developer Fund (5%)

- **Amount**: 50,000,000 VOID
- **Vesting**: 4 years
- **Cliff**: None
- **Release**: Linear monthly unlock
- **Transparency**: All addresses published at genesis

### Vesting Schedule

```
Month 1:   1,041,666 VOID released
Month 12:  12,500,000 VOID released
Month 24:  25,000,000 VOID released
Month 48:  50,000,000 VOID released (fully vested)
```

---

## Treasury (5%)

- **Amount**: 50,000,000 VOID
- **Control**: Future DAO governance
- **Use cases**:
  - Community grants for researchers
  - Bounties for new ML models
  - Partnership incentives
  - Ecosystem development

---

## Why 90% to Miners?

Traditional crypto projects allocate 20-40% to miners. We chose 90% because:

1. **The computation IS the product** — miners produce scientifically valuable data
2. **No company taking a cut** — no 20% VC allocation, no 10% marketing budget
3. **Transparent** — all allocation visible on-chain
4. **Incentive aligned** — miners earn directly for useful work

---

## Token Utility

VOID is used for:

1. **Mining rewards** — earned for processing astronomical data
2. **Pool fees** — 2% fee on pool submissions
3. **Governance** — future DAO voting on task selection
4. **Staking** — future feature for quality guarantees

---

## Contract Details

### VoidmapToken.sol

```solidity
// Key functions:
function mintMinerReward(address miner, uint256 amount, uint256 taskId, uint256 quality)
function devClaim(address dev) // linear 4-year vesting
function renounce() // ownership renounced after deployment
```

### MiningPool.sol

```solidity
// Key functions:
function submitWork(...) // submit mining results
function createPool(...) // create a mining pool
function addPoolMember(...) // add miner to pool
```

---

## Deployment

```bash
# Deploy to Base
export DEPLOYER_PK=0x...  # needs ~$0.50 ETH on Base
export DEV_ADDR=0x...      # your wallet
bash deploy.sh

# After deployment:
# 1. MiningPool becomes token minter
# 2. Ownership renounced (immutable)
# 3. 90% allocated to miners via MiningPool
```

---

## No Rug Pull

- **Ownership renounced** — no one can modify the token
- **90% to miners** — no hidden allocations
- **Transparent vesting** — dev fund addresses public
- **No company** — just open-source code
