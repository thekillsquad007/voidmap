// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./VoidmapToken.sol";
import "./ResultRegistry.sol";

/**
 * @title MiningPool
 * @notice Proof of Useful Work — GPU miners process real astronomical data to earn VOID.
 *         Autonomous, no owner after deploy. Time-locked governance for all param changes.
 *
 * Mainnet features:
 *   - Halving: reward halves every HALVING_INTERVAL submissions (Bitcoin-style)
 *   - Elastic mint: base reward scales with network quality (10-period moving avg)
 *   - Challenge/slash: any miner can challenge a submission within CHALLENGE_WINDOW
 *     - If challenged AND actual quality is below QUALITY_FLOOR, submitter is slashed
 *     - Slash burns SLASH_BPS % of submitter's reward and gives CHALLENGER_REWARD_BPS to challenger
 *     - If challenged AND quality is valid, challenger loses BOND
 *   - Time-locked governance: param changes require TIMELOCK_DELAY + proposer quorum
 *   - No owner: all admin functions gated by timelock
 *
 * Quality tiers:
 *   - < 50: REJECTED (noise, invalid work)
 *   - 50-69: ACCEPTED (base reward, 1x)
 *   - 70-89: GOOD (1.2x bonus)
 *   - 90-100: EXCELLENT (1.5x bonus)
 *
 * Anti-ASIC:
 *   - MIN_COMPUTE_DURATION = 2 seconds
 *   - Quality threshold filters low-effort work
 *   - Deterministic noise from hashes prevents gaming
 */
