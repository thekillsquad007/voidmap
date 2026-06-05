# Smart Contracts

## Overview

Voidmap uses three Solidity contracts on Base L2:

1. **VoidmapToken** — Ownerless ERC-20 token with miner rewards
2. **MiningPool** — Autonomous work submissions, halving, elastic mint, challenge/slash, time-locked governance
3. **ResultRegistry** — Permanent, queryable record of all mining results (for scientific citation)

**All three contracts are immutable from day one.** No `Ownable`, no upgrade path, no multisig.

---

## ResultRegistry.sol

### Properties

| Property | Value |
|----------|-------|
| Owner | Set once at deploy, then renounceable |
| Recorders | Allowlist (MiningPool + future contracts) |
| Storage | Append-only `Result[]` array |
| Purpose | Permanent, queryable record of all mining results |

### Constructor

```solidity
constructor()  // Sets deployer as owner
```

### Key Functions

#### setRecorder

```solidity
function setRecorder(address recorder, bool allowed) external onlyOwner
```

Adds or removes a recorder. MiningPool is added at deploy time.

#### recordResult

```solidity
function recordResult(
    address miner,
    uint256 taskId,
    bytes32 dataHash,
    bytes32 resultHash,
    bytes32 modelHash,
    uint256 quality,
    uint256 samples,
    uint256 durationMs,
    string calldata ipfsCID,
    string calldata metadataURI
) external
```

Records a result. **Only callable by authorised recorders.** Reverts with:
- `NotRecorder()` — caller is not authorised
- `InvalidQuality()` — quality > 100
- `EmptyIPFS()` — empty CID string
- `AlreadyExists()` — IPFS CID already used

#### renounceOwnership

```solidity
function renounceOwnership() external
```

One-time only. After this, the registry is fully autonomous.

#### Query Functions

```solidity
function getResult(uint256 resultId) external view returns (Result memory);
function getLatestResults(uint256 n) external view returns (Result[] memory);
function getMinerResults(address miner, uint256 offset, uint256 limit) external view returns (Result[] memory);
function getTaskResults(uint256 taskId, uint256 offset, uint256 limit) external view returns (Result[] memory);
function findByDataHash(bytes32 dataHash) external view returns (uint256);
function findByResultHash(bytes32 resultHash) external view returns (uint256);
function getNetworkStats() external view returns (uint256, uint256, uint256, uint256);
```

### Result Struct

```solidity
struct Result {
    uint256 indexedAt;       // Block number
    uint256 timestamp;       // Unix timestamp
    address miner;
    uint256 taskId;
    bytes32 dataHash;
    bytes32 resultHash;
    bytes32 modelHash;
    uint256 quality;         // 0-100
    uint256 samples;
    uint256 durationMs;
    string ipfsCID;
    string metadataURI;      // Optional (e.g. arXiv DOI)
}
```

### Events

```solidity
event ResultRecorded(uint256 indexed resultId, address indexed miner, uint256 indexed taskId, bytes32 dataHash, bytes32 resultHash, string ipfsCID, uint256 quality);
event RecorderUpdated(address recorder, bool allowed);
event OwnershipRenounced();
```

### Gas Costs

| Operation | Gas | Cost on Base (19 Gwei) |
|-----------|-----|------------------------|
| `recordResult` | ~150K | ~$0.00003 |
| View functions | 0 | free |

See [result-registry.md](result-registry.md) for full documentation.

---

## VoidmapToken.sol

### Properties

| Property | Value |
|----------|-------|
| Standard | ERC-20 |
| Name | Voidmap |
| Symbol | VOID |
| Decimals | 18 |
| Total Supply | 1,000,000,000 VOID (fixed) |
| Owner | None (ownerless from deploy) |
| Minter | MiningPool (locked after one-time `migrateMinter()`) |

### Allocation (at deploy)

| Recipient | Amount | % | Vesting |
|-----------|--------|---|---------|
| GPU Miners | 900,000,000 | 90% | Halving schedule |
| Developer Fund | 50,000,000 | 5% | 4 years |
| Treasury/DAO | 50,000,000 | 5% | None |

### Constructor

```solidity
constructor(address _dev, address _dao)
```

- `_dev`: Developer fund address (receives 5% with 4-year vesting)
- `_dao`: Treasury address (receives 5%)

**Note**: The token does NOT take a minter in the constructor. This is because the deploy order is circular (pool needs token, token needs pool address). Instead, after deploying both contracts, call `migrateMinter(poolAddress)` to lock the minter.

### Key Functions

#### migrateMinter

```solidity
function migrateMinter(address newMinter) external
```

**One-time only.** Sets the minter address. After this is called, the minter is locked forever. Must be called by the deploy EOA in the same transaction sequence as the deploy.

