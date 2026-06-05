# Tokenomics

## Token Overview

| Property | Value |
|----------|-------|
| Name | Voidmap |
| Symbol | VOID |
| Standard | ERC-20 |
| Chain | Base (L2) |
| Total Supply | 1,000,000,000 VOID (fixed, immutable) |
| Decimals | 18 |
| Owner | None (ownerless from day one) |
| Minter | MiningPool (locked after one-time `migrateMinter()`) |

---

## Token Distribution (at Deploy)

| Allocation | Percentage | Amount | Vesting |
|------------|------------|--------|---------|
| GPU Miners | 90% | 900,000,000 VOID | Halving schedule (continuous) |
| Developer Fund | 5% | 50,000,000 VOID | 4 years linear |
| Treasury/DAO | 5% | 50,000,000 VOID | None (unlocked at genesis) |

**No inflation.** `MAX_SUPPLY = 1,000,000,000 × 10¹⁸` is enforced in the contract.

---

## Halving Schedule (Bitcoin-Inspired)

Block reward starts at 50 VOID and **halves every 210,000 submissions**.

| Epoch | Subscriptions | Block Reward | Total Issued in Epoch |
|-------|--------------|--------------|----------------------|
| 0 | 0 – 209,999 | 50 VOID | 10,500,000 VOID |
| 1 | 210,000 – 419,999 | 25 VOID | 5,250,000 VOID |
| 2 | 420,000 – 629,999 | 12.5 VOID | 2,625,000 VOID |
| 3 | 630,000 – 839,999 | 6.25 VOID | 1,312,500 VOID |
| 4 | 840,000 – 1,049,999 | 3.125 VOID | 656,250 VOID |
| 5 | 1,050,000 – 1,259,999 | 1.5625 VOID | 328,125 VOID |
| 6 | 1,260,000 – 1,469,999 | 0.78125 VOID | 164,062.5 VOID |
| 7 | 1,470,000 – 1,679,999 | 0.390625 VOID | 82,031.25 VOID |
| 8 | 1,680,000 – 1,889,999 | 0.1953125 VOID | 41,015.625 VOID |
| 9 | 1,890,000+ | 0.1 VOID (floor) | 21,000 VOID / 210K subs |

`MIN_BLOCK_REWARD = 0.1 VOID` (no zero reward — every submission earns something).

**Note**: Actual issuance per epoch depends on quality, elastic multiplier, and pool fees. The table above shows maximum possible issuance at quality=100, no elastic adjustment, no pool fee.

### Halving Math

```
submissions_to_halving = 210,000
reward_after_n_halvings = INITIAL_BLOCK_REWARD / (2^n)
```

For example:
- After 1 halving: 50 / 2 = 25 VOID
- After 2 halvings: 50 / 4 = 12.5 VOID
- After 10 halvings: 50 / 1024 ≈ 0.0488 VOID → floored to 0.1 VOID

---

## Elastic Mint (Network Quality Adjustment)

The reward is scaled by an **elastic multiplier** based on the network's rolling 10-submission average quality. This prevents runaway issuance during high-quality periods and incentivizes more miners during low-quality periods.

### Formula

```
avgQuality = sum(qualityRing) / 10
TARGET_QUALITY = 75
EPSILON = 5  // dead zone

if avgQuality > TARGET + EPSILON:  // 80+
    multiplier = 100 - (excess * 2)
    floor: 80 (0.8x dampener)
elif avgQuality + EPSILON < TARGET:  // 70-
    multiplier = 100 + (deficit * 2)
    cap: 120 (1.2x boost)
else:
    multiplier = 100  // dead zone
```

### Examples

| Avg Quality | Multiplier | Effect |
|-------------|------------|--------|
| 50 | 160 (1.6x) | Boost (deficit = 20) → capped at 120 (1.2x) |
| 60 | 130 (1.3x) | Boost (deficit = 10) |
| 70 | 100 (1.0x) | Dead zone (within ±5) |
| 75 | 100 (1.0x) | Dead zone (target) |
| 80 | 100 (1.0x) | Dead zone (within ±5) |
| 85 | 90 (0.9x) | Dampener (excess = 5) |
| 90 | 80 (0.8x) | Dampener floor |

**Rationale**: When the network is doing well (high quality), slow down issuance to extend the supply runway. When the network is struggling (low quality), boost rewards to attract more miners.

---

## Reward Formula (Final)

```
reward = blockReward × quality × qualityMultiplier × elasticMultiplier
        ───────────────────────────────────────────────────────────
                              10 × 100
```

Where:
- `blockReward` = current halving-epoch reward (50 → 25 → 12.5 → ... → 0.1 VOID)
- `quality` = 50–100 (with deterministic noise floor applied)
- `qualityMultiplier` = 10 (base, 50-69), 12 (good, 70-89), 15 (excellent, 90-100)
- `elasticMultiplier` = 80–120 (0.8x–1.2x)

### Example Calculations

**Excellent work in epoch 0 (no elastic adjustment):**
```
quality = 95, qualityMultiplier = 15, elasticMultiplier = 100, blockReward = 50e18
reward = (50e18 × 95 × 15 × 100) / (10 × 100) = 7.125e21 wei = 7,125 VOID
```