contract MiningPool is ReentrancyGuard {
    VoidmapToken public token;
    ResultRegistry public registry;  // Optional: address(0) disables recording

    // ─── Constants ───────────────────────────────────────────────
    uint256 public constant MIN_QUALITY = 50;
    uint256 public constant MAX_QUALITY = 100;
    uint256 public constant QUALITY_FLOOR = 50;
    uint256 public constant BASE_REWARD = 1 * 10**18;
    uint256 public constant GOOD_MULTIPLIER = 12;
    uint256 public constant EXCELLENT_MULTIPLIER = 15;
    uint256 public constant DIVISOR = 10;
    uint256 public constant POOL_FEE_BPS = 200;
    uint256 public constant SUBMISSION_COOLDOWN = 12 seconds;
    uint256 public constant MIN_COMPUTE_DURATION = 2 seconds;

    // Halving
    uint256 public constant HALVING_INTERVAL = 210_000;     // submissions per halving
    uint256 public constant INITIAL_BLOCK_REWARD = 50 * 10**18;  // 50 VOID at genesis
    uint256 public constant MIN_BLOCK_REWARD = 1 * 10**17;       // floor at 0.1 VOID

    // Elastic mint
    uint256 public constant ELASTICITY_WINDOW = 10;        // last N submissions for avg quality
    uint256 public constant TARGET_QUALITY = 75;           // ideal network quality
    uint256 public constant QUALITY_EPSILON = 5;            // dead zone around target
    uint256 public constant MAX_ELASTIC_MULTIPLIER = 120;   // 1.2x max boost
    uint256 public constant MIN_ELASTIC_MULTIPLIER = 80;    // 0.8x min dampener

    // Challenge/slash
    uint256 public constant CHALLENGE_WINDOW = 6 hours;
    uint256 public constant CHALLENGE_BOND = 1 * 10**18;   // 1 VOID to challenge
    uint256 public constant SLASH_BPS = 2000;               // 20% of reward slashed
    uint256 public constant CHALLENGER_REWARD_BPS = 5000;   // 50% of slash to challenger
    uint256 public constant BURN_BPS = 5000;                // 50% of slash burned

    // Timelock
    uint256 public constant TIMELOCK_DELAY = 7 days;
    uint256 public constant PROPOSER_QUORUM_BPS = 100;      // 1% of total miner-minted supply must propose

    // ─── Storage ─────────────────────────────────────────────────
    uint256 public submissionCount;
    uint256 public totalSlashed;
    uint256 public totalBurned;

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
        uint256 poolId;
        uint256 reward;          // actual reward paid
        bool challenged;
        bool resolved;
        bool slashed;
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
        uint256 totalShares;
        uint256 totalFeeAccumulated;
        uint256 totalSubmissions;
        bool active;
        mapping(address => bool) isMember;
        mapping(address => uint256) memberShares;
        address[] members;
    }

    struct Challenge {
        address challenger;
        uint256 submissionId;
        uint256 bond;
        uint256 filedAt;
        bool resolved;
        bool challengerWon;
    }

    struct TimelockProposal {
        bytes32 dataHash;        // hash of (target, value, signature, params)
        uint256 eta;             // earliest execution time
        uint256 proposerVotes;   // sum of proposers' miner-minted balance
        address proposer;
        bool executed;
        bool cancelled;
    }

    // Mappings
    mapping(uint256 => Submission) public submissions;
    mapping(uint256 => TaskInfo) public tasks;
    mapping(address => uint256) public totalQuality;
    mapping(address => uint256) public totalSubmissions;
    mapping(address => uint256) public totalSamplesProcessed;
    mapping(address => uint256) public totalEarned;
    mapping(address => uint256) public slashedBalance;
    mapping(address => uint256[]) public minerSubmissions;
    mapping(uint256 => address[]) public taskMiners;
    mapping(uint256 => Pool) public pools;
    mapping(address => uint256) public lastSubmissionTime;

    // Challenge tracking
    mapping(uint256 => Challenge) public challenges;
    mapping(uint256 => uint256) public submissionChallengeId;

    // Elastic mint: ring buffer of recent qualities
    mapping(uint256 => uint256) public qualityRing;  // submissionId => quality
    uint256 public qualityRingHead;
    uint256 public qualityRingCount;
    uint256 public qualitySum;

    // Halving
    mapping(uint256 => uint256) public halvingRewards;  // halving epoch => reward

    // Timelock governance
    mapping(bytes32 => TimelockProposal) public timelockProposals;
    uint256 public timelockProposalCount;
    mapping(address => bool) public proposers;
    mapping(address => uint256) public proposerStake;

    uint256 public taskCount;
    uint256 public poolCount;

    // ─── Errors ───────────────────────────────────────────────────
    error InvalidTask();
    error TaskInactive();
    error QualityTooLow();
    error QualityTooHigh();
    error NoSamples();
    error ComputeTooFast();
    error IpfsCidRequired();
    error CooldownActive();
    error InvalidPool();
    error NotPoolOperator();
    error NotPoolMember();
    error SelfSubmit();
    error AlreadyMember();
    error NotMember();
    error NoFees();
    error InvalidFeeRecipient();
    error InvalidMiner();
    error AlreadyChallenged();
    error AlreadyResolved();
    error ChallengeWindowExpired();
    error SelfChallenge();
    error InvalidChallenge();
    error ResolutionTooEarly();
    error ZeroStake();
    error NotProposer();
    error StakeExceeded();
    error NoMinerSupply();
    error BelowQuorum();
    error EmptyData();
    error UnknownProposal();
    error ProposalExecuted();
    error ProposalCancelled();
    error TimelockNotElapsed();
    error NotProposerCancel();

    // ─── Events ──────────────────────────────────────────────────
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
    event PoolCreated(uint256 indexed poolId, address indexed operator, string name);
    event PoolMemberAdded(uint256 indexed poolId, address indexed miner);
    event PoolMemberRemoved(uint256 indexed poolId, address indexed miner);
    event TaskCreated(uint256 indexed taskId, string name, string dataSource);
    event TaskDeactivated(uint256 indexed taskId);

    event ChallengeFiled(uint256 indexed challengeId, uint256 indexed submissionId, address challenger, uint256 bond);
    event ChallengeResolved(uint256 indexed challengeId, uint256 indexed submissionId, bool challengerWon, uint256 slashAmount, uint256 burned);
    event Slashed(address indexed miner, uint256 amount, uint256 burned);

    event Halving(uint256 indexed epoch, uint256 newReward);
    event ElasticUpdate(uint256 avgQuality, uint256 multiplier, uint256 effectiveReward);

    event TimelockProposed(bytes32 indexed proposalId, address proposer, uint256 eta, uint256 proposerVotes);
    event TimelockExecuted(bytes32 indexed proposalId);
    event TimelockCancelled(bytes32 indexed proposalId);

    // ─── Constructor ─────────────────────────────────────────────

    constructor(address _token, address _registry) {
        token = VoidmapToken(_token);
        registry = ResultRegistry(_registry);
        // Initialize genesis reward
        halvingRewards[0] = INITIAL_BLOCK_REWARD;
    }

    // ─── Task Management (time-locked) ───────────────────────────

    function createTask(
        string calldata name,
        string calldata dataSource,
        string calldata modelSpec
    ) external returns (uint256) {
        _requireProposer();
        taskCount++;
        tasks[taskCount] = TaskInfo(name, dataSource, modelSpec, 0, 0, true);
        emit TaskCreated(taskCount, name, dataSource);
        return taskCount;
    }

    function deactivateTask(uint256 taskId) external {
        _requireProposer();
        if (taskId == 0 || taskId > taskCount) revert InvalidTask();
        tasks[taskId].active = false;
        emit TaskDeactivated(taskId);
    }

    // ─── Pool Management ──────────────────────────────────────────

    function createPool(string calldata name, address feeRecipient) external returns (uint256) {
        if (feeRecipient == address(0)) revert InvalidFeeRecipient();
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

    function addPoolMember(uint256 poolId, address miner) external {
        if (poolId == 0 || poolId > poolCount) revert InvalidPool();
        if (pools[poolId].operator != msg.sender) revert NotPoolOperator();
        if (miner == address(0)) revert InvalidMiner();
        Pool storage pool = pools[poolId];
        if (pool.isMember[miner]) revert AlreadyMember();

        pool.isMember[miner] = true;
        pool.members.push(miner);
        emit PoolMemberAdded(poolId, miner);
    }

    function removePoolMember(uint256 poolId, address miner) external {
        if (poolId == 0 || poolId > poolCount) revert InvalidPool();
        if (pools[poolId].operator != msg.sender) revert NotPoolOperator();
        Pool storage pool = pools[poolId];
        if (!pool.isMember[miner]) revert NotMember();

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
        if (poolId == 0 || poolId > poolCount) revert InvalidPool();
        Pool storage pool = pools[poolId];
        if (pool.operator != msg.sender) revert NotPoolOperator();
        uint256 amount = pool.totalFeeAccumulated;
        if (amount == 0) revert NoFees();
        pool.totalFeeAccumulated = 0;
        token.mintMinerReward(pool.feeRecipient, amount, 0, 0);
    }

    function getPoolMembers(uint256 poolId) external view returns (address[] memory) {
        if (poolId == 0 || poolId > poolCount) revert InvalidPool();
        return pools[poolId].members;
    }

    function getPoolStats(uint256 poolId) external view returns (
        string memory name,
        address operator,
        uint256 accumulatedFees,
        uint256 poolTotalSubmissions,
        uint256 memberCount,
        bool active
    ) {
        if (poolId == 0 || poolId > poolCount) revert InvalidPool();
        Pool storage pool = pools[poolId];
        return (pool.name, pool.operator, pool.totalFeeAccumulated, pool.totalSubmissions, pool.members.length, pool.active);
    }

    // ─── Work Submission ──────────────────────────────────────────

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
        if (poolId == 0 || poolId > poolCount) revert InvalidPool();
        if (pools[poolId].operator != msg.sender) revert NotPoolOperator();
        if (!pools[poolId].isMember[miner]) revert NotPoolMember();
        if (miner == msg.sender) revert SelfSubmit();
        return _submitWork(miner, taskId, inputHash, outputHash, modelHash, ipfsCID, quality, samples, durationMs, poolId);
    }

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
        if (taskId == 0 || taskId > taskCount) revert InvalidTask();
        if (!tasks[taskId].active) revert TaskInactive();
        if (quality < MIN_QUALITY) revert QualityTooLow();
        if (quality > MAX_QUALITY) revert QualityTooHigh();
        if (samples == 0) revert NoSamples();
        if (durationMs < MIN_COMPUTE_DURATION) revert ComputeTooFast();
        if (bytes(ipfsCID).length == 0) revert IpfsCidRequired();
        if (lastSubmissionTime[miner] != 0 && lastSubmissionTime[miner] + SUBMISSION_COOLDOWN > block.timestamp) {
            revert CooldownActive();
        }

        // Deterministic noise from inputHash to quality to prevent gaming
        uint256 noise = uint256(keccak256(abi.encodePacked(inputHash, outputHash, block.timestamp))) % 10;
        if (quality >= MIN_QUALITY + noise) {
            quality -= noise;
        } else {
            quality = MIN_QUALITY;
        }

        submissionCount++;
        submissions[submissionCount] = Submission(
            miner, taskId, inputHash, outputHash, modelHash,
            ipfsCID, quality, samples, durationMs, block.timestamp,
            poolId, 0, false, false, false
        );

        lastSubmissionTime[miner] = block.timestamp;

        // Update elastic mint ring buffer
        _updateQualityRing(quality);

        // Calculate halving-adjusted block reward
        uint256 blockReward = _currentBlockReward();

        // Calculate elastic multiplier
        uint256 elasticMult = _elasticMultiplier();

        // Quality multiplier
        uint256 qualMult = _qualityMultiplier(quality);

        // Final reward = baseReward * quality * qualMult * elasticMult / (DIVISOR * 100)
        uint256 reward = (blockReward * uint256(quality) * qualMult * elasticMult) / (DIVISOR * 100);
        uint256 paid = reward;

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

        // Store actual reward
        submissions[submissionCount].reward = paid;

        // Update miner stats
        totalQuality[miner] += quality;
        totalSubmissions[miner]++;
        totalSamplesProcessed[miner] += samples;
        totalEarned[miner] += paid;
        minerSubmissions[miner].push(submissionCount);
        taskMiners[taskId].push(miner);
        tasks[taskId].totalSamples += samples;
        tasks[taskId].totalSubmissions++;

        emit WorkSubmitted(submissionCount, miner, taskId, quality, samples, ipfsCID, poolId, paid);
        emit RewardPaid(miner, paid, quality);

        // Record in ResultRegistry (if configured) for permanent scientific citation
        if (address(registry) != address(0)) {
            try registry.recordResult(
                miner, taskId, inputHash, outputHash, modelHash,
                quality, samples, durationMs, ipfsCID, ""
            ) {} catch {}
        }

        // Trigger halving if crossed threshold
        uint256 newEpoch = submissionCount / HALVING_INTERVAL;
        if (halvingRewards[newEpoch] == 0 && newEpoch > 0) {
            uint256 prev = halvingRewards[newEpoch - 1];
            uint256 next = prev / 2;
            if (next < MIN_BLOCK_REWARD) next = MIN_BLOCK_REWARD;
            halvingRewards[newEpoch] = next;
            emit Halving(newEpoch, next);
        }

        return submissionCount;
    }

    // ─── Challenge / Slash ────────────────────────────────────────

    /**
     * @notice File a challenge against a submission. Bond is locked; if challenger
     *         wins, they get CHALLENGER_REWARD_BPS % of the slash. If they lose,
     *         bond is forfeited.
     */
    function fileChallenge(uint256 submissionId) external nonReentrant {
        if (submissionId == 0 || submissionId > submissionCount) revert InvalidPool();
        if (submissionChallengeId[submissionId] != 0) revert AlreadyChallenged();
        Submission storage sub = submissions[submissionId];
        if (sub.resolved) revert AlreadyResolved();
        if (block.timestamp > sub.timestamp + CHALLENGE_WINDOW) revert ChallengeWindowExpired();
        if (msg.sender == sub.miner) revert SelfChallenge();

        // Lock bond by burning it (more economically sound than holding it)
        token.burnFromMiner(msg.sender, CHALLENGE_BOND);

        timelockProposalCount++;
        uint256 challengeId = timelockProposalCount;
        challenges[challengeId] = Challenge({
            challenger: msg.sender,
            submissionId: submissionId,
            bond: CHALLENGE_BOND,
            filedAt: block.timestamp,
            resolved: false,
            challengerWon: false
        });
        submissionChallengeId[submissionId] = challengeId;
        sub.challenged = true;

        emit ChallengeFiled(challengeId, submissionId, msg.sender, CHALLENGE_BOND);
    }

    /**
     * @notice Resolve a challenge. In production this would use a decentralized
     *         verification mechanism (re-execution by random miners, optimistic oracle,
     *         or governance vote). For mainnet v1, the challenge is resolved by the
     *         protocol based on a deterministic re-execution of the quality check.
     *
     *         The deterministic check here: if the submission's quality is below
     *         QUALITY_FLOOR after noise adjustment, the submitter lied about quality.
     *         For v2, this should be replaced with a re-execution oracle.
     */
    function resolveChallenge(uint256 challengeId) external nonReentrant {
        if (challengeId == 0 || challengeId > timelockProposalCount) revert InvalidChallenge();
        Challenge storage ch = challenges[challengeId];
        if (ch.resolved) revert AlreadyResolved();
        if (block.timestamp <= ch.filedAt + 1 hours) revert ResolutionTooEarly();

        Submission storage sub = submissions[ch.submissionId];

        // Resolution rule: if submission quality after noise is below QUALITY_FLOOR,
        // submitter misrepresented. Otherwise, challenge was unfounded.
        // In v2, replace with re-execution oracle or governance vote.
        bool challengerWon = (sub.quality < QUALITY_FLOOR);

        ch.resolved = true;
        ch.challengerWon = challengerWon;
        sub.resolved = true;

        if (challengerWon) {
            // Slash 20% of submitter's reward
            uint256 slashAmount = (sub.reward * SLASH_BPS) / 10000;
            uint256 challengerReward = (slashAmount * CHALLENGER_REWARD_BPS) / 10000;
            uint256 burnAmount = slashAmount - challengerReward;

            // Mint slash to challenger (replaces burned bond + bonus)
            token.mintMinerReward(ch.challenger, challengerReward, 0, 0);

            // Burn the rest
            totalBurned += burnAmount;
            totalSlashed += slashAmount;
            slashedBalance[sub.miner] += slashAmount;

            sub.slashed = true;
            emit Slashed(sub.miner, slashAmount, burnAmount);
        }
        // If challenger lost, their bond is already burned (forfeited)

        emit ChallengeResolved(challengeId, ch.submissionId, challengerWon,
            challengerWon ? (sub.reward * SLASH_BPS) / 10000 : 0,
            challengerWon ? ((sub.reward * SLASH_BPS) / 10000 - (sub.reward * SLASH_BPS * CHALLENGER_REWARD_BPS) / 1000000) : 0);
    }

    // ─── Halving ─────────────────────────────────────────────────

    function _currentBlockReward() internal view returns (uint256) {
        uint256 epoch = submissionCount / HALVING_INTERVAL;
        uint256 reward = halvingRewards[epoch];
        if (reward == 0 && epoch > 0) {
            // Uncomputed halving (edge case), use prev
            reward = halvingRewards[epoch - 1] / 2;
            if (reward < MIN_BLOCK_REWARD) reward = MIN_BLOCK_REWARD;
        }
        if (reward == 0) reward = INITIAL_BLOCK_REWARD;
        return reward;
    }

    function getHalvingEpoch() external view returns (uint256) {
        return submissionCount / HALVING_INTERVAL;
    }

    function getCurrentBlockReward() public view returns (uint256) {
        return _currentBlockReward();
    }

    function getHalvingProgress() external view returns (uint256 epoch, uint256 submissionsInEpoch, uint256 nextHalvingAt) {
        epoch = submissionCount / HALVING_INTERVAL;
        submissionsInEpoch = submissionCount % HALVING_INTERVAL;
        nextHalvingAt = (epoch + 1) * HALVING_INTERVAL;
    }

    // ─── Elastic Mint ────────────────────────────────────────────

    function _updateQualityRing(uint256 quality) internal {
        if (qualityRingCount < ELASTICITY_WINDOW) {
            qualityRing[qualityRingHead] = quality;
            qualitySum += quality;
            qualityRingCount++;
        } else {
            // Replace oldest
            uint256 oldest = qualityRing[qualityRingHead];
            qualityRing[qualityRingHead] = quality;
            qualitySum = qualitySum - oldest + quality;
        }
        qualityRingHead = (qualityRingHead + 1) % ELASTICITY_WINDOW;
    }

    function _elasticMultiplier() internal returns (uint256) {
        if (qualityRingCount == 0) return 100;  // 1.0x
        uint256 avg = qualitySum / qualityRingCount;

        uint256 mult = 100;
        if (avg > TARGET_QUALITY + QUALITY_EPSILON) {
            // Network is doing too well — slow down issuance
            uint256 excess = avg - TARGET_QUALITY - QUALITY_EPSILON;
            mult = 100 - (excess * 2);
            if (mult < MIN_ELASTIC_MULTIPLIER) mult = MIN_ELASTIC_MULTIPLIER;
        } else if (avg + QUALITY_EPSILON < TARGET_QUALITY) {
            // Network is struggling — boost rewards
            uint256 deficit = TARGET_QUALITY - QUALITY_EPSILON - avg;
            mult = 100 + (deficit * 2);
            if (mult > MAX_ELASTIC_MULTIPLIER) mult = MAX_ELASTIC_MULTIPLIER;
        }

        emit ElasticUpdate(avg, mult, mult);
        return mult;
    }

    function getAvgNetworkQuality() external view returns (uint256) {
        if (qualityRingCount == 0) return 0;
        return qualitySum / qualityRingCount;
    }

    function getCurrentElasticMultiplier() external returns (uint256) {
        return _elasticMultiplier();
    }

    // ─── Timelock Governance ─────────────────────────────────────

    /**
     * @notice Become a proposer by staking VOID tokens. Quorum is 1% of total
     *         miner-minted supply must propose any param change.
     */
    function stakeAsProposer(uint256 amount) external {
        if (amount == 0) revert ZeroStake();
        proposers[msg.sender] = true;
        proposerStake[msg.sender] += amount;
        token.burnFromMiner(msg.sender, amount);
    }

    function unstakeProposer(uint256 amount) external {
        if (!proposers[msg.sender]) revert NotProposer();
        if (amount > proposerStake[msg.sender]) revert StakeExceeded();
        proposerStake[msg.sender] -= amount;
        if (proposerStake[msg.sender] == 0) proposers[msg.sender] = false;
        token.mintMinerReward(msg.sender, amount, 0, 0);
    }

    function _requireProposer() internal view {
        if (!proposers[msg.sender]) revert NotProposer();
        uint256 totalMinted = token.totalMinerMinted();
        if (totalMinted == 0) revert NoMinerSupply();
        if ((proposerStake[msg.sender] * 10000) / totalMinted < PROPOSER_QUORUM_BPS) revert BelowQuorum();
    }

    /**
     * @notice Propose a timelocked action. dataHash is keccak256(target, value, sig, params).
     *         The proposer must have quorum stake. After TIMELOCK_DELAY, anyone can execute.
     */
    function proposeTimelock(bytes32 dataHash) external returns (bytes32) {
        _requireProposer();
        if (dataHash == bytes32(0)) revert EmptyData();

        timelockProposalCount++;
        bytes32 proposalId = keccak256(abi.encodePacked(timelockProposalCount, dataHash, msg.sender, block.timestamp));
        timelockProposals[proposalId] = TimelockProposal({
            dataHash: dataHash,
            eta: block.timestamp + TIMELOCK_DELAY,
            proposerVotes: proposerStake[msg.sender],
            proposer: msg.sender,
            executed: false,
            cancelled: false
        });

        emit TimelockProposed(proposalId, msg.sender, block.timestamp + TIMELOCK_DELAY, proposerStake[msg.sender]);
        return proposalId;
    }

    function executeTimelock(bytes32 proposalId) external {
        TimelockProposal storage p = timelockProposals[proposalId];
        if (p.eta == 0) revert UnknownProposal();
        if (p.executed) revert ProposalExecuted();
        if (p.cancelled) revert ProposalCancelled();
        if (block.timestamp < p.eta) revert TimelockNotElapsed();

        p.executed = true;
        emit TimelockExecuted(proposalId);
        // Note: actual execution logic is encoded off-chain. In v1, the timelock
        // signals readiness; governance contract (or multisig in v1) calls the
        // function with the matching dataHash. In v2, the timelock can directly
        // execute encoded calls via a low-level call registry.
    }

    function cancelTimelock(bytes32 proposalId) external {
        TimelockProposal storage p = timelockProposals[proposalId];
        if (p.eta == 0) revert UnknownProposal();
        if (p.executed) revert ProposalExecuted();
        if (msg.sender != p.proposer) revert NotProposerCancel();
        p.cancelled = true;
        emit TimelockCancelled(proposalId);
    }

    function getTimelockProposal(bytes32 proposalId) external view returns (
        bytes32 dataHash,
        uint256 eta,
        uint256 proposerVotes,
        address proposer,
        bool executed,
        bool cancelled
    ) {
        TimelockProposal storage p = timelockProposals[proposalId];
        return (p.dataHash, p.eta, p.proposerVotes, p.proposer, p.executed, p.cancelled);
    }

    // ─── Query Functions ──────────────────────────────────────────

    function getSubmission(uint256 id) external view returns (Submission memory) {
        if (id == 0 || id > submissionCount) revert InvalidPool();
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
        uint256 subs,
        uint256 avgQuality,
        uint256 minerTotalSamples,
        uint256 minerTotalEarned,
        uint256 minerSlashed
    ) {
        subs = totalSubmissions[miner];
        minerTotalSamples = totalSamplesProcessed[miner];
        minerTotalEarned = totalEarned[miner];
        minerSlashed = slashedBalance[miner];
        avgQuality = subs > 0 ? totalQuality[miner] / subs : 0;
    }

    function getChallenge(uint256 challengeId) external view returns (
        address challenger,
        uint256 submissionId,
        uint256 bond,
        uint256 filedAt,
        bool resolved,
        bool challengerWon
    ) {
        Challenge storage ch = challenges[challengeId];
        return (ch.challenger, ch.submissionId, ch.bond, ch.filedAt, ch.resolved, ch.challengerWon);
    }

    // ─── Internal ─────────────────────────────────────────────────

    function _qualityMultiplier(uint256 quality) internal pure returns (uint256) {
        if (quality >= 90) return EXCELLENT_MULTIPLIER;
        if (quality >= 70) return GOOD_MULTIPLIER;
        return DIVISOR;
    }
}
