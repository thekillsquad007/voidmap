# Mainnet Features

This document describes the four core mechanisms that make Voidmap mainnet-grade: **Halving**, **Elastic Mint**, **Challenge/Slash**, and **Time-Locked Governance**. All four are enforced in the native Rust consensus (φ-PoW).

---

## 1. Halving Schedule

### Overview

Like Bitcoin, Voidmap's block reward halves every 210,000 accepted submissions. The schedule is encoded in the contract — no one can change it.

| Constant | Value |
|----------|-------|
| `HALVING_INTERVAL` | 210,000 submissions |
| `INITIAL_BLOCK_REWARD` | 50 VOID |
| `MIN_BLOCK_REWARD` | 0.1 VOID |

### Reward by Epoch

| Epoch | Submission Range | Block Reward | Epoch Total (max) |
|-------|------------------|--------------|-------------------|
| 0 | 0 – 209,999 | 50 VOID | 10,500,000 VOID |
| 1 | 210,000 – 419,999 | 25 VOID | 5,250,000 VOID |
| 2 | 420,000 – 629,999 | 12.5 VOID | 2,625,000 VOID |
| 3 | 630,000 – 839,999 | 6.25 VOID | 1,312,500 VOID |
| 4 | 840,000 – 1,049,999 | 3.125 VOID | 656,250 VOID |
| 5 | 1,050,000 – 1,259,999 | 1.5625 VOID | 328,125 VOID |
| 6 | 1,260,000 – 1,469,999 | 0.78125 VOID | 164,062.5 VOID |
| 7 | 1,470,000 – 1,679,999 | 0.390625 VOID | 82,031.25 VOID |
| 8 | 1,680,000 – 1,889,999 | 0.1953125 VOID | 41,015.625 VOID |
| 9+ | 1,890,000+ | 0.1 VOID (floor) | 21,000 VOID / 210K subs |

### Why Halving?

1. **Predictable supply** — Total miner-minted supply asymptotes to 900M VOID. At floor reward (0.1 VOID), it would take ~42,000 epochs (8.8 billion submissions) to issue the remaining supply. This creates **inherent scarcity**.
2. **No human decisions** — Halving is automatic. The supply schedule cannot be changed by a multisig, governance vote, or admin key.
3. **Long-term security** — The block reward floor (0.1 VOID) ensures miners are always incentivized, even when most of the supply is mined.

### Querying the Halving State

```solidity
// Get current epoch (0, 1, 2, ...)
function getHalvingEpoch() external view returns (uint256);

// Get full progress: epoch, submissions in epoch, next halving at
function getHalvingProgress() external view returns (
    uint256 epoch,
    uint256 submissionsInEpoch,
    uint256 nextHalvingAt
);

// Get current block reward in wei
function getCurrentBlockReward() external view returns (uint256);
```

```bash
# Cast examples
cast call $POOL "getHalvingEpoch()(uint256)" --rpc-url $RPC
cast call $POOL "getCurrentBlockReward()(uint256)" --rpc-url $RPC
```

### Halving Event

```solidity
event Halving(uint256 indexed epoch, uint256 newReward);
```

Emitted automatically when `submissionCount` crosses a halving boundary.

---

## 2. Elastic Mint

### Overview

The reward is scaled by an **elastic multiplier** based on the network's rolling 10-submission average quality. This prevents runaway issuance during high-quality periods and boosts rewards when quality drops.

### Constants

| Constant | Value |
|----------|-------|
| `ELASTICITY_WINDOW` | 10 submissions |
| `TARGET_QUALITY` | 75 |
| `QUALITY_EPSILON` | 5 (dead zone) |
| `MIN_ELASTIC_MULTIPLIER` | 80 (0.8x) |
| `MAX_ELASTIC_MULTIPLIER` | 120 (1.2x) |

### Algorithm

