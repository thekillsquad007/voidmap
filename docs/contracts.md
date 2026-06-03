# Smart Contracts

## Overview

Voidmap uses two Solidity contracts on Base L2:

1. **VoidmapToken** — ERC-20 token with miner rewards
2. **MiningPool** — Accepts work submissions, distributes rewards

---

## VoidmapToken.sol

### Properties

| Property | Value |
|----------|-------|
| Standard | ERC-20 |
| Name | Voidmap |
| Symbol | VOID |
| Decimals | 18 |
| Total Supply | 1,000,000,000 VOID |

### Allocation

| Recipient | Amount | % |
|-----------|--------|---|
| GPU Miners | 900,000,000 | 90% |
| Developer Fund | 50,000,000 | 5% |
| Treasury | 50,000,000 | 5% |

### Constructor

```solidity
constructor(address _dev, address _dao)
```

- `_dev`: Developer fund address (receives 5% with 4-year vesting)
- `_dao`: Treasury address (receives 5%)

### Key Functions

#### mintMinerReward

```solidity
function mintMinerReward(
    address miner,
    uint256 amount,
    uint256 taskId,
    uint256 quality
) external
```

Mints VOID tokens as mining reward. Can only be called by MiningPool contract.

#### devClaim

```solidity
function devClaim(address dev) external
```

Claims vested dev tokens. Linear 4-year vesting, no cliff.

#### renounce

```solidity
function renounce() external
```

Renounces ownership. Called once after deployment to make token immutable.

---

## MiningPool.sol

### Properties

| Property | Value |
|----------|-------|
| Owner | Deployer (renounced after setup) |
| Token | VoidmapToken |
| Min Quality | 50 |
| Base Reward | 1 VOID per quality point |

### Quality Multipliers

| Quality | Multiplier | Example |
|---------|------------|---------|
| 50-69 | 1x | 50 quality → 50 VOID |
| 70-89 | 1.2x | 80 quality → 96 VOID |
| 90-100 | 1.5x | 100 quality → 150 VOID |

### Constructor

```solidity
constructor(address _token)
```

- `_token`: VoidmapToken contract address

### Task Management

#### createTask

```solidity
function createTask(
    string name,
    string dataSource,
    string modelSpec
) external onlyOwner returns (uint256)
```

Creates a new mining task (e.g., "Exoplanet Transit Detection").

#### deactivateTask

```solidity
function deactivateTask(uint256 taskId) external onlyOwner
```

Deactivates a task (miners can no longer submit work for it).

### Pool Management

#### createPool

```solidity
function createPool(
    string name,
    address feeRecipient
) external returns (uint256)
```

Creates a mining pool. Returns pool ID.

#### addPoolMember

```solidity
function addPoolMember(uint256 poolId, address miner) external
```

Adds a miner to a pool. Only pool operator can call.

#### removePoolMember

```solidity
function removePoolMember(uint256 poolId, address miner) external
```

Removes a miner from a pool.

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

Submits mining work directly from an individual miner.

#### submitPoolWork (Pool)

```solidity
function submitPoolWork(
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

Submits work on behalf of a pool member.

### Query Functions

#### getSubmission

```solidity
function getSubmission(uint256 id) external view returns (Submission memory)
```

Returns submission details by ID.

#### getMinerStats

```solidity
function getMinerStats(address miner) external view returns (
    uint256 submissions,
    uint256 avgQuality,
    uint256 totalSamples
)
```

Returns statistics for a specific miner.

#### getPoolStats

```solidity
function getPoolStats(uint256 poolId) external view returns (
    string name,
    address operator,
    uint256 totalShares,
    uint256 totalSubmissions,
    uint256 memberCount,
    bool active
)
```

Returns pool statistics.

---

## Events

```solidity
event WorkSubmitted(
    uint256 indexed submissionId,
    address indexed miner,
    uint256 taskId,
    uint256 quality,
    uint256 samples,
    string ipfsCID,
    uint256 poolId
);

event RewardPaid(
    address indexed miner,
    uint256 amount,
    uint256 qualityScore
);

event PoolCreated(
    uint256 indexed poolId,
    address indexed operator,
    string name
);

event PoolMemberAdded(
    uint256 indexed poolId,
    address indexed miner
);

event PoolMemberRemoved(
    uint256 indexed poolId,
    address indexed miner
);
```

---

## Deployment

### Prerequisites

- Foundry installed
- Base ETH for gas (~$0.50)
- Private key with ETH

### Deploy

```bash
# Set environment variables
export DEPLOYER_PK=0x...  # Private key
export DEV_ADDR=0x...      # Your wallet (dev fund)

# Deploy contracts
bash deploy.sh
```

### Post-Deployment

1. MiningPool becomes token minter
2. Ownership renounced (immutable)
3. Contract addresses displayed

### Verify on Basescan

```bash
# Verify VoidmapToken
forge verify-contract $TOKEN_ADDRESS contracts/VoidmapToken.sol \
  --chain-id 8453 \
  --etherscan-api-key $ETHERSCAN_KEY

# Verify MiningPool
forge verify-contract $POOL_ADDRESS contracts/MiningPool.sol \
  --chain-id 8453 \
  --etherscan-api-key $ETHERSCAN_KEY
```

---

## Security

### Renounced Ownership

After deployment, `renounce()` is called on both contracts. This means:
- No one can modify the token
- No one can change reward rates
- No one can add new minters
- The contracts are immutable

### Quality Threshold

Work with quality < 50 is rejected. This prevents:
- Low-effort spam
- Random noise submissions
- ASIC/FPGA hash grinding

### IPFS Verification

All results include an IPFS CID. Anyone can verify:
- Input data matches the hash
- Output predictions match the hash
- Model weights are correct

---

## Contract Addresses

After deployment, add addresses here:

| Contract | Address | Chain |
|----------|---------|-------|
| VoidmapToken | `0x...` | Base |
| MiningPool | `0x...` | Base |
