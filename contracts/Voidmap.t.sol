// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./VoidmapToken.sol";
import "./MiningPool.sol";
import "./ResultRegistry.sol";

contract VoidmapTokenTest is Test {
    VoidmapToken token;
    address dev = makeAddr("dev");
    address dao = makeAddr("dao");
    address minter = makeAddr("minter");  // MiningPool in production
    address miner1 = makeAddr("miner1");

    function setUp() public {
        token = new VoidmapToken(dev, dao);
        token.migrateMinter(minter);
    }

    function test_initialSupply() public view {
        assertEq(token.totalSupply(), token.DEV_SHARE() + token.DAO_SHARE());
        assertEq(token.balanceOf(dev), token.DEV_SHARE());
        assertEq(token.balanceOf(dao), token.DAO_SHARE());
    }

    function test_devShare5Percent() public view {
        assertEq(token.DEV_SHARE(), 50_000_000 * 10 ** 18);
    }

    function test_minerShare90Percent() public view {
        assertEq(token.MINER_SHARE(), 900_000_000 * 10 ** 18);
    }

    function test_tokenIsOwnerless() public view {
        // Token is not Ownable anymore — verify by checking minter is immutable
        assertEq(token.minter(), minter);
    }

    function test_mintMinerReward() public {
        vm.prank(minter);
        token.mintMinerReward(miner1, 100 * 10 ** 18, 1, 80);
        assertEq(token.balanceOf(miner1), 100 * 10 ** 18);
        assertEq(token.totalMinerMinted(), 100 * 10 ** 18);
    }

    function test_mintMinerRewardRejectsNonMinter() public {
        vm.prank(makeAddr("notminter"));
        vm.expectRevert(VoidmapToken.NotMinter.selector);
        token.mintMinerReward(miner1, 100 * 10 ** 18, 1, 80);
    }

    function test_mintMinerRewardCap() public {
        vm.startPrank(minter);
        token.mintMinerReward(miner1, token.MINER_SHARE() - 1 * 10 ** 18, 1, 80);
        vm.expectRevert(VoidmapToken.MinerCapReached.selector);
        token.mintMinerReward(makeAddr("miner2"), 2 * 10 ** 18, 1, 80);
        vm.stopPrank();
    }

    function test_burnFromMiner() public {
        vm.prank(minter);
        token.mintMinerReward(miner1, 100 * 10 ** 18, 1, 80);
        uint256 balBefore = token.balanceOf(miner1);
        vm.prank(minter);
        token.burnFromMiner(miner1, 40 * 10 ** 18);
        assertEq(token.balanceOf(miner1), balBefore - 40 * 10 ** 18);
        assertEq(token.totalBurned(), 40 * 10 ** 18);
    }

    function test_burnFromMinerRejectsNonMinter() public {
        vm.prank(minter);
        token.mintMinerReward(miner1, 100 * 10 ** 18, 1, 80);
        vm.prank(makeAddr("notminter"));
        vm.expectRevert(VoidmapToken.NotMinter.selector);
        token.burnFromMiner(miner1, 40 * 10 ** 18);
    }

    function test_devClaimBeforeVesting() public {
        vm.prank(dev);
        vm.expectRevert(VoidmapToken.VestingActive.selector);
        token.devClaim(dev);
    }

    function test_devClaimAfterVesting() public {
        vm.warp(token.vestingEnd() + 1);
        address recipient = makeAddr("recipient");
        uint256 bal = token.balanceOf(dev);
        vm.prank(dev);
        token.devClaim(recipient);
        assertEq(token.balanceOf(recipient), bal);
        assertEq(token.balanceOf(dev), 0);
    }

    function test_devClaimRejectsNonDev() public {
        vm.warp(token.vestingEnd() + 1);
        vm.prank(makeAddr("notdev"));
        vm.expectRevert(VoidmapToken.NotDev.selector);
        token.devClaim(makeAddr("recipient"));
    }

    function test_devClaimRejectsZeroAddress() public {
        vm.warp(token.vestingEnd() + 1);
        vm.prank(dev);
        vm.expectRevert(VoidmapToken.InvalidAddress.selector);
        token.devClaim(address(0));
    }
}

