// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title ResultRegistry
/// @notice Permanent, queryable record of all mining results for scientific citation.
/// @dev Each accepted submission gets a record with miner, timestamp, hashes, and IPFS CID.
///      Researchers can query by miner, by task, or by data hash. The registry is
///      append-only — entries cannot be modified or deleted.
contract ResultRegistry {

    // ─── Structs ─────────────────────────────────────────

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
        string metadataURI;      // Optional pointer to extended metadata (e.g. arXiv DOI)
    }

    // ─── Storage ─────────────────────────────────────────

    Result[] public results;
    uint256 public resultCount;

    // Index: miner => result IDs
    mapping(address => uint256[]) public minerResults;

    // Index: task => result IDs
    mapping(uint256 => uint256[]) public taskResults;

    // Index: dataHash => result ID (first match)
    mapping(bytes32 => uint256) public dataHashToResult;

    // Index: resultHash => result ID (first match)
    mapping(bytes32 => uint256) public resultHashToResult;

    // IPFS CID uniqueness check
    mapping(string => bool) public ipfsCIDExists;

    // Per-miner stats
    mapping(address => uint256) public minerSubmissionCount;
    mapping(address => uint256) public minerAverageQuality;
    mapping(address => uint256) public minerTotalSamples;

    // Per-task stats
    mapping(uint256 => uint256) public taskSubmissionCount;
    mapping(uint256 => uint256) public taskAverageQuality;

    // Per-data-source stats
    mapping(bytes32 => uint256) public dataSourceSubmissionCount;

    // Authorised recorders (MiningPool + future contracts)
    mapping(address => bool) public isRecorder;

    address public owner;  // Set once at deploy, then transferred to address(0)

    // ─── Events ──────────────────────────────────────────

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

    // ─── Errors ──────────────────────────────────────────

    error NotRecorder();
    error NotOwner();
    error AlreadyExists();
    error InvalidQuality();
    error EmptyIPFS();
    error NoSuchResult();

    // ─── Modifiers ───────────────────────────────────────

    modifier onlyRecorder() {
        if (!isRecorder[msg.sender]) revert NotRecorder();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ─── Constructor ─────────────────────────────────────

    constructor() {
        owner = msg.sender;
        // Owner is NOT a recorder by default; explicit allowlist only.
    }

    // ─── Owner Setup (one-time) ─────────────────────────

    function setRecorder(address recorder, bool allowed) external onlyOwner {
        isRecorder[recorder] = allowed;
        emit RecorderUpdated(recorder, allowed);
    }

    /// @notice Renounce ownership. After this, no admin actions possible.
    function renounceOwnership() external onlyOwner {
        owner = address(0);
        emit OwnershipRenounced();
    }

    // ─── Recording ──────────────────────────────────────

    /// @notice Record a new mining result. Only callable by authorised recorders (e.g. MiningPool).
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
    ) external onlyRecorder {
        if (quality > 100) revert InvalidQuality();
        if (bytes(ipfsCID).length == 0) revert EmptyIPFS();
        if (ipfsCIDExists[ipfsCID]) revert AlreadyExists();

        uint256 resultId = results.length;
        results.push(Result({
            indexedAt: block.number,
            timestamp: block.timestamp,
            miner: miner,
            taskId: taskId,
            dataHash: dataHash,
            resultHash: resultHash,
            modelHash: modelHash,
            quality: quality,
            samples: samples,
            durationMs: durationMs,
            ipfsCID: ipfsCID,
            metadataURI: metadataURI
        }));
        resultCount = resultId + 1;

        // Update indices
        minerResults[miner].push(resultId);
        taskResults[taskId].push(resultId);

        // First-write-wins for hash lookups (cheap, no overwrites)
        if (dataHashToResult[dataHash] == 0 && resultId > 0) {
            dataHashToResult[dataHash] = resultId;
        } else if (resultId == 0) {
            dataHashToResult[dataHash] = 0;
        }
        if (resultHashToResult[resultHash] == 0 && resultId > 0) {
            resultHashToResult[resultHash] = resultId;
        } else if (resultId == 0) {
            resultHashToResult[resultHash] = 0;
        }

        ipfsCIDExists[ipfsCID] = true;

        // Update per-miner stats (running average)
        uint256 prevCount = minerSubmissionCount[miner];
        uint256 prevTotal = minerAverageQuality[miner] * prevCount;
        minerAverageQuality[miner] = (prevTotal + quality) / (prevCount + 1);
        minerSubmissionCount[miner] = prevCount + 1;
        minerTotalSamples[miner] += samples;

        // Update per-task stats
        uint256 prevTaskCount = taskSubmissionCount[taskId];
        uint256 prevTaskTotal = taskAverageQuality[taskId] * prevTaskCount;
        taskAverageQuality[taskId] = (prevTaskTotal + quality) / (prevTaskCount + 1);
        taskSubmissionCount[taskId] = prevTaskCount + 1;

        // Per-data-source stats
        dataSourceSubmissionCount[dataHash] += 1;

        emit ResultRecorded(resultId, miner, taskId, dataHash, resultHash, ipfsCID, quality);
    }

    // ─── Reading ────────────────────────────────────────

    /// @notice Get a result by ID.
    function getResult(uint256 resultId) external view returns (Result memory) {
        if (resultId >= results.length) revert NoSuchResult();
        return results[resultId];
    }

    /// @notice Get the latest N results.
    function getLatestResults(uint256 n) external view returns (Result[] memory) {
        uint256 count = n > results.length ? results.length : n;
        Result[] memory out = new Result[](count);
        for (uint256 i = 0; i < count; i++) {
            out[i] = results[results.length - 1 - i];
        }
        return out;
    }

    /// @notice Get all results by a specific miner (paginated).
    function getMinerResults(address miner, uint256 offset, uint256 limit)
        external view returns (Result[] memory)
    {
        uint256[] storage ids = minerResults[miner];
        uint256 count = limit;
        if (offset + limit > ids.length) {
            count = ids.length > offset ? ids.length - offset : 0;
        }
        Result[] memory out = new Result[](count);
        for (uint256 i = 0; i < count; i++) {
            out[i] = results[ids[offset + i]];
        }
        return out;
    }

    /// @notice Get all results for a specific task (paginated).
    function getTaskResults(uint256 taskId, uint256 offset, uint256 limit)
        external view returns (Result[] memory)
    {
        uint256[] storage ids = taskResults[taskId];
        uint256 count = limit;
        if (offset + limit > ids.length) {
            count = ids.length > offset ? ids.length - offset : 0;
        }
        Result[] memory out = new Result[](count);
        for (uint256 i = 0; i < count; i++) {
            out[i] = results[ids[offset + i]];
        }
        return out;
    }

    /// @notice Get the miner count for a given miner.
    function getMinerResultCount(address miner) external view returns (uint256) {
        return minerResults[miner].length;
    }

    /// @notice Get the result count for a given task.
    function getTaskResultCount(uint256 taskId) external view returns (uint256) {
        return taskResults[taskId].length;
    }

    /// @notice Look up a result by data hash. Returns 0 if not found.
    function findByDataHash(bytes32 dataHash) external view returns (uint256) {
        return dataHashToResult[dataHash];
    }

    /// @notice Look up a result by result hash.
    function findByResultHash(bytes32 resultHash) external view returns (uint256) {
        return resultHashToResult[resultHash];
    }

    /// @notice Get network-wide statistics.
    function getNetworkStats() external view returns (
        uint256 totalResults,
        uint256 totalSamples,
        uint256 networkAverageQuality,
        uint256 distinctMiners
    ) {
        // Note: distinctMiners requires an index we don't track here.
        // Approximate as totalResults / averageResultsPerMiner.
        totalResults = resultCount;
        if (resultCount == 0) {
            return (0, 0, 0, 0);
        }

        uint256 qualitySum;
        uint256 samplesSum;
        for (uint256 i = 0; i < resultCount; i++) {
            qualitySum += results[i].quality;
            samplesSum += results[i].samples;
        }
        networkAverageQuality = qualitySum / resultCount;
        totalSamples = samplesSum;
        distinctMiners = 0;  // Not tracked separately
    }
}