```solidity
// Deploy order:
// 1. Deploy MiningPool (with placeholder token)
// 2. Deploy VoidmapToken (with dev + dao)
// 3. Call migrateMinter(poolAddress) — locks minter
```

#### mintMinerReward

```solidity
function mintMinerReward(
    address miner,
    uint256 amount,
    uint256 taskId,
    uint256 quality
) external
```

Mints VOID tokens as mining reward. **Only callable by the locked minter (MiningPool).** Reverts with `NotMinter()` if called by anyone else.

Reverts with `MinerCapReached()` if the total miner-minted would exceed 900M VOID.

#### burnFromMiner

```solidity
function burnFromMiner(address from, uint256 amount) external
```

Burns VOID tokens from a holder. **Only callable by the minter (MiningPool).** Used for:
- Challenge bonds (1 VOID burned when filing a challenge)
- Slash burns (50% of slashed amount burned)

Emits `Burned(from, amount)`.

#### devClaim

```solidity
function devClaim(address to) external
```

Claims vested dev tokens to a recipient address. Linear 4-year vesting, no cliff. Only callable by the dev fund address, only after vesting ends.

### Events

```solidity
event MinerReward(address indexed miner, uint256 amount, uint256 taskId, uint256 quality);
event DevClaimed(uint256 amount);
event Burned(address indexed from, uint256 amount);
```

### Error Types

```solidity
error NotMinter();           // Caller is not the locked minter
error NotDev();              // Caller is not the dev fund
error VestingActive();       // Vesting period not over
error InvalidAddress();      // Zero address
error MinerCapReached();     // 900M VOID miner cap exceeded
```

---

## MiningPool.sol

### Properties

| Property | Value |
|----------|-------|
| Owner | None (no `Ownable`) |
| Token | VoidmapToken (immutable) |
| Min Quality | 50 |
| Submission Cooldown | 12 seconds |
| Min Compute Duration | 2 seconds (anti-ASIC) |

### Quality Multipliers

| Quality | Tier | Multiplier |
|---------|------|------------|
| 50 – 69 | Accepted | 1.0x |
| 70 – 89 | Good | 1.2x |
| 90 – 100 | Excellent | 1.5x |

### Halving Constants

| Constant | Value |
|----------|-------|
| `HALVING_INTERVAL` | 210,000 submissions |
| `INITIAL_BLOCK_REWARD` | 50 VOID |
| `MIN_BLOCK_REWARD` | 0.1 VOID |

### Elastic Mint Constants

| Constant | Value |
|----------|-------|
| `ELASTICITY_WINDOW` | 10 (submissions) |
| `TARGET_QUALITY` | 75 |
| `QUALITY_EPSILON` | 5 (dead zone) |
| `MIN_ELASTIC_MULTIPLIER` | 0.8x |
| `MAX_ELASTIC_MULTIPLIER` | 1.2x |

### Challenge/Slash Constants

| Constant | Value |
|----------|-------|
| `CHALLENGE_WINDOW` | 6 hours |
| `CHALLENGE_BOND` | 1 VOID |
| `CHALLENGE_RESOLUTION_DELAY` | 1 hour |
| `SLASH_BPS` | 2000 (20% of reward) |
| `CHALLENGER_REWARD_BPS` | 5000 (50% of slash) |
| `BURN_BPS` | 5000 (50% of slash burned) |

### Time-Lock Constants

| Constant | Value |
|----------|-------|
| `TIMELOCK_DELAY` | 7 days |
| `PROPOSER_QUORUM_BPS` | 100 (1% of total miner-minted) |

### Constructor

```solidity
constructor(address _token)
```

- `_token`: VoidmapToken contract address

### Reward Formula

```
reward = blockReward × quality × qualityMultiplier × elasticMultiplier
        ───────────────────────────────────────────────────────────
                              10 × 100
```

### Task Management (Proposer-Only)

#### createTask

```solidity
function createTask(
    string name,
    string dataSource,
    string modelSpec
) external returns (uint256)
```

Creates a new mining task. **Requires proposer quorum** (1% of total miner-minted VOID staked).

#### deactivateTask

```solidity
function deactivateTask(uint256 taskId) external
```

Deactivates a task. Miners can no longer submit work for it. **Requires proposer quorum.**

### Pool Management

#### createPool

```solidity
function createPool(string name, address feeRecipient) external returns (uint256)
```

Creates a mining pool. Anyone can create a pool. Returns pool ID.

#### addPoolMember

```solidity
function addPoolMember(uint256 poolId, address miner) external
```

Adds a miner to a pool. Only the pool operator can call.

#### removePoolMember

```solidity
function removePoolMember(uint256 poolId, address miner) external
```

Removes a miner from a pool. Only the pool operator can call.

#### withdrawPoolFees

```solidity
function withdrawPoolFees(uint256 poolId) external
```

Withdraws accumulated 2% pool fees to the fee recipient. Only the pool operator can call.

