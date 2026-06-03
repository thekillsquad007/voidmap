// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VoidmapToken is ERC20, ERC20Burnable, Ownable {
    uint256 public constant SUPPLY = 1_000_000_000 * 10**18;

    bool public immutable locked;
    uint256 public immutable devFundVestingEnd;
    mapping(address => uint256) public lastClaim;

    event DevTokensClaimed(address indexed recipient, uint256 amount);

    constructor(address devFund, address daoFund) ERC20("Voidmap", "VOID") Ownable(msg.sender) {
        _mint(devFund, 120_000_000 * 10**18);    // 12% dev fund — vested
        _mint(daoFund, 150_000_000 * 10**18);     // 15% DAO treasury
        _mint(address(this), 100_000_000 * 10**18); // 10% vesting pool
        // Remaining 63% allocated elsewhere (sale, LP, airdrop, miners, partners)

        devFundVestingEnd = block.timestamp + 4 * 365 days;
        locked = true;
    }

    function claimDevTokens(address recipient, uint256 amount) external onlyOwner {
        require(locked, "Already unlocked");
        require(block.timestamp >= devFundVestingEnd, "Vesting not ended");
        require(amount > 0 && balanceOf(address(this)) >= amount, "Insufficient pool");
        _transfer(address(this), recipient, amount);
        emit DevTokensClaimed(recipient, amount);
    }

    function renounce() external onlyOwner {
        renounceOwnership();
    }
}
