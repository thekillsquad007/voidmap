// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DataMarketplace is ReentrancyGuard, Ownable {
    IERC20 public token;

    struct Listing {
        uint256 id;
        address seller;
        string ipfsCid;
        uint8 taskType;       // 0=exoplanet, 1=galaxy, 2=anomaly
        uint8 qualityScore;   // 0-100
        uint256 price;
        bool sold;
        uint256 timestamp;
    }

    uint256 public counter;
    uint256 public totalVolume;
    uint256 public feeBps = 100;

    mapping(uint256 => Listing) public listings;
    mapping(address => uint256) public reputation;

    event Listed(uint256 id, address seller, uint8 taskType, uint256 price);
    event Sold(uint256 id, address buyer, uint256 price);
    event Cancelled(uint256 id);

    constructor(address _token) Ownable(msg.sender) {
        token = IERC20(_token);
    }

    function list(string calldata ipfsCid, uint8 taskType, uint8 qualityScore, uint256 price) external returns (uint256) {
        require(qualityScore <= 100 && price > 0);
        counter++;
        listings[counter] = Listing(counter, msg.sender, ipfsCid, taskType, qualityScore, price, false, block.timestamp);
        emit Listed(counter, msg.sender, taskType, price);
        return counter;
    }

    function buy(uint256 id) external nonReentrant {
        Listing storage l = listings[id];
        require(!l.sold && l.id == id);
        require(msg.sender != l.seller);

        uint256 fee = (l.price * feeBps) / 10000;
        uint256 net = l.price - fee;

        token.transferFrom(msg.sender, address(this), l.price);
        token.transfer(l.seller, net);

        l.sold = true;
        totalVolume += l.price;
        reputation[l.seller]++;
        emit Sold(id, msg.sender, l.price);
    }

    function cancel(uint256 id) external {
        Listing storage l = listings[id];
        require(l.seller == msg.sender && !l.sold);
        l.sold = true;
        emit Cancelled(id);
    }

    function setFee(uint256 bps) external onlyOwner {
        require(bps <= 500);
        feeBps = bps;
    }
}