### Work Submission

#### submitWork (Individual)

```solidity
function submitWork(
    uint256 taskId,
    bytes32 inputHash,
    bytes32 outputHash,
    bytes32 modelHash,
    string ipfsCID,
    uint256 quality,
    uint256 samples,
    uint256 durationMs
) external returns (uint256)
```

Submits mining work directly. Reverts on:
- Invalid task
- Inactive task
- Quality < 50 or > 100
- Samples = 0
- Duration < 2s (anti-ASIC)
- Empty IPFS CID
- Cooldown not elapsed

#### submitPoolWork (Pool)

```solidity
function submitPoolWork(
    uint256 poolId,
    uint256 taskId,
    address miner,
    bytes32 inputHash,
    bytes32 outputHash,
    bytes32 modelHash,
    string ipfsCID,
    uint256 quality,
    uint256 samples,
    uint256 durationMs
) external returns (uint256)
```

Submits work on behalf of a pool member. Deducts 2% pool fee.

### Halving Functions

#### getHalvingEpoch

```solidity
function getHalvingEpoch() external view returns (uint256)
```

Returns the current halving epoch (submissionCount / 210,000).

#### getHalvingProgress

```solidity
function getHalvingProgress() external view returns (
    uint256 epoch,
    uint256 submissionsInEpoch,
    uint256 nextHalvingAt
)
```

Returns halving progress: current epoch, submissions in current epoch, and the next halving submission number.

#### getCurrentBlockReward

```solidity
function getCurrentBlockReward() external view returns (uint256)
```

Returns the current halving-epoch block reward in wei (50e18 → 25e18 → 12.5e18 → ... → 1e17).

### Elastic Mint Functions

#### getAvgNetworkQuality

```solidity
function getAvgNetworkQuality() external view returns (uint256)
```

Returns the rolling 10-submission average quality. Used to compute the elastic multiplier.

#### getCurrentElasticMultiplier

```solidity
function getCurrentElasticMultiplier() external returns (uint256)
```

Returns the current elastic multiplier in basis points (80–120 = 0.8x–1.2x).

### Challenge/Slash Functions

#### fileChallenge

```solidity
function fileChallenge(uint256 submissionId) external
```

File a challenge against a submission. **Locks 1 VOID bond** (burned on file). Reverts if:
- Submission doesn't exist
- Already challenged
- Already resolved
- Challenge window (6h) expired
- Caller is the submitter

#### resolveChallenge

```solidity
function resolveChallenge(uint256 challengeId) external
```