```solidity
// Ring buffer of last 10 qualities
uint256 public qualityRingIndex;
uint256[10] public qualityRing;
uint256 public qualityRingCount;

function getAvgNetworkQuality() public view returns (uint256) {
    if (qualityRingCount == 0) return TARGET_QUALITY;
    uint256 sum;
    for (uint256 i = 0; i < 10; i++) {
        sum += qualityRing[i];
    }
    return sum / 10;
}

function getCurrentElasticMultiplier() public returns (uint256) {
    uint256 avgQ = getAvgNetworkQuality();
    
    if (avgQ > TARGET_QUALITY + QUALITY_EPSILON) {
        // High quality — dampen
        uint256 excess = avgQ - (TARGET_QUALITY + QUALITY_EPSILON);
        uint256 multiplier = 100 - (excess * 2);
        return multiplier < MIN_ELASTIC_MULTIPLIER ? MIN_ELASTIC_MULTIPLIER : multiplier;
    } else if (avgQ + QUALITY_EPSILON < TARGET_QUALITY) {
        // Low quality — boost
        uint256 deficit = TARGET_QUALITY - (avgQ + QUALITY_EPSILON);
        uint256 multiplier = 100 + (deficit * 2);
        return multiplier > MAX_ELASTIC_MULTIPLIER ? MAX_ELASTIC_MULTIPLIER : multiplier;
    } else {
        // Dead zone
        return 100;
    }
}
```

### Examples

| Avg Quality | Calculation | Multiplier | Effect |
|-------------|-------------|------------|--------|
| 50 | deficit = 75 - (50+5) = 20, 100 + 40 = 140 → cap 120 | 120 (1.2x) | Max boost |
| 60 | deficit = 10, 100 + 20 = 120 | 120 (1.2x) | Max boost |
| 65 | deficit = 5, 100 + 10 = 110 | 110 (1.1x) | Boost |
| 70 | dead zone (70 + 5 = 75) | 100 (1.0x) | Neutral |
| 75 | target | 100 (1.0x) | Neutral |
| 80 | dead zone (80 - 5 = 75) | 100 (1.0x) | Neutral |
| 85 | excess = 5, 100 - 10 = 90 | 90 (0.9x) | Dampen |
| 90 | excess = 10, 100 - 20 = 80 | 80 (0.8x) | Floor dampen |

### Why Elastic Mint?

1. **Extends supply runway** — During high-quality periods, less VOID is issued per submission, slowing supply depletion.
2. **Incentivizes low-quality periods** — When miners are struggling (low quality), the boost attracts more participation.
3. **Self-balancing** — The network naturally converges to quality = 75 because both high and low quality are penalized.
4. **No governance needed** — The formula is fixed in code, no human can change it.

### Querying Elastic State

```solidity
// Average of last 10 submissions
function getAvgNetworkQuality() external view returns (uint256);

// Current elastic multiplier (in basis points: 80–120)
function getCurrentElasticMultiplier() external returns (uint256);
```

### Elastic Event

```solidity
event ElasticUpdate(uint256 avgQuality, uint256 multiplier, uint256 effectiveReward);
```

Emitted on every submission, showing the network state at that point.

---

## 3. Challenge / Slash

### Overview

Any miner can challenge a submission within **6 hours** of creation. If the submission is provably below the quality floor, the submitter is slashed.

### Constants

