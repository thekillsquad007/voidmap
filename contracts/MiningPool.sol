// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MiningPool is Ownable {
    struct Submission {
        address miner;
        uint256 taskId;
        uint256 qualityScore;
        uint256 timestamp;
        bool paid;
    }

    uint256 public submissionCount;
    uint256 public rewardPerSubmission = 10 * 10**18;
    mapping(uint256 => Submission) public submissions;
    mapping(address => uint256) public totalScore;

    event Submitted(uint256 id, address indexed miner, uint256 taskId, uint256 quality);
    event RewardPaid(address indexed miner, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function submitWork(uint256 taskId, uint256 qualityScore) external returns (uint256) {
        require(qualityScore <= 100 && qualityScore >= 30);
        submissionCount++;
        submissions[submissionCount] = Submission(msg.sender, taskId, qualityScore, block.timestamp, false);
        totalScore[msg.sender] += qualityScore;
        emit Submitted(submissionCount, msg.sender, taskId, qualityScore);
        return submissionCount;
    }

    function setReward(uint256 amount) external onlyOwner {
        rewardPerSubmission = amount;
    }
}