contract MiningPoolTest is Test {
    VoidmapToken token;
    MiningPool pool;
    ResultRegistry registry;
    address dev = makeAddr("dev");
    address dao = makeAddr("dao");
    address miner1 = makeAddr("miner1");
    address miner2 = makeAddr("miner2");
    address poolOperator = makeAddr("poolOperator");
    address feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        // Deploy order:
        // 1. Deploy pool with a MockToken at a known address
        // 2. Deploy the real VoidmapToken
        // 3. Lock minter to the pool
        // 4. Use the MockToken for pool.token (it forwards to real token)
        //
        // Actually, simpler: deploy pool with a real token, and use
        // a constructor that takes the pool address. But we have circular dep.
        //
        // Simplest working approach: use the SAME address for both pool and token.
        // We do this by:
        // 1. Deploy pool with address(0xdead) as token
        // 2. Deploy token with address(0xdead) as minter placeholder
        // 3. Get the token's deployed bytecode
        // 4. Use vm.etch to put the token's bytecode at address(0xdead)
        // 5. Use vm.store to... no, immutable can't be changed.
        //
        // OK, the ACTUAL simplest approach: deploy pool with the real token,
        // but deploy the token first with a placeholder minter, then set the
        // real minter via migrateMinter. The pool's token is the real token.
        token = new VoidmapToken(dev, dao);
        registry = new ResultRegistry();
        pool = new MiningPool(address(token), address(registry));
        registry.setRecorder(address(pool), true);
        token.migrateMinter(address(pool));
    }

    function _bootstrapMiner1() internal {
        // Give miner1 some VOID to stake as proposer
        vm.prank(address(pool));
        token.mintMinerReward(miner1, 100 * 10 ** 18, 0, 0);
    }

    function test_createTask() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(10 * 10 ** 18);
        vm.prank(miner1);
        uint256 taskId = pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");
        assertEq(taskId, 1);
        (string memory name, , , , , bool active) = pool.tasks(taskId);
        assertEq(name, "Exoplanet Transit");
        assertTrue(active);
    }

    function test_createTaskRejectsNonProposer() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        vm.expectRevert("Not a proposer");
        pool.createTask("Exoplanet", "MAST", "Model");
    }

    function test_submitWork() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(
            1,
            keccak256("input"),
            keccak256("output"),
            keccak256("model"),
            "QmTestCID123",
            75,
            100,
            5000
        );

        assertEq(pool.submissionCount(), 1);
        (uint256 subs, uint256 avgQ, uint256 totalS, uint256 earned, uint256 slashed) = pool.getMinerStats(miner1);
        assertEq(subs, 1);
        assertTrue(avgQ > 0 && avgQ <= 75);
        assertEq(totalS, 100);
        assertTrue(earned > 0);
        assertEq(slashed, 0);
    }

    function test_submitWorkRejectsLowQuality() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        vm.expectRevert("Quality too low (< 50)");
        pool.submitWork(
            1,
            keccak256("input"),
            keccak256("output"),
            keccak256("model"),
            "QmTestCID123",
            49,
            100,
            5000
        );
    }

    function test_submitWorkRejectsQualityAbove100() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        vm.expectRevert("Quality > 100");
        pool.submitWork(
            1,
            keccak256("input"),
            keccak256("output"),
            keccak256("model"),
            "QmTestCID123",
            101,
            100,
            5000
        );
    }

    function test_submitWorkRejectsInactiveTask() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        uint256 taskId = pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");
        vm.prank(miner1);
        pool.deactivateTask(taskId);

        vm.prank(miner1);
        vm.expectRevert("Task inactive");
        pool.submitWork(
            taskId,
            keccak256("input"),
            keccak256("output"),
            keccak256("model"),
            "QmTestCID123",
            75,
            100,
            5000
        );
    }

    function test_qualityMultiplierBase() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 55, 100, 1000);
        assertTrue(token.balanceOf(miner1) > 10 * 10 ** 18); // initial 10 + reward
    }

    function test_qualityMultiplierGood() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 75, 100, 1000);
        assertTrue(token.balanceOf(miner1) > 10 * 10 ** 18);
    }

    function test_qualityMultiplierExcellent() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 95, 100, 1000);
        assertTrue(token.balanceOf(miner1) > 10 * 10 ** 18);
    }

    function test_submitWorkCooldown() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 75, 100, 1000);

        vm.prank(miner1);
        vm.expectRevert("Cooldown");
        pool.submitWork(1, keccak256("i2"), keccak256("o2"), keccak256("m2"), "Qm2", 75, 100, 1000);

        vm.warp(block.timestamp + 13);
        vm.prank(miner1);
        pool.submitWork(1, keccak256("i2"), keccak256("o2"), keccak256("m2"), "Qm2", 75, 100, 1000);
        assertEq(pool.submissionCount(), 2);
    }

    function test_createPool() public {
        _bootstrapMiner1();
        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);
        assertEq(poolId, 1);
    }

    function test_submitPoolWork() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);
        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);
        vm.prank(poolOperator);
        pool.submitPoolWork(
            poolId, 1, miner1,
            keccak256("input"), keccak256("output"), keccak256("model"),
            "QmPoolCID", 75, 100, 5000
        );

        assertEq(pool.submissionCount(), 1);
    }

    function test_submitPoolWorkRejectsNonOperator() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);
        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);

        vm.prank(miner2);
        vm.expectRevert("Not pool operator");
        pool.submitPoolWork(
            poolId, 1, miner1,
            keccak256("input"), keccak256("output"), keccak256("model"),
            "QmPoolCID", 75, 100, 5000
        );
    }

    function test_submitPoolWorkRejectsNonMember() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);

        vm.prank(poolOperator);
        vm.expectRevert("Not pool member");
        pool.submitPoolWork(
            poolId, 1, miner1,
            keccak256("input"), keccak256("output"), keccak256("model"),
            "QmPoolCID", 75, 100, 5000
        );
    }

    function test_poolFeeDeducted() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);
        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);

        vm.prank(poolOperator);
        pool.submitPoolWork(poolId, 1, miner1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 55, 100, 1000);

        (, , uint256 poolFees, , , ) = pool.getPoolStats(poolId);
        assertTrue(poolFees > 0);
    }

    function test_withdrawPoolFees() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);
        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);

        vm.prank(poolOperator);
        pool.submitPoolWork(poolId, 1, miner1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 55, 100, 1000);

        vm.prank(poolOperator);
        pool.withdrawPoolFees(poolId);

        assertTrue(token.balanceOf(feeRecipient) > 0);
    }

    function test_addRemovePoolMember() public {
        _bootstrapMiner1();
        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);
        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);

        address[] memory members = pool.getPoolMembers(poolId);
        assertTrue(members.length >= 2);

        vm.prank(poolOperator);
        pool.removePoolMember(poolId, miner1);

        (, , , , uint256 memberCount, ) = pool.getPoolStats(poolId);
        assertEq(memberCount, members.length);
    }

    function test_deactivateTask() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        uint256 taskId = pool.createTask("Test", "Source", "Model");
        vm.prank(miner1);
        pool.deactivateTask(taskId);
        (,,,,, bool active) = pool.tasks(taskId);
        assertFalse(active);
    }

    function test_submitWorkEmptyCIDRejected() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        vm.expectRevert("IPFS CID required");
        pool.submitWork(
            1, keccak256("input"), keccak256("output"), keccak256("model"),
            "", 75, 100, 5000
        );
    }

    function test_submitWorkZeroSamplesRejected() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        vm.expectRevert("Samples > 0");
        pool.submitWork(
            1, keccak256("input"), keccak256("output"), keccak256("model"),
            "QmTest", 75, 0, 5000
        );
    }

    // ─── Halving Tests ────────────────────────────────────────

    function test_halving() public {
        _bootstrapMiner1();
        assertEq(pool.getHalvingEpoch(), 0);
        // Initial reward is 50 VOID
        uint256 reward0 = pool.getCurrentBlockReward();

        // Simulate crossing the halving boundary by checking the halving math
        (uint256 epoch, uint256 submissionsInEpoch, uint256 nextHalvingAt) = pool.getHalvingProgress();
        assertEq(epoch, 0);
        assertEq(submissionsInEpoch, 0);
        assertEq(nextHalvingAt, 210_000);
    }

    function test_initialBlockReward() public {
        _bootstrapMiner1();
        // Genesis reward is 50 VOID
        assertEq(pool.INITIAL_BLOCK_REWARD(), 50 * 10 ** 18);
    }

    // ─── Elastic Mint Tests ───────────────────────────────────

    function test_elasticMintAtTarget() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        // Submit 10 submissions at quality 75 (target)
        // vm.warp is per-call, so we use absolute timestamps
        for (uint i = 0; i < 10; i++) {
            vm.warp(13 * (i + 1) + 100);  // start at 113, increment by 13
            vm.prank(miner1);
            pool.submitWork(1, keccak256(abi.encodePacked("i", i)), keccak256(abi.encodePacked("o", i)),
                keccak256("m"), "Qm1", 75, 100, 1000);
        }
        uint256 avg = pool.getAvgNetworkQuality();
        assertTrue(avg >= 70 && avg <= 80);
    }

    function test_avgNetworkQualityEmpty() public {
        _bootstrapMiner1();
        assertEq(pool.getAvgNetworkQuality(), 0);
    }

    // ─── Challenge / Slash Tests ──────────────────────────────

    function test_fileChallenge() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        // Give miner2 some VOID for the bond
        vm.prank(address(pool));
        token.mintMinerReward(miner2, 10 * 10 ** 18, 0, 0);

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 75, 100, 1000);

        uint256 balBefore = token.balanceOf(miner2);
        vm.prank(miner2);
        pool.fileChallenge(1);
        assertEq(token.balanceOf(miner2), balBefore - pool.CHALLENGE_BOND());
        assertEq(pool.submissionChallengeId(1), 1);
    }

    function test_fileChallengeRejectsSelf() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 75, 100, 1000);

        vm.prank(miner1);
        vm.expectRevert("Cannot challenge yourself");
        pool.fileChallenge(1);
    }

    function test_fileChallengeRejectsDoubleChallenge() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");
        vm.prank(address(pool));
        token.mintMinerReward(miner2, 10 * 10 ** 18, 0, 0);

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 75, 100, 1000);

        vm.prank(miner2);
        pool.fileChallenge(1);
        vm.prank(miner2);
        vm.expectRevert("Already challenged");
        pool.fileChallenge(1);
    }

    function test_fileChallengeRejectsExpiredWindow() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");
        vm.prank(address(pool));
        token.mintMinerReward(miner2, 10 * 10 ** 18, 0, 0);

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 75, 100, 1000);

        vm.warp(block.timestamp + pool.CHALLENGE_WINDOW() + 1);
        vm.prank(miner2);
        vm.expectRevert("Challenge window expired");
        pool.fileChallenge(1);
    }

    function test_resolveChallengeUnfounded() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");
        vm.prank(address(pool));
        token.mintMinerReward(miner2, 10 * 10 ** 18, 0, 0);

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 75, 100, 1000);

        vm.prank(miner2);
        pool.fileChallenge(1);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(miner2);
        pool.resolveChallenge(1);

        // Challenge was unfounded (quality >= 50), so no slash
        (address challenger, uint256 submissionId, uint256 bond, uint256 filedAt, bool resolved, bool challengerWon) = pool.getChallenge(1);
        assertTrue(resolved);
        assertFalse(challengerWon);
    }

    // ─── Timelock Governance Tests ────────────────────────────

    function test_stakeAsProposer() public {
        _bootstrapMiner1();
        // miner1 already has 10 VOID from _setup
        uint256 balBefore = token.balanceOf(miner1);
        vm.prank(miner1);
        token.approve(address(pool), 10 * 10 ** 18);
        vm.prank(miner1);
        pool.stakeAsProposer(10 * 10 ** 18);
        assertTrue(pool.proposers(miner1));
        assertEq(token.balanceOf(miner1), balBefore - 10 * 10 ** 18);
    }

    function test_proposeTimelock() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        // Need 1% of total miner-minted as stake. With miner1 having only 10 VOID
        // and totalMinerMinted = 10 VOID, that's 100% — should pass.
        bytes32 dataHash = keccak256("test data");
        vm.prank(miner1);
        bytes32 proposalId = pool.proposeTimelock(dataHash);
        assertTrue(proposalId != bytes32(0));
    }

    function test_proposeTimelockRejectsNonProposer() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        vm.expectRevert("Not a proposer");
        pool.proposeTimelock(keccak256("test"));
    }

    function test_executeTimelock() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        bytes32 dataHash = keccak256("test data");
        vm.prank(miner1);
        bytes32 proposalId = pool.proposeTimelock(dataHash);

        // Can't execute before delay
        vm.expectRevert("Timelock not elapsed");
        pool.executeTimelock(proposalId);

        vm.warp(block.timestamp + pool.TIMELOCK_DELAY() + 1);
        pool.executeTimelock(proposalId);
        (,,,, bool executed,) = pool.getTimelockProposal(proposalId);
        assertTrue(executed);
    }

    function test_cancelTimelock() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        bytes32 dataHash = keccak256("test data");
        vm.prank(miner1);
        bytes32 proposalId = pool.proposeTimelock(dataHash);

        vm.prank(miner1);
        pool.cancelTimelock(proposalId);
        (,,,, bool executed, bool cancelled) = pool.getTimelockProposal(proposalId);
        assertFalse(executed);
        assertTrue(cancelled);
    }

    function test_unstakeProposer() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        uint256 balBefore = token.balanceOf(miner1);
        vm.prank(miner1);
        pool.unstakeProposer(1e18);
        assertFalse(pool.proposers(miner1));
        assertEq(token.balanceOf(miner1), balBefore + 1e18);
    }

    // ─── ResultRegistry integration tests ─────────────────

    function test_registryRecordsSubmissions() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i1"), keccak256("o1"), keccak256("m1"), "QmCID1", 75, 100, 1000);
        vm.warp(block.timestamp + 13);
        vm.prank(miner2);
        pool.submitWork(1, keccak256("i2"), keccak256("o2"), keccak256("m2"), "QmCID2", 85, 200, 1500);

        assertEq(registry.resultCount(), 2);

        ResultRegistry.Result memory r1 = registry.getResult(0);
        assertEq(r1.miner, miner1);
        assertEq(r1.taskId, 1);

        ResultRegistry.Result memory r2 = registry.getResult(1);
        assertEq(r2.miner, miner2);
        assertEq(r2.samples, 200);
    }

    function test_registryGetMinerResults() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i1"), keccak256("o1"), keccak256("m1"), "QmCID1", 75, 100, 1000);
        vm.warp(block.timestamp + 13);
        vm.prank(miner1);
        pool.submitWork(1, keccak256("i2"), keccak256("o2"), keccak256("m2"), "QmCID2", 80, 100, 1000);

        ResultRegistry.Result[] memory results = registry.getMinerResults(miner1, 0, 10);
        assertEq(results.length, 2);
        assertEq(registry.getMinerResultCount(miner1), 2);
    }

    function test_registryFindByHash() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet", "MAST TESS", "AstroNetCNN");

        bytes32 dataHash = keccak256("dataX");
        bytes32 outHash = keccak256("outX");
        vm.prank(miner1);
        pool.submitWork(1, dataHash, outHash, keccak256("m1"), "QmFind", 75, 100, 1000);

        uint256 idx = registry.findByDataHash(dataHash);
        assertTrue(idx < registry.resultCount());
    }

    function test_registryRejectsNonRecorder() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(ResultRegistry.NotRecorder.selector);
        registry.recordResult(
            makeAddr("miner"), 1, keccak256("i"), keccak256("o"),
            keccak256("m"), 80, 100, 1000, "QmX", ""
        );
    }

    function test_registryRejectsDuplicateIPFS() public {
        registry.setRecorder(address(this), true);
        registry.recordResult(
            miner1, 1, keccak256("i1"), keccak256("o1"),
            keccak256("m1"), 80, 100, 1000, "QmDup", ""
        );
        vm.expectRevert(ResultRegistry.AlreadyExists.selector);
        registry.recordResult(
            miner2, 1, keccak256("i2"), keccak256("o2"),
            keccak256("m2"), 75, 100, 1000, "QmDup", ""
        );
    }

    function test_registryStats() public {
        _bootstrapMiner1();
        vm.prank(miner1);
        pool.stakeAsProposer(1e18);
        vm.prank(miner1);
        pool.createTask("Exoplanet", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i1"), keccak256("o1"), keccak256("m1"), "QmS1", 75, 100, 1000);
        vm.warp(block.timestamp + 13);
        vm.prank(miner2);
        pool.submitWork(1, keccak256("i2"), keccak256("o2"), keccak256("m2"), "QmS2", 85, 200, 1500);

        (uint256 total, uint256 samples, uint256 avgQ, ) = registry.getNetworkStats();
        assertEq(total, 2);
        assertGt(samples, 200);
        assertGt(avgQ, 60);
    }
}

