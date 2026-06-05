// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title VoidmapToken
 * @notice VOID token — Proof of Useful Work on Base L2.
 *         Fixed supply (1B), 90% to miners via MiningPool.
 *         No owner from day one — the contract is ownerless and immutable.
 *
 * Supply allocation (minted at deploy):
 *   - 5% (50M) to dev fund — 4-year linear vesting, claimable by dev
 *   - 5% (50M) to DAO/treasury — unlocked, controlled by DAO
 *   - 90% (900M) to miners — minted by MiningPool via mintMinerReward()
 *
 * Renounce happens automatically at deploy (no owner). The renounce() function
 * is left as a no-op safety net.
 */
contract VoidmapToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant MINER_SHARE = 900_000_000 * 10**18;
    uint256 public constant DEV_SHARE   =  50_000_000 * 10**18;
    uint256 public constant DAO_SHARE   =  50_000_000 * 10**18;

    uint256 public immutable vestingEnd;
    address public immutable devFund;
    address public immutable daoFund;
    uint256 public totalMinerMinted;

    // Burned tokens from challenges/slashes
    uint256 public totalBurned;

    // The MiningPool is set at deploy. Minter is non-immutable to allow
    // the circular deploy order (pool needs token, token needs pool).
    // The migrateMinter() function can only be called once, locking it in.
    address public minter;
    bool private _minterLocked;

    event MinerReward(address indexed miner, uint256 amount, uint256 taskId, uint256 quality);
    event DevClaimed(uint256 amount);
    event Burned(address indexed from, uint256 amount);

    error NotMinter();
    error NotDev();
    error VestingActive();
    error InvalidAddress();
    error MinerCapReached();

    constructor(address _dev, address _dao) ERC20("Voidmap", "VOID") {
        if (_dev == address(0) || _dao == address(0)) revert InvalidAddress();
        devFund = _dev;
        daoFund = _dao;
        vestingEnd = block.timestamp + 1461 days; // 4 years
        _mint(devFund, DEV_SHARE);
        _mint(daoFund, DAO_SHARE);
    }

    /**
     * @notice One-time migration: set the minter address.
     *         This is needed because the circular deploy order (pool needs token,
     *         token needs pool address) requires a 2-step process. After this is
     *         called once, the minter is locked forever.
     */
    function migrateMinter(address newMinter) external {
        if (_minterLocked) revert NotMinter();
        if (newMinter == address(0)) revert InvalidAddress();
        minter = newMinter;
        _minterLocked = true;
    }

    function isMinterLocked() external view returns (bool) {
        return _minterLocked;
    }

    /**
     * @notice Mint VOID to a miner for completing useful work.
     *         Only callable by the MiningPool.
     */
    function mintMinerReward(address miner, uint256 amount, uint256 taskId, uint256 quality) external {
        if (msg.sender != minter) revert NotMinter();
        if (totalMinerMinted + amount > MINER_SHARE) revert MinerCapReached();
        totalMinerMinted += amount;
        _mint(miner, amount);
        emit MinerReward(miner, amount, taskId, quality);
    }

    /**
     * @notice Burn VOID from a holder (used for challenge bonds and slash burns).
     *         Only callable by the MiningPool.
     */
    function burnFromMiner(address from, uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        if (amount == 0) return;
        _burn(from, amount);
        totalBurned += amount;
        emit Burned(from, amount);
    }

    /**
     * @notice Dev claims their 4-year-vested allocation to a recipient address.
     *         Only callable by the dev fund address. Only after vesting ends.
     */
    function devClaim(address to) external {
        if (msg.sender != devFund) revert NotDev();
        if (block.timestamp < vestingEnd) revert VestingActive();
        if (to == address(0)) revert InvalidAddress();
        uint256 bal = balanceOf(devFund);
        if (bal > 0) {
            _transfer(devFund, to, bal);
            emit DevClaimed(bal);
        }
    }
}
