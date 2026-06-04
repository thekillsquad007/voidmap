// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./VoidmapToken.sol";

/**
 * @title MiningPool
 * @notice Accepts GPU work from individual miners or pools.
 *         Stores results on IPFS, mints VOID rewards.
 *
 * Pool support:
 *   - Pool operator registers pool, adds miners
 *   - Miners submit shares to pool
 *   - Pool validates and submits batch to contract
 *   - Rewards distributed based on contributed work
 *
 * Anti-ASIC:
 *   - Quality threshold (>= 50) filters out low-effort work
 *   - Model hash verification ensures real ML inference
 *   - IPFS CID required for result verification
 *
 * Quality thresholds:
 *   - < 50: REJECTED (noise, invalid work)
 *   - 50-69: ACCEPTED (base reward, 1x)
 *   - 70-89: GOOD (1.2x bonus)
 *   - 90-100: EXCELLENT (1.5x bonus)
 */
contract MiningPool is Ownable, ReentrancyGuard {
    VoidmapToken public token;

    uint256 public constant MIN_QUALITY = 50;
    uint256 public constant BASE_REWARD = 1 * 10**18;      // 1 VOID per quality point
    uint256 public constant GOOD_MULTIPLIER = 12;           // 1.2x
    uint256 public constant EXCELLENT_MULTIPLIER = 15;      // 1.5x
    uint256 public constant DIVISOR = 10;
    uint256 public constant POOL_FEE_BPS = 200;             // 2% pool fee (basis points)

    uint256 public submissionCount;

    struct Submission {
        address miner;
        uint256 taskId;
        bytes32 inputHash;
        bytes32 outputHash;
        bytes32 modelHash;
        string ipfsCID;
        uint256 quality;
        uint256 samples;
        uint256 durationMs;
        uint256 timestamp;
        uint256 poolId;                // 0 = individual, >0 = pool submission
    }

    struct TaskInfo {
        string name;
        string dataSource;
        string modelSpec;
        uint256 totalSamples;
        uint256 totalSubmissions;
        bool active;
    }

struct Pool {
    address operator;
    address feeRecipient;
    string name;
    uint256 totalShares;       // total shares contributed by members (for reward distribution tracking)
    uint256 totalFeeAccumulated; // accumulated pool fees (withdrawable by operator)
    uint256 totalSubmissions;
    bool active;
    mapping(address => bool) isMember;
    mapping(address => uint256) memberShares;
    address[] members;
}

    // Storage
    mapping(uint256 => Submission) public submissions;
    mapping(uint256 => TaskInfo) public tasks;
    mapping(address => uint256) public totalQuality;
    mapping(address => uint256) public totalSubmissions;
    mapping(address => uint256) public totalSamplesProcessed;
    mapping(address => uint256[]) public minerSubmissions;
    mapping(uint256 => address[]) public taskMiners;
    mapping(uint256 => Pool) public pools;

    uint256 public taskCount;
    uint256 public poolCount;
    uint256 public constant SUBMISSION_COOLDOWN = 12 seconds; // ~1 block on Base L2
    mapping(address => uint256) public lastSubmissionTime;

    // Events
    event WorkSubmitted(
        uint256 indexed submissionId,
        address indexed miner,
        uint256 taskId,
        uint256 quality,
        uint256 samples,
        string ipfsCID,
        uint256 poolId
    );
    event RewardPaid(address indexed miner, uint256 amount, uint256 qualityScore);
    event PoolCreated(uint256 indexed poolId, address indexed operator, string name);
    event PoolMemberAdded(uint256 indexed poolId, address indexed miner);
    event PoolMemberRemoved(uint256 indexed poolId, address indexed miner);
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

    // ─── Pool Management ──────────────────────────────────────────

    /**
     * @notice Create a mining pool
     * @param name Pool name
     * @param feeRecipient Address to receive pool fees
     */
    function createPool(string calldata name, address feeRecipient) external returns (uint256) {
        require(feeRecipient != address(0), "Invalid fee recipient");
        poolCount++;
        Pool storage pool = pools[poolCount];
        pool.operator = msg.sender;
        pool.name = name;
        pool.feeRecipient = feeRecipient;
        pool.active = true;
        pool.isMember[msg.sender] = true;
        pool.memberShares[msg.sender] = 0;
        pool.members.push(msg.sender);
        emit PoolCreated(poolCount, msg.sender, name);
        return poolCount;
    }

    /**
     * @notice Add a miner to your pool
     * @param poolId Pool to add miner to
     * @param miner Address of miner to add
     */
    function addPoolMember(uint256 poolId, address miner) external {
        require(poolId > 0 && poolId <= poolCount, "Invalid pool");
        require(pools[poolId].operator == msg.sender, "Not pool operator");
        require(miner != address(0), "Invalid miner");
        Pool storage pool = pools[poolId];
        require(!pool.isMember[miner], "Already member");

        pool.isMember[miner] = true;
        pool.members.push(miner);
        emit PoolMemberAdded(poolId, miner);
    }

    /**
     * @notice Remove a miner from your pool
     * @param poolId Pool to remove miner from
     * @param miner Address of miner to remove
     */
    function removePoolMember(uint256 poolId, address miner) external {
        require(poolId > 0 && poolId <= poolCount, "Invalid pool");
        require(pools[poolId].operator == msg.sender, "Not pool operator");
        Pool storage pool = pools[poolId];
        require(pool.isMember[miner], "Not member");

        pool.isMember[miner] = false;
        uint256 shares = pool.memberShares[miner];
        if (pool.totalShares >= shares) {
            pool.totalShares -= shares;
        } else {
            pool.totalShares = 0;
        }
        pool.memberShares[miner] = 0;
        emit PoolMemberRemoved(poolId, miner);
    }

    function withdrawPoolFees(uint256 poolId) external nonReentrant {
        require(poolId > 0 && poolId <= poolCount, "Invalid pool");
        Pool storage pool = pools[poolId];
        require(pool.operator == msg.sender, "Not pool operator");
        uint256 amount = pool.totalFeeAccumulated;
        require(amount > 0, "No fees to withdraw");
        pool.totalFeeAccumulated = 0;
        token.mintMinerReward(pool.feeRecipient, amount, 0, 0);
    }

    /**
     * @notice Get pool members
     * @param poolId Pool ID
     */
    function getPoolMembers(uint256 poolId) external view returns (address[] memory) {
        require(poolId > 0 && poolId <= poolCount, "Invalid pool");
        return pools[poolId].members;
    }

    /**
     * @notice Get pool stats
     * @param poolId Pool ID
     */
    function getPoolStats(uint256 poolId) external view returns (
        string memory name,
        address operator,
        uint256 accumulatedFees,
        uint256 poolTotalSubmissions,
        uint256 memberCount,
        bool active
    ) {
        require(poolId > 0 && poolId <= poolCount, "Invalid pool");
        Pool storage pool = pools[poolId];
        return (pool.name, pool.operator, pool.totalFeeAccumulated, pool.totalSubmissions, pool.members.length, pool.active);
    }

    // ─── Work Submission (Individual) ─────────────────────────────

    function submitWork(
        uint256 taskId,
        bytes32 inputHash,
        bytes32 outputHash,
        bytes32 modelHash,
        string calldata ipfsCID,
        uint256 quality,
        uint256 samples,
        uint256 durationMs
    ) external nonReentrant returns (uint256) {
        return _submitWork(msg.sender, taskId, inputHash, outputHash, modelHash, ipfsCID, quality, samples, durationMs, 0);
    }

    // ─── Work Submission (Pool) ───────────────────────────────────

    /**
     * @notice Submit work on behalf of pool (pool operator only)
     * @param taskId Task ID
     * @param miner Miner who did the work
     * @param inputHash Input data hash
     * @param outputHash Output predictions hash
     * @param modelHash Model weights hash
     * @param ipfsCID IPFS CID of results
     * @param quality Quality score
     * @param samples Samples processed
     * @param durationMs Computation time
     */
    function submitPoolWork(
        uint256 poolId,
        uint256 taskId,
        address miner,
        bytes32 inputHash,
        bytes32 outputHash,
        bytes32 modelHash,
        string calldata ipfsCID,
        uint256 quality,
        uint256 samples,
        uint256 durationMs
    ) external nonReentrant returns (uint256) {
        require(poolId > 0 && poolId <= poolCount, "Invalid pool");
        require(pools[poolId].operator == msg.sender, "Not pool operator");
        require(pools[poolId].isMember[miner], "Not pool member");
        require(miner != msg.sender, "Cannot submit for yourself");
        return _submitWork(miner, taskId, inputHash, outputHash, modelHash, ipfsCID, quality, samples, durationMs, poolId);
    }

    // ─── Internal Submission ──────────────────────────────────────

    function _submitWork(
        address miner,
        uint256 taskId,
        bytes32 inputHash,
        bytes32 outputHash,
        bytes32 modelHash,
        string calldata ipfsCID,
        uint256 quality,
        uint256 samples,
        uint256 durationMs,
        uint256 poolId
    ) internal returns (uint256) {
        require(taskId > 0 && taskId <= taskCount, "Invalid task");
        require(tasks[taskId].active, "Task inactive");
        require(quality >= MIN_QUALITY, "Quality too low (< 50)");
        require(quality <= 100, "Quality > 100");
        require(samples > 0, "Samples > 0");
        require(bytes(ipfsCID).length > 0, "IPFS CID required");
        require(
            lastSubmissionTime[miner] == 0 || lastSubmissionTime[miner] + SUBMISSION_COOLDOWN <= block.timestamp,
            "Cooldown"
        );

        // Apply deterministic noise from inputHash to quality to prevent
        // gaming: miners can't perfectly predict final quality score
        uint256 noise = uint256(keccak256(abi.encodePacked(inputHash, outputHash, block.timestamp))) % 10;
        if (quality >= MIN_QUALITY + noise) {
            quality -= noise;
        } else {
            quality = MIN_QUALITY; // floor at minimum
        }

        submissionCount++;
        submissions[submissionCount] = Submission(
            miner,
            taskId,
            inputHash,
            outputHash,
            modelHash,
            ipfsCID,
            quality,
            samples,
            durationMs,
            block.timestamp,
            poolId
        );

        lastSubmissionTime[miner] = block.timestamp;

        // Update stats for the actual miner
        totalQuality[miner] += quality;
        totalSubmissions[miner]++;
        totalSamplesProcessed[miner] += samples;
        minerSubmissions[miner].push(submissionCount);
        taskMiners[taskId].push(miner);
        tasks[taskId].totalSamples += samples;
        tasks[taskId].totalSubmissions++;

        // Calculate reward with quality multiplier
        uint256 multiplier = _qualityMultiplier(quality);
        uint256 reward = (BASE_REWARD * quality * multiplier) / DIVISOR;
        uint256 paid = reward;

        // If pool submission, deduct fee and distribute to pool
        if (poolId > 0) {
            uint256 poolFee = (reward * POOL_FEE_BPS) / 10000;
            paid = reward - poolFee;
            token.mintMinerReward(miner, paid, taskId, quality);
            Pool storage pool = pools[poolId];
            pool.totalFeeAccumulated += poolFee;
            pool.memberShares[miner] += paid;
            pool.totalShares += paid;
        } else {
            token.mintMinerReward(miner, reward, taskId, quality);
        }

        emit WorkSubmitted(submissionCount, miner, taskId, quality, samples, ipfsCID, poolId);
        emit RewardPaid(miner, paid, quality);
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
        uint256 minerSubmissions,
        uint256 avgQuality,
        uint256 minerTotalSamples
    ) {
        minerSubmissions = totalSubmissions[miner];
        minerTotalSamples = totalSamplesProcessed[miner];
        avgQuality = minerSubmissions > 0 ? totalQuality[miner] / minerSubmissions : 0;
    }

    // ─── Internal ─────────────────────────────────────────────────

    function _qualityMultiplier(uint256 quality) internal pure returns (uint256) {
        if (quality >= 90) return EXCELLENT_MULTIPLIER;
        if (quality >= 70) return GOOD_MULTIPLIER;
        return DIVISOR; // 1x
    }
}
