// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./VoidmapToken.sol";

/**
 * @title MiningPool
 * @notice Accepts GPU work submissions, stores results on IPFS, mints VOID rewards.
 *
 * Data flow:
 *   1. Miner downloads real data (TESS, SDSS, ZTF) from public archives
 *   2. Miner runs ML model on GPU, produces predictions
 *   3. Miner uploads results to IPFS (free via Pinata/NFT.Storage)
 *   4. Miner submits: inputHash + outputHash + quality + ipfsCID
 *   5. Contract stores everything on-chain, mints reward
 *   6. Anyone can access results via IPFS gateway
 *
 * Quality thresholds:
 *   - < 50: REJECTED (noise, invalid work)
 *   - 50-69: ACCEPTED (base reward, 1x)
 *   - 70-89: GOOD (1.2x bonus)
 *   - 90-100: EXCELLENT (1.5x bonus)
 */
contract MiningPool is Ownable {
    VoidmapToken public token;

    uint256 public constant MIN_QUALITY = 50;
    uint256 public constant BASE_REWARD = 1 * 10**18;      // 1 VOID per quality point
    uint256 public constant GOOD_MULTIPLIER = 12;           // 1.2x
    uint256 public constant EXCELLENT_MULTIPLIER = 15;      // 1.5x
    uint256 public constant DIVISOR = 10;

    uint256 public submissionCount;

    struct Submission {
        address miner;
        uint256 taskId;
        bytes32 inputHash;       // hash of input data batch
        bytes32 outputHash;      // hash of output predictions
        bytes32 modelHash;       // hash of model weights used
        string ipfsCID;          // IPFS CID of actual results (publicly accessible)
        uint256 quality;         // 0-100, from model metrics
        uint256 samples;         // number of samples processed
        uint256 durationMs;      // computation time in ms
        uint256 timestamp;
    }

    struct TaskInfo {
        string name;
        string dataSource;       // e.g. "MAST TESS 2-min cadence"
        string modelSpec;        // e.g. "TransitCNN v1, 1D conv"
        uint256 totalSamples;
        uint256 totalSubmissions;
        bool active;
    }

    // Storage
    mapping(uint256 => Submission) public submissions;
    mapping(uint256 => TaskInfo) public tasks;
    mapping(address => uint256) public totalQuality;
    mapping(address => uint256) public totalSubmissions;
    mapping(address => uint256) public totalSamplesProcessed;
    mapping(address => uint256[]) public minerSubmissions;  // miner -> list of submission IDs
    mapping(uint256 => address[]) public taskMiners;         // taskId -> list of miners

    uint256 public taskCount;

    // Events
    event WorkSubmitted(
        uint256 indexed submissionId,
        address indexed miner,
        uint256 taskId,
        uint256 quality,
        uint256 samples,
        string ipfsCID
    );
    event RewardPaid(address indexed miner, uint256 amount, uint256 qualityScore);
    event TaskCreated(uint256 indexed taskId, string name, string dataSource);
    event TaskDeactivated(uint256 indexed taskId);

    constructor(address _token) Ownable(msg.sender) {
        token = VoidmapToken(_token);
    }

    // ─── Task Management ──────────────────────────────────────────

    function createTask(
        string calldata name,
        string calldata dataSource,
        string calldata modelSpec
    ) external onlyOwner returns (uint256) {
        taskCount++;
        tasks[taskCount] = TaskInfo(name, dataSource, modelSpec, 0, 0, true);
        emit TaskCreated(taskCount, name, dataSource);
        return taskCount;
    }

    function deactivateTask(uint256 taskId) external onlyOwner {
        require(taskId > 0 && taskId <= taskCount, "Invalid task");
        tasks[taskId].active = false;
        emit TaskDeactivated(taskId);
    }

    // ─── Work Submission ──────────────────────────────────────────

    /**
     * @notice Submit a batch of processed work
     * @param taskId Which task this work belongs to
     * @param inputHash SHA-256 of input data (verifiable against archive)
     * @param outputHash SHA-256 of output predictions
     * @param modelHash SHA-256 of model weights (for reproducibility)
     * @param ipfsCID IPFS Content Identifier where results are stored
     * @param quality Quality score 0-100 from model metrics
     * @param samples Number of samples processed in this batch
     * @param durationMs Milliseconds spent computing
     */
    function submitWork(
        uint256 taskId,
        bytes32 inputHash,
        bytes32 outputHash,
        bytes32 modelHash,
        string calldata ipfsCID,
        uint256 quality,
        uint256 samples,
        uint256 durationMs
    ) external returns (uint256) {
        require(taskId > 0 && taskId <= taskCount, "Invalid task");
        require(tasks[taskId].active, "Task inactive");
        require(quality >= MIN_QUALITY, "Quality too low (< 50)");
        require(quality <= 100, "Quality > 100");
        require(samples > 0, "Samples > 0");
        require(bytes(ipfsCID).length > 0, "IPFS CID required");

        submissionCount++;
        submissions[submissionCount] = Submission(
            msg.sender,
            taskId,
            inputHash,
            outputHash,
            modelHash,
            ipfsCID,
            quality,
            samples,
            durationMs,
            block.timestamp
        );

        // Update stats
        totalQuality[msg.sender] += quality;
        totalSubmissions[msg.sender]++;
        totalSamplesProcessed[msg.sender] += samples;
        minerSubmissions[msg.sender].push(submissionCount);
        taskMiners[taskId].push(msg.sender);
        tasks[taskId].totalSamples += samples;
        tasks[taskId].totalSubmissions++;

        // Calculate reward with quality multiplier
        uint256 multiplier = _qualityMultiplier(quality);
        uint256 reward = (BASE_REWARD * quality * multiplier) / DIVISOR;
        token.mintMinerReward(msg.sender, reward, taskId, quality);

        emit WorkSubmitted(submissionCount, msg.sender, taskId, quality, samples, ipfsCID);
        emit RewardPaid(msg.sender, reward, quality);
        return submissionCount;
    }

    // ─── Query Functions ──────────────────────────────────────────

    function getSubmission(uint256 id) external view returns (Submission memory) {
        require(id > 0 && id <= submissionCount, "Invalid submission");
        return submissions[id];
    }

    function getMinerSubmissionCount(address miner) external view returns (uint256) {
        return minerSubmissions[miner].length;
    }

    function getMinerSubmissions(address miner) external view returns (uint256[] memory) {
        return minerSubmissions[miner];
    }

    function getTaskMinerCount(uint256 taskId) external view returns (uint256) {
        return taskMiners[taskId].length;
    }

    function getMinerStats(address miner) external view returns (
        uint256 submissions,
        uint256 avgQuality,
        uint256 totalSamples,
        uint256 earned
    ) {
        submissions = totalSubmissions[miner];
        totalSamples = totalSamplesProcessed[miner];
        avgQuality = submissions > 0 ? totalQuality[miner] / submissions : 0;
        // Note: earned is tracked via token balance, not here
    }

    // ─── Internal ─────────────────────────────────────────────────

    function _qualityMultiplier(uint256 quality) internal pure returns (uint256) {
        if (quality >= 90) return EXCELLENT_MULTIPLIER;
        if (quality >= 70) return GOOD_MULTIPLIER;
        return DIVISOR; // 1x
    }
}