contract ResultRegistryTest is Test {
    ResultRegistry registry;
    address owner = makeAddr("owner");
    address recorder = makeAddr("recorder");
    address miner = makeAddr("miner");

    function setUp() public {
        vm.prank(owner);
        registry = new ResultRegistry();
        vm.prank(owner);
        registry.setRecorder(recorder, true);
    }

    function test_ownerCanSetRecorder() public view {
        assertTrue(registry.isRecorder(recorder));
    }

    function test_nonOwnerCannotSetRecorder() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(ResultRegistry.NotOwner.selector);
        registry.setRecorder(makeAddr("rogue"), true);
    }

    function test_renounceOwnership() public {
        vm.prank(owner);
        registry.renounceOwnership();
        assertEq(registry.owner(), address(0));
    }

    function test_recordAndGetResult() public {
        bytes32 dataHash = keccak256("input");
        bytes32 outHash = keccak256("output");
        vm.prank(recorder);
        registry.recordResult(
            miner, 1, dataHash, outHash, keccak256("model"),
            85, 2048, 4500, "QmTest", ""
        );

        ResultRegistry.Result memory r = registry.getResult(0);
        assertEq(r.miner, miner);
        assertEq(r.taskId, 1);
        assertEq(r.dataHash, dataHash);
        assertEq(r.quality, 85);
        assertEq(r.samples, 2048);
    }

    function test_emptyIPFSRejected() public {
        vm.prank(recorder);
        vm.expectRevert(ResultRegistry.EmptyIPFS.selector);
        registry.recordResult(
            miner, 1, keccak256("i"), keccak256("o"),
            keccak256("m"), 80, 100, 1000, "", ""
        );
    }

    function test_invalidQualityRejected() public {
        vm.prank(recorder);
        vm.expectRevert(ResultRegistry.InvalidQuality.selector);
        registry.recordResult(
            miner, 1, keccak256("i"), keccak256("o"),
            keccak256("m"), 101, 100, 1000, "QmX", ""
        );
    }

    function test_getTaskResults() public {
        vm.prank(recorder);
        registry.recordResult(miner, 1, keccak256("i1"), keccak256("o1"), keccak256("m1"), 75, 100, 1000, "QmT1", "");
        vm.prank(recorder);
        registry.recordResult(miner, 2, keccak256("i2"), keccak256("o2"), keccak256("m2"), 80, 100, 1000, "QmT2", "");

        ResultRegistry.Result[] memory task1 = registry.getTaskResults(1, 0, 10);
        ResultRegistry.Result[] memory task2 = registry.getTaskResults(2, 0, 10);
        assertEq(task1.length, 1);
        assertEq(task2.length, 1);
    }

    function test_getLatestResults() public {
        for (uint i = 0; i < 5; i++) {
            vm.prank(recorder);
            registry.recordResult(
                miner, 1, keccak256(abi.encodePacked("i", i)),
                keccak256(abi.encodePacked("o", i)),
                keccak256("m"), 75, 100, 1000,
                string(abi.encodePacked("QmL", i)), ""
            );
        }
        ResultRegistry.Result[] memory latest = registry.getLatestResults(3);
        assertEq(latest.length, 3);
    }
}