**Good work with elastic boost:**
```
quality = 75, qualityMultiplier = 12, elasticMultiplier = 120 (low avg), blockReward = 25e18
reward = (25e18 × 75 × 12 × 120) / (10 × 100) = 2.7e22 wei = 27,000 VOID
```

**Base work with elastic dampener:**
```
quality = 60, qualityMultiplier = 10, elasticMultiplier = 80 (high avg), blockReward = 50e18
reward = (50e18 × 60 × 10 × 80) / (10 × 100) = 2.4e21 wei = 2,400 VOID
```

---

## Quality Tiers

| Quality Range | Tier | Multiplier | Status |
|---------------|------|------------|--------|
| < 50 | Rejected | — | Work not accepted, no reward |
| 50 – 69 | Accepted | 1.0x | Base reward |
| 70 – 89 | Good | 1.2x | 20% bonus |
| 90 – 100 | Excellent | 1.5x | 50% bonus |

Quality is derived from model confidence with a **deterministic noise factor** (0–9) computed from `keccak256(inputHash, outputHash, block.timestamp)`. This prevents gaming by submitting the same input multiple times.

---

## Developer Fund (5%)

- **Amount**: 50,000,000 VOID
- **Vesting**: 4 years, linear, no cliff
- **Release**: `devClaim(address to)` callable by dev fund address after vesting ends
- **Transparency**: All addresses published at genesis

### Vesting Schedule

```
Year 1:  12,500,000 VOID claimable (after vesting end)
Year 2:  25,000,000 VOID claimable
Year 3:  37,500,000 VOID claimable
Year 4:  50,000,000 VOID claimable (fully vested)
```

**Note**: Vesting ends 4 years after deploy timestamp. `devClaim` can be called once for the full balance at that point. No continuous streaming.

---

## Treasury (5%)

- **Amount**: 50,000,000 VOID
- **Control**: DAO/treasury multisig at genesis
- **Use cases**:
  - Community grants for researchers using the data
  - Bounties for new ML models
  - Partnership incentives
  - Ecosystem development
- **Unlock**: Available immediately at deploy

---

## Anti-Gaming Mechanisms

### Deterministic Noise

```
noise = keccak256(inputHash, outputHash, block.timestamp) % 10
quality -= noise  // floored at MIN_QUALITY
```

Miners can't predict the noise because it depends on `block.timestamp`. Different submissions get different noise values.

### Submission Cooldown

`SUBMISSION_COOLDOWN = 12 seconds` per miner. Prevents spam and limits the effective submission rate to 5/min per miner.

### Anti-ASIC Timing

`MIN_COMPUTE_DURATION = 2 seconds` enforced on-chain. Sub-2s results rejected.

### Challenge/Slash

`SLASH_BPS = 20%` of submitter's reward slashed if quality is provably below floor (see [mainnet-features.md](Mainnet-Features)).

---

## Why 90% to Miners?

Traditional crypto projects allocate 20–40% to miners. We chose 90% because:

1. **The computation IS the product** — miners produce scientifically valuable data
2. **No company taking a cut** — no 20% VC allocation, no 10% marketing budget
3. **Transparent** — all allocation visible on-chain
4. **Incentive aligned** — miners earn directly for useful work
5. **No founder, no team allocation** — the protocol has no team to pay

---

## Token Utility

VOID is used for:

1. **Mining rewards** — earned for processing astronomical data
2. **Pool fees** — 2% fee on pool submissions
3. **Governance** — proposer stake for time-locked param changes
4. **Challenge bonds** — 1 VOID burned to challenge a submission
5. **Burns** — 50% of slashed amounts burned (deflationary pressure)

---

## Contract Details

### VoidmapToken (Ownerless)

```solidity
function migrateMinter(address newMinter) external;  // one-time only
function mintMinerReward(address miner, uint256 amount, uint256 taskId, uint256 quality) external;
function burnFromMiner(address from, uint256 amount) external;
function devClaim(address to) external;  // 4yr vesting
```

### MiningPool (Autonomous)

```solidity
// Halving
function getHalvingEpoch() external view returns (uint256);
function getHalvingProgress() external view returns (uint256, uint256, uint256);
function getCurrentBlockReward() external view returns (uint256);

// Elastic mint
function getAvgNetworkQuality() external view returns (uint256);
function getCurrentElasticMultiplier() external returns (uint256);

// Challenge / Slash
function fileChallenge(uint256 submissionId) external;
function resolveChallenge(uint256 challengeId) external;

// Time-locked governance
function stakeAsProposer(uint256 amount) external;
function proposeTimelock(bytes32 dataHash) external returns (bytes32);
function executeTimelock(bytes32 proposalId) external;
```

---

## No Rug, No Team, No Promises

- **No `Ownable`** — Token and pool are ownerless from day one
- **No multisig** — Protocol has no privileged signer
- **No upgrade path** — Contracts are not upgradeable
- **No team allocation** — 5% dev is vested 4 years, no team tokens
- **No VC allocation** — No pre-mine, no private sale
- **Halving is automatic** — Enforced in code, no human intervention
- **Total supply is fixed** — `MAX_SUPPLY = 1B` enforced in contract
- **No inflation** — No minting outside the MiningPool

The dev's only way to get VOID is by mining it (or by the 4-year dev vesting). The dev fund starts with 50M VOID (5% of supply) and can only be claimed after 4 years. The dev has no other control over the protocol.

**This is the most fair token launch possible. The code is the team.**
