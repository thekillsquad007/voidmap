// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VoidmapToken is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant MINER_SHARE = 900_000_000 * 10**18; // 90%
    uint256 public constant DEV_SHARE   =  50_000_000 * 10**18; // 5%
    uint256 public constant DAO_SHARE   =  50_000_000 * 10**18; // 5%

    uint256 public immutable vestingEnd;
    address public immutable devFund;
    address public immutable daoFund;
    uint256 public totalMinerMinted;

    bool public renounced;

    event MinerReward(address indexed miner, uint256 amount, uint256 taskId, uint256 quality);
    event DevClaimed(uint256 amount);

    constructor(address _dev, address _dao) ERC20("Voidmap", "VOID") Ownable(msg.sender) {
        devFund = _dev;
        daoFund = _dao;
        vestingEnd = block.timestamp + 1461 days; // 4 years
        _mint(devFund, DEV_SHARE);
        _mint(daoFund, DAO_SHARE);
    }

    function mintMinerReward(address miner, uint256 amount, uint256 taskId, uint256 quality) external onlyOwner {
        require(!renounced, "Renounced");
        require(totalMinerMinted + amount <= MINER_SHARE, "Miner cap");
        totalMinerMinted += amount;
        _mint(miner, amount);
        emit MinerReward(miner, amount, taskId, quality);
    }

    function devClaim(address to) external {
        require(msg.sender == devFund, "Only dev");
        require(block.timestamp >= vestingEnd, "Vesting");
        require(to != address(0), "Invalid to");
        uint256 bal = balanceOf(devFund);
        if (bal > 0) {
            _transfer(devFund, to, bal);
            emit DevClaimed(bal);
        }
    }

    function renounce() external onlyOwner {
        renounced = true;
        renounceOwnership();
    }
}
