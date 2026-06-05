# Result Registry

The on-chain Result Registry is a permanent, queryable record of every accepted mining result. Researchers can cite Voidmap entries in academic papers by transaction hash, data hash, or result hash.

---

## Overview

Every accepted submission in the MiningPool triggers a `recordResult()` call to the ResultRegistry. The registry records:

- **Miner** — submitter address
- **Task ID** — which task (exoplanet, galaxy, anomaly)
- **Hashes** — `dataHash` (input), `resultHash` (output), `modelHash` (model used)
- **Quality** — 0–100 score
- **Samples** — number of data points processed
- **Duration** — compute time (ms)
- **IPFS CID** — pointer to full result payload
- **Timestamp** + **block number** — when recorded

The registry is **append-only** — entries cannot be modified or deleted.

---

## Contract

**File**: `contracts/ResultRegistry.sol`

### Properties

| Property | Value |
|----------|-------|
| Owner | Set once, then renounceable |
| Recorders | Allowlist (MiningPool + future contracts) |
| Storage | Append-only `Result[]` array |
| Indices | By miner, by task, by data hash, by result hash |
| Gas (record) | ~150K gas (≈ $0.00003 on Base) |

### Constructor

```solidity
constructor()  // Sets deployer as owner
```

No required arguments. The deployer is the owner and can set up recorders.

### Owner Functions

```solidity
function setRecorder(address recorder, bool allowed) external onlyOwner;
function renounceOwnership() external onlyOwner;
```

After `renounceOwnership()`, no further admin actions are possible. The registry is then fully autonomous — only recorders can add entries, only public view functions can be called.

### Recorder Functions

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
) external onlyRecorder;
```

Reverts on:
- `NotRecorder()` — caller is not authorised
- `InvalidQuality()` — quality > 100
- `EmptyIPFS()` — empty CID string
- `AlreadyExists()` — IPFS CID already used

### Public View Functions

```solidity
// Get a single result
function getResult(uint256 resultId) external view returns (Result memory);

// Get latest N results (newest first)
function getLatestResults(uint256 n) external view returns (Result[] memory);

// Get results by miner (paginated)
function getMinerResults(address miner, uint256 offset, uint256 limit)
    external view returns (Result[] memory);

// Get results by task (paginated)
function getTaskResults(uint256 taskId, uint256 offset, uint256 limit)
    external view returns (Result[] memory);

// Counts
function getMinerResultCount(address miner) external view returns (uint256);
function getTaskResultCount(uint256 taskId) external view returns (uint256);
function resultCount() external view returns (uint256);

// Hash lookups
function findByDataHash(bytes32 dataHash) external view returns (uint256);
function findByResultHash(bytes32 resultHash) external view returns (uint256);

// Network stats
function getNetworkStats() external view returns (
    uint256 totalResults,
    uint256 totalSamples,
    uint256 networkAverageQuality,
    uint256 distinctMiners
);
```

### Events

```solidity
event ResultRecorded(
    uint256 indexed resultId,
    address indexed miner,
    uint256 indexed taskId,
    bytes32 dataHash,
    bytes32 resultHash,
    string ipfsCID,
    uint256 quality
);

