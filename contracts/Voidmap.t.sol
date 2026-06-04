// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./VoidmapToken.sol";
import "./MiningPool.sol";

contract VoidmapTokenTest is Test {
    VoidmapToken token;
    address dev = makeAddr("dev");
    address dao = makeAddr("dao");
    address owner = makeAddr("owner");

    function setUp() public {
        vm.prank(owner);
        token = new VoidmapToken(dev, dao);
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

    function test_mintMinerReward() public {
        vm.prank(owner);
        token.mintMinerReward(makeAddr("miner1"), 100 * 10 ** 18, 1, 80);
        assertEq(token.balanceOf(makeAddr("miner1")), 100 * 10 ** 18);
        assertEq(token.totalMinerMinted(), 100 * 10 ** 18);
    }

    function test_mintMinerRewardCap() public {
        vm.startPrank(owner);
        token.mintMinerReward(makeAddr("miner1"), token.MINER_SHARE() - 1 * 10 ** 18, 1, 80);
        vm.expectRevert("Miner cap");
        token.mintMinerReward(makeAddr("miner2"), 2 * 10 ** 18, 1, 80);
        vm.stopPrank();
    }

    function test_mintBlockedAfterRenounce() public {
        vm.prank(owner);
        token.renounce();

        vm.expectRevert();
        token.mintMinerReward(makeAddr("miner2"), 100 * 10 ** 18, 1, 80);
    }

    function test_devClaimBeforeVesting() public {
        vm.prank(dev);
        vm.expectRevert("Vesting");
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

    function test_onlyDevCanClaim() public {
        vm.warp(token.vestingEnd() + 1);
        vm.prank(makeAddr("notdev"));
        vm.expectRevert("Only dev");
        token.devClaim(makeAddr("recipient"));
    }

    function test_onlyOwnerCanMint() public {
        vm.prank(makeAddr("notowner"));
        vm.expectRevert();
        token.mintMinerReward(makeAddr("miner1"), 100 * 10 ** 18, 1, 80);
    }

    function test_renounceAlsoRenouncesOwnership() public {
        vm.prank(owner);
        token.renounce();
        assertTrue(token.renounced());
        assertEq(token.owner(), address(0));
    }
}

contract MiningPoolTest is Test {
    VoidmapToken token;
    MiningPool pool;
    address dev = makeAddr("dev");
    address dao = makeAddr("dao");
    address owner = makeAddr("owner");
    address miner1 = makeAddr("miner1");
    address miner2 = makeAddr("miner2");
    address poolOperator = makeAddr("poolOperator");
    address feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        vm.prank(owner);
        token = new VoidmapToken(dev, dao);
        vm.prank(owner);
        pool = new MiningPool(address(token));
        vm.prank(owner);
        token.transferOwnership(address(pool));
    }

    function test_createTask() public {
        vm.prank(owner);
        uint256 taskId = pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");
        assertEq(taskId, 1);
        (string memory name, string memory dataSource, string memory modelSpec, uint256 totalSamples, uint256 totalSubmissions, bool active) = pool.tasks(taskId);
        assertEq(name, "Exoplanet Transit");
        assertTrue(active);
    }

    function test_submitWork() public {
        vm.prank(owner);
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
        (uint256 subs, uint256 avgQ, uint256 totalS) = pool.getMinerStats(miner1);
        assertEq(subs, 1);
        assertTrue(avgQ > 0 && avgQ <= 75);
        assertEq(totalS, 100);
    }

    function test_submitWorkRejectsLowQuality() public {
        vm.prank(owner);
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
        vm.prank(owner);
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
        vm.prank(owner);
        uint256 taskId = pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");
        vm.prank(owner);
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
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 55, 100, 1000);
        assertTrue(token.balanceOf(miner1) > 0);
        assertTrue(token.balanceOf(miner1) <= 55 * 10 ** 18); // noise may reduce quality
    }

    function test_qualityMultiplierGood() public {
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 75, 100, 1000);
        assertTrue(token.balanceOf(miner1) > 0);
    }

    function test_qualityMultiplierExcellent() public {
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        pool.submitWork(1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 95, 100, 1000);
        assertTrue(token.balanceOf(miner1) > 0);
    }

    function test_submitWorkCooldown() public {
        vm.prank(owner);
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
        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);
        assertEq(poolId, 1);
    }

    function test_submitPoolWork() public {
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);

        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);

        vm.prank(poolOperator);
        pool.submitPoolWork(
            poolId,
            1,
            miner1,
            keccak256("input"),
            keccak256("output"),
            keccak256("model"),
            "QmPoolCID",
            75,
            100,
            5000
        );

        assertEq(pool.submissionCount(), 1);
    }

    function test_submitPoolWorkRejectsNonOperator() public {
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);

        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);

        vm.prank(miner2);
        vm.expectRevert("Not pool operator");
        pool.submitPoolWork(
            poolId,
            1,
            miner1,
            keccak256("input"),
            keccak256("output"),
            keccak256("model"),
            "QmPoolCID",
            75,
            100,
            5000
        );
    }

    function test_submitPoolWorkRejectsNonMember() public {
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);

        vm.prank(poolOperator);
        vm.expectRevert("Not pool member");
        pool.submitPoolWork(
            poolId,
            1,
            miner1,
            keccak256("input"),
            keccak256("output"),
            keccak256("model"),
            "QmPoolCID",
            75,
            100,
            5000
        );
    }

    function test_poolFeeDeducted() public {
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);
        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);

        vm.prank(poolOperator);
        pool.submitPoolWork(poolId, 1, miner1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 55, 100, 1000);

        assertTrue(token.balanceOf(miner1) > 0);
        (, , uint256 poolFees, , , ) = pool.getPoolStats(poolId);
        assertTrue(poolFees > 0);
    }

    function test_withdrawPoolFees() public {
        vm.prank(owner);
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

    function test_withdrawPoolFeesRejectsNonOperator() public {
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);
        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);

        vm.prank(poolOperator);
        pool.submitPoolWork(poolId, 1, miner1, keccak256("i"), keccak256("o"), keccak256("m"), "Qm1", 55, 100, 1000);

        vm.prank(miner2);
        vm.expectRevert("Not pool operator");
        pool.withdrawPoolFees(poolId);
    }

    function test_addRemovePoolMember() public {
        vm.prank(poolOperator);
        uint256 poolId = pool.createPool("TestPool", feeRecipient);

        vm.prank(poolOperator);
        pool.addPoolMember(poolId, miner1);

        address[] memory members = pool.getPoolMembers(poolId);
        assertTrue(members.length >= 2); // operator + miner1

        vm.prank(poolOperator);
        pool.removePoolMember(poolId, miner1);

        (, , , , uint256 memberCount, ) = pool.getPoolStats(poolId);
        assertEq(memberCount, members.length); // array not shrunk, but isMember=false
    }

    function test_deactivateTask() public {
        vm.prank(owner);
        uint256 taskId = pool.createTask("Test", "Source", "Model");
        vm.prank(owner);
        pool.deactivateTask(taskId);
        (,,,,, bool active) = pool.tasks(taskId);
        assertFalse(active);
    }

    function test_submitWorkEmptyCIDRejected() public {
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        vm.expectRevert("IPFS CID required");
        pool.submitWork(
            1,
            keccak256("input"),
            keccak256("output"),
            keccak256("model"),
            "",
            75,
            100,
            5000
        );
    }

    function test_submitWorkZeroSamplesRejected() public {
        vm.prank(owner);
        pool.createTask("Exoplanet Transit", "MAST TESS", "AstroNetCNN");

        vm.prank(miner1);
        vm.expectRevert("Samples > 0");
        pool.submitWork(
            1,
            keccak256("input"),
            keccak256("output"),
            keccak256("model"),
            "QmTest",
            75,
            0,
            5000
        );
    }
}