| Constant | Value |
|----------|-------|
| `CHALLENGE_WINDOW` | 6 hours |
| `CHALLENGE_BOND` | 1 VOID (burned on file) |
| `CHALLENGE_RESOLUTION_DELAY` | 1 hour |
| `SLASH_BPS` | 2000 (20% of submitter's reward) |
| `CHALLENGER_REWARD_BPS` | 5000 (50% of slash) |
| `BURN_BPS` | 5000 (50% of slash burned) |

### Flow

```
   T+0         T+6h              T+7h
   │            │                  │
   ▼            ▼                  ▼
Submission  Challenge    Resolution
created     window      delay
            closes      (1h after file)
```

### Filing a Challenge

```solidity
function fileChallenge(uint256 submissionId) external;
```

Reverts if:
- Submission doesn't exist
- Submission already challenged or resolved
- Challenge window expired (6h after creation)
- Caller is the submitter (can't challenge yourself)

Effects:
- **Burns 1 VOID** from the challenger's balance (bond)
- Marks submission as `challenged`
- Records `challengeTimestamp`

### Resolving a Challenge

```solidity
function resolveChallenge(uint256 challengeId) external;
```

Callable **1 hour** after `challengeTimestamp`. Anyone can call (not just the challenger).

Logic:
```solidity
if (submission.quality < 50) {
    // Challenger wins
    slashAmount = (submission.reward * 2000) / 10000;  // 20%
    challengerReward = (slashAmount * 5000) / 10000;   // 10% of submission reward
    burnAmount = slashAmount - challengerReward;        // 10% of submission reward burned
    
    token.mint(challenger, challengerReward);  // From minter
    token.burnFromMiner(submitter, burnAmount);
    submitterStats.minerSlashed += slashAmount;
} else {
    // Challenger loses — bond is forfeit
    // (1 VOID already burned at fileChallenge, no further action)
}
```

### Slash Distribution

When a challenger wins:

| Recipient | Amount | % |
|-----------|--------|---|
| Challenger | 10% of submission reward | 50% of slash |
| Burned (deflation) | 10% of submission reward | 50% of slash |
| Submitter (remaining) | 80% of submission reward | 0% of slash |

The submitter's *original* reward (80%) is still theirs — only the *slashed portion* (20%) is redistributed.

### Anti-Spam

- The 1 VOID challenge bond is **burned on file**, not held in escrow. This means spamming challenges costs real VOID, preventing Sybil attacks.
- The 1-hour resolution delay gives the submitter time to defend (in future: stake a counter-bond, request re-scoring by an oracle).
- The 6-hour challenge window prevents indefinite uncertainty.

### Events

```solidity
event ChallengeFiled(
    uint256 indexed challengeId,
    uint256 indexed submissionId,
    address challenger,
    uint256 bond  // always 1e18 (1 VOID)
);

event ChallengeResolved(
    uint256 indexed challengeId,
    uint256 indexed submissionId,
    bool challengerWon,
    uint256 slashAmount,
    uint256 burned
);

event Slashed(
    address indexed miner,
    uint256 amount,
    uint256 burned
);
```

### Querying Challenges

```solidity
function getChallenge(uint256 challengeId) external view returns (Challenge memory);

struct Challenge {
    uint256 submissionId;
    address challenger;
    uint256 challengeTimestamp;
    bool resolved;
    bool challengerWon;
}
```

---

## 4. Time-Locked Governance

### Overview

Parameter changes (new tasks, fee adjustments, etc.) require:
1. **Proposer stake** of at least 1% of total miner-minted VOID
2. **7-day delay** between proposal and execution
3. **Proposer votes** counted at proposal time (snapshot)

This prevents surprise changes, rug pulls, and admin key abuse.

### Constants

| Constant | Value |
|----------|-------|
| `TIMELOCK_DELAY` | 7 days |
| `PROPOSER_QUORUM_BPS` | 100 (1% of total miner-minted) |

### Becoming a Proposer

```solidity
function stakeAsProposer(uint256 amount) external;
```

Stakes `amount` VOID from caller. The caller becomes a proposer. Their staked VOID is locked.

**Quorum check**: `amount >= (totalMinerMinted * 100) / 10000`

For example, if `totalMinerMinted = 1,000,000 VOID`, you must stake at least `10,000 VOID` to be a proposer.

### Unstaking

```solidity
function unstakeProposer(uint256 amount) external;
```

Unstakes VOID and returns it to the caller. Removes proposer status if total stake drops below quorum.

### Proposing a Change

```solidity
function proposeTimelock(bytes32 dataHash) external returns (bytes32);
```

- Requires caller to be a proposer (stake ≥ quorum)
- `dataHash` = keccak256 of the encoded action data
- Records `eta = block.timestamp + 7 days`
- Records `proposerVotes = caller stake` (snapshot at proposal time)
- Returns `proposalId = keccak256(dataHash, block.timestamp, msg.sender)`

### Executing a Proposal

```solidity
function executeTimelock(bytes32 proposalId) external;
```

Callable by **anyone** (not just the proposer) after the 7-day delay.

Reverts if:
- Proposal doesn't exist
- `block.timestamp < eta` (delay not elapsed)
- Already executed
- Cancelled

Effects:
- Marks proposal as `executed`
- Emits `TimelockExecuted`

### Cancelling a Proposal

```solidity
function cancelTimelock(bytes32 proposalId) external;
```

Only the proposer can cancel. Marks the proposal as `cancelled`. Staked VOID is not returned (stays locked while they remain a proposer).

### Events

```solidity
event TimelockProposed(
    bytes32 indexed proposalId,
    address proposer,
    uint256 eta,
    uint256 proposerVotes
);

event TimelockExecuted(bytes32 indexed proposalId);
event TimelockCancelled(bytes32 indexed proposalId);
```

### Querying Proposals

```solidity
function getTimelockProposal(bytes32 proposalId) external view returns (
    bytes32 dataHash,
    uint256 eta,
    uint256 proposerVotes,
    address proposer,
    bool executed,
    bool cancelled
);
```

### Why Time-Lock?

1. **No surprise changes** — Everyone has 7 days to review and react.
2. **Skin in the game** — Proposers must stake VOID. If they propose bad changes, they can be outvoted by other proposers (in future iterations).
3. **Sybil-resistant** — Quorum grows with the network. At 1M VOID minted, you need 10K VOID to propose. At 100M VOID minted, you need 1M VOID.
4. **Exit hatch** — A malicious proposer can be outvoted or out-staked by honest actors. The timelock gives time for coordination.
5. **No admin keys** — Governance is the only way to change parameters, and it's fully on-chain with public proposals.

### Example: Proposing a New Task

```javascript
// 1. Encode the new task data
const taskData = ethers.utils.defaultAbiCoder.encode(
    ["string", "string", "string"],
    ["Pulsar Detection", "Fermi-LAT", "ConvNeXT"]
);
const dataHash = ethers.utils.keccak256(taskData);

// 2. Stake as proposer
await pool.stakeAsProposer(ethers.utils.parseEther("10000"));

// 3. Propose
const tx = await pool.proposeTimelock(dataHash);
const receipt = await tx.wait();
const proposalId = receipt.events[0].args.proposalId;

// 4. Wait 7 days...
// (Other proposers can review, signal, etc.)

// 5. Execute
await pool.executeTimelock(proposalId);
```

---

## Combined Security Model

All four mechanisms work together to create a self-enforcing, autonomous protocol:

```
Halving        → Predictable supply, no inflation surprises
Elastic Mint   → Self-balancing reward issuance
Challenge/Slash → Honest miners enforced by other miners
Time-Lock      → No surprise parameter changes
```

**No multisig. No admin key. No owner. No upgrade path.**

The contracts are immutable from day one. The only way to change the protocol is via the time-locked governance, which requires 1% proposer quorum + 7-day delay. This is the most decentralized structure possible without a DAO token vote.

---

## Comparison: Voidmap vs Bitcoin

| Feature | Bitcoin | Voidmap |
|---------|---------|---------|
| Block reward | 50 BTC → halve every 210K blocks | 50 VOID → halve every 210K submissions |
| Issuance cap | 21M BTC | 1B VOID (fixed) |
| Halving interval | 210,000 blocks (~4 years) | 210,000 submissions (varies) |
| Reward floor | 0 BTC (after ~64 halvings) | 0.1 VOID (after ~9 halvings) |
| Elastic supply | No | Yes (0.8x–1.2x) |
| Slashing | No | Yes (20% of submission reward) |
| Governance | Soft fork / hard fork | Time-locked (7 days, 1% quorum) |
| Work type | Hash puzzle | Useful ML inference |
| Energy | Wasted | Useful (real scientific data) |
| Ownerless | Yes (from genesis) | Yes (from deploy) |

---

## Testing

All four mechanisms are covered by Rust unit tests. Run them with:

```bash
cd voidmap-chain
cargo test
```

Test coverage:
- **Halving**: Epoch transitions, reward halving, floor enforcement
- **Elastic Mint**: Quality ring buffer, dead zone, dampener, boost, cap
- **Challenge/Slash**: File, resolve, self-challenge prevention, double-challenge prevention, expired window, slashed stats tracking
- **Difficulty Validation**: Blocks verified against adjustment algorithm

---

## See Also

- [Mining Guide](mining.md) — How to mine and run a node
- [Data Sources](data-sources.md) — Where the astronomical data comes from