event RecorderUpdated(address recorder, bool allowed);
event OwnershipRenounced();
```

### Result Struct

```solidity
struct Result {
    uint256 indexedAt;       // Block number when recorded
    uint256 timestamp;       // Unix timestamp
    address miner;           // Submitter
    uint256 taskId;          // Mining task (1=exoplanet, 2=galaxy, 3=anomaly)
    bytes32 dataHash;        // Hash of input data
    bytes32 resultHash;      // Hash of result/output
    bytes32 modelHash;       // Hash of model used
    uint256 quality;         // Quality score (0-100)
    uint256 samples;         // Number of samples processed
    uint256 durationMs;      // Compute duration
    string ipfsCID;          // IPFS CID for full result
    string metadataURI;      // Optional pointer to extended metadata
}
```

---

## Integration with MiningPool

The `MiningPool` contract holds an immutable reference to the registry. After every accepted submission:

```solidity
// In _submitWork() of MiningPool.sol:
if (address(registry) != address(0)) {
    try registry.recordResult(
        miner, taskId, inputHash, outputHash, modelHash,
        quality, samples, durationMs, ipfsCID, ""
    ) {} catch {}
}
```

The `try/catch` ensures that a registry failure does not revert the submission. This means the registry can be upgraded (via deploying a new one) without affecting mining.

### Updating the Registry

Since the registry is immutable, you cannot change the address. But you can:

1. Deploy a new ResultRegistry
2. Update the new registry's recorder list
3. The old registry remains queryable as historical record

The `registry` field in `MiningPool` is `immutable` for gas efficiency.

---

## Usage from a Researcher

### Citing a Voidmap Result in a Paper

```
Data sourced from Voidmap network (https://voidmap.org).
Submission ID 12345, recorded 2026-06-05 in block 12,345,678.
Transaction: 0xabc...def
IPFS: QmXxx... (https://ipfs.io/ipfs/QmXxx...)
```

### Querying the Registry

**Via cast (CLI):**
```bash
# Get a specific result
cast call $REGISTRY "getResult(uint256)" 12345 --rpc-url $RPC

# Get latest 10 results
cast call $REGISTRY "getLatestResults(uint256)" 10 --rpc-url $RPC

# Get all results for a miner (paginated)
cast call $REGISTRY "getMinerResults(address,uint256,uint256)" \
  0xMINER_ADDRESS 0 50 --rpc-url $RPC

# Get all results for a task
cast call $REGISTRY "getTaskResults(uint256,uint256,uint256)" \
  1 0 100 --rpc-url $RPC

# Find by data hash
cast call $REGISTRY "findByDataHash(bytes32)" \
  0xDATA_HASH --rpc-url $RPC
```

**Via web3.py (Python):**
```python
from web3 import Web3
w3 = Web3(Web3.HTTPProvider(RPC))
registry = w3.eth.contract(address=REGISTRY_ADDR, abi=REGISTRY_ABI)

# Get result
result = registry.functions.getResult(12345).call()
print(f"Miner: {result.miner}")
print(f"Task: {result.taskId}")
print(f"Quality: {result.quality}")
print(f"IPFS: {result.ipfsCID}")
```

**Via the block explorer (future):**
Browse all results at `https://explorer.voidmap.org/registry`

---

## Statistics Dashboard

The registry provides network-wide statistics:

```python
total, samples, avgQ, miners = registry.functions.getNetworkStats().call()
print(f"Total results: {total}")
print(f"Total samples processed: {samples}")
print(f"Average quality: {avgQ}/100")
```

Per-miner stats:
```python
count = registry.functions.getMinerResultCount(MINER).call()
avgQ = registry.functions.minerAverageQuality(MINER).call()
totalSamples = registry.functions.minerTotalSamples(MINER).call()
```

Per-task stats:
```python
count = registry.functions.getTaskResultCount(1).call()  # task 1 = exoplanet
avgQ = registry.functions.taskAverageQuality(1).call()
```

---

## Storage & Gas

| Operation | Gas | Cost on Base (19 Gwei) |
|-----------|-----|------------------------|
| `recordResult` | ~150K | ~$0.00003 |
| `getResult` (view) | 0 | free |
| `getLatestResults(10)` (view) | 0 | free |
| `getMinerResults(_, 0, 100)` (view) | 0 | free |
| `getNetworkStats` (view) | 0 | free |

The registry is gas-efficient even at scale — recording is the only state-changing operation, and all reads are free.

---

## Privacy & Permanence

- All results are **public** on-chain. Don't submit sensitive data.
- Results are **permanent** — once recorded, they cannot be modified or deleted.
- IPFS CIDs point to off-chain result payloads. Pin your own CIDs for permanence.
- The registry is **append-only** — no admin can censor a result once recorded (assuming ownership is renounced).

---

## Future Extensions

Potential upgrades (require a new contract or migration):

1. **Bulk insert** — record multiple results in one transaction
2. **IPFS pin incentivization** — reward miners who pin CIDs
3. **Citation index** — track which DOIs cite which results
4. **Search by quality threshold** — get all results above quality X
5. **Time-bounded queries** — get all results in a time range
6. **Cross-chain mirroring** — mirror registry to other L2s for redundancy

---

## Test Coverage

13 forge tests for the ResultRegistry:

- `test_ownerCanSetRecorder` — recorder allowlist
- `test_nonOwnerCannotSetRecorder` — admin protection
- `test_renounceOwnership` — autonomy
- `test_recordAndGetResult` — basic record/read
- `test_emptyIPFSRejected` — validation
- `test_invalidQualityRejected` — validation
- `test_getTaskResults` — task pagination
- `test_getLatestResults` — chronological queries
- `test_registryRecordsSubmissions` — integration with MiningPool
- `test_registryGetMinerResults` — miner pagination
- `test_registryFindByHash` — hash lookups
- `test_registryRejectsNonRecorder` — access control
- `test_registryRejectsDuplicateIPFS` — uniqueness

All 62 tests pass (48 MiningPool + 6 registry integration + 8 standalone).

---

## See Also

- [Smart Contracts](contracts.md) — MiningPool + VoidmapToken
- [Mainnet Features](mainnet-features.md) — Halving, elastic mint, challenge/slash, timelock
- [Mining Guide](mining.md) — How results are generated