Resolve a challenge after the 1-hour resolution delay. If submission quality < 50, challenger wins (gets 10% of submitter's reward, 10% burned). If quality ≥ 50, challenger loses (bond forfeited to burn).

### Time-Lock Functions

#### stakeAsProposer

```solidity
function stakeAsProposer(uint256 amount) external
```

Stake VOID to become a proposer. Required for creating/deactivating tasks.

#### unstakeProposer

```solidity
function unstakeProposer(uint256 amount) external
```

Unstake VOID and remove proposer status. Returns the unstaked VOID.

#### proposeTimelock

```solidity
function proposeTimelock(bytes32 dataHash) external returns (bytes32)
```

Propose a time-locked action. `dataHash` is the keccak256 of the action's encoded data. Returns the proposal ID.

#### executeTimelock

```solidity
function executeTimelock(bytes32 proposalId) external
```

Execute a proposal after the 7-day delay. Anyone can call (not just the proposer).

#### cancelTimelock

```solidity
function cancelTimelock(bytes32 proposalId) external
```

Cancel a pending proposal. Only the proposer can call.

#### getTimelockProposal

```solidity
function getTimelockProposal(bytes32 proposalId) external view returns (
    bytes32 dataHash,
    uint256 eta,
    uint256 proposerVotes,
    address proposer,
    bool executed,
    bool cancelled
)
```

Get proposal details.

### Query Functions

#### getSubmission

```solidity
function getSubmission(uint256 id) external view returns (Submission memory)
```

Returns submission details by ID.

#### getMinerStats

```solidity
function getMinerStats(address miner) external view returns (
    uint256 subs,
    uint256 avgQuality,
    uint256 minerTotalSamples,
    uint256 minerTotalEarned,
    uint256 minerSlashed
)
```

Returns statistics for a specific miner.

#### getPoolStats

```solidity
function getPoolStats(uint256 poolId) external view returns (
    string name,
    address operator,
    uint256 accumulatedFees,
    uint256 poolTotalSubmissions,
    uint256 memberCount,
    bool active
)
```

Returns pool statistics.

---

## Events

```solidity
// Work submission
event WorkSubmitted(
    uint256 indexed submissionId,
    address indexed miner,
    uint256 taskId,
    uint256 quality,
    uint256 samples,
    string ipfsCID,
    uint256 poolId,
    uint256 reward
);

event RewardPaid(address indexed miner, uint256 amount, uint256 qualityScore);

// Pool events
event PoolCreated(uint256 indexed poolId, address indexed operator, string name);
event PoolMemberAdded(uint256 indexed poolId, address indexed miner);
event PoolMemberRemoved(uint256 indexed poolId, address indexed miner);

// Task events
event TaskCreated(uint256 indexed taskId, string name, string dataSource);
event TaskDeactivated(uint256 indexed taskId);

// Challenge events
event ChallengeFiled(uint256 indexed challengeId, uint256 indexed submissionId, address challenger, uint256 bond);
event ChallengeResolved(uint256 indexed challengeId, uint256 indexed submissionId, bool challengerWon, uint256 slashAmount, uint256 burned);
event Slashed(address indexed miner, uint256 amount, uint256 burned);

// Halving + elastic events
event Halving(uint256 indexed epoch, uint256 newReward);
event ElasticUpdate(uint256 avgQuality, uint256 multiplier, uint256 effectiveReward);

// Time-lock events
event TimelockProposed(bytes32 indexed proposalId, address proposer, uint256 eta, uint256 proposerVotes);
event TimelockExecuted(bytes32 indexed proposalId);
event TimelockCancelled(bytes32 indexed proposalId);
```

---

## Deployment

### 2-Step Deploy

The contracts are deployed in 4 transactions:

1. **MiningPool** — Deployed with placeholder token (`address(0xdead)` or any non-zero).
2. **VoidmapToken** — Deployed with dev + dao addresses.
3. **`migrateMinter(poolAddress)`** — Locks the minter to MiningPool.
4. **Bootstrap** — Deployer stakes 1 VOID as initial proposer, creates 3 default tasks.

### Post-Deployment State

After deployment:
- `token.minter() == poolAddress` (locked)
- `token.isMinterLocked() == true`
- `pool.token() == tokenAddress` (immutable)
- Total supply = 100M VOID (dev + dao minted at deploy)
- 3 tasks created (Exoplanet, Galaxy, Anomaly)
- Deployer is the only proposer (1 VOID staked)

Total gas: ~3.5M gas (~0.00007 ETH at 19 Gwei on Base).

### Verify on BaseScan

```bash
# Verify VoidmapToken
forge verify-contract <TOKEN_ADDRESS> VoidmapToken.sol:VoidmapToken \
  --verifier blockscout --verifier-url https://api.basescan.org/api

# Verify MiningPool
forge verify-contract <POOL_ADDRESS> MiningPool.sol:MiningPool \
  --verifier blockscout --verifier-url https://api.basescan.org/api
```

---

## Security Model

### Ownerless from Day One

Both contracts have **no `Ownable` inheritance**. The token's minter is set via a one-time `migrateMinter()` call and locked forever. After this:

- No one can mint outside the MiningPool
- No one can change reward rates
- No one can add new minters
- No one can pause the contract
- The contracts are immutable

### Quality Threshold

Work with quality < 50 is rejected. This prevents:
- Low-effort spam
- Random noise submissions
- Hash grinding

### IPFS Verification

All results include an IPFS CID. Anyone can verify:
- Input data matches the hash
- Output predictions match the hash
- Model weights are correct

### Anti-ASIC Timing

`MIN_COMPUTE_DURATION = 2 seconds` enforced on-chain. Sub-2s results rejected with `"Compute too fast (ASIC?)"`.

### Challenge/Slash

Any miner can challenge a submission within 6 hours. If the submission is provably below quality floor, the submitter loses 20% of their reward. This creates a Schelling point for honest behavior.

### Time-Locked Governance

Param changes require 7-day delay + 1% proposer quorum. No surprise changes, no admin keys, no emergency switch.

---

## Contract Addresses

After deployment, save your addresses here:

| Contract | Address | Chain |
|----------|---------|-------|
| VoidmapToken | `0x8AF20228A724d7420434791EAEA5F7D037865d35` | Base Sepolia (testnet) |
| MiningPool | `0x3768e25aFc129D4455e267819801f2b2914fA4A2` | Base Sepolia (testnet) |
| ResultRegistry | TBD | Base Sepolia (testnet) |
| VoidmapToken | TBD | Base (mainnet) |
| MiningPool | TBD | Base (mainnet) |
| ResultRegistry | TBD | Base (mainnet) |

View on BaseScan:
- Testnet: https://sepolia.basescan.org
- Mainnet: https://basescan.org

---

## Test Suite

```bash
cd contracts
forge test -vv
```

**48 tests, all passing** — covers:
- Token: initial supply, dev share, miner cap, vesting, burn, ownerless
- Pool: task creation (proposer-only), submission, halving, elastic mint, challenge/slash, time-lock, pool ops

See `Voidmap.t.sol` for the full test suite.
