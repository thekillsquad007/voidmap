// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./VoidmapToken.sol";

contract MiningPool is Ownable {
    VoidmapToken public token;
    uint256 public rewardPerQuality = 1 * 10**18; // 1 VOID per quality point
    uint256 public submissionCount;

    struct Submission {
        address miner;
        uint256 taskId;
        bytes32 inputHash;
        bytes32 outputHash;
        uint256 quality;
        uint256 samples;
        uint256 time;
    }

    mapping(uint256 => Submission) public submissions;
    mapping(address => uint256) public totalQuality;
    mapping(address => uint256) public totalSubmissions;

    event WorkSubmitted(uint256 id, address indexed miner, uint256 taskId, uint256 quality, uint256 samples);
    event RewardPaid(address indexed miner, uint256 amount);

    constructor(address _token) Ownable(msg.sender) {
        token = VoidmapToken(_token);
    }

    function submitWork(
        uint256 taskId,
        bytes32 inputHash,
        bytes32 outputHash,
        uint256 quality,
        uint256 samples
    ) external returns (uint256) {
        require(quality <= 100 && quality >= 10, "Quality 10-100");
        require(samples > 0, "Samples > 0");

        submissionCount++;
        submissions[submissionCount] = Submission(
            msg.sender, taskId, inputHash, outputHash, quality, samples, block.timestamp
        );
        totalQuality[msg.sender] += quality;
        totalSubmissions[msg.sender]++;

        uint256 reward = rewardPerQuality * quality;
        token.mintMinerReward(msg.sender, reward, taskId, quality);

        emit WorkSubmitted(submissionCount, msg.sender, taskId, quality, samples);
        emit RewardPaid(msg.sender, reward);
        return submissionCount;
    }

    function setReward(uint256 perQuality) external onlyOwner {
        rewardPerQuality = perQuality;
    }
}
