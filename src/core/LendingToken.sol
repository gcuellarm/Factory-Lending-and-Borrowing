//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;    

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ILendingMarketLike {
    function exchangeRateStored() external view returns (uint256);
}

contract LendingToken is ERC20, Ownable {
    
    // State Variables
    IERC20 public immutable underlyingToken;    // The underlying token
    address public market;                      // Address of the market that controls this token
    bool public marketSet;                      // Whether the market has been set

    // Modifiers
    modifier onlyMarket(){
        require(msg.sender == market, "Only market can call this function");
        _;
    }

    // Events
    event Mint(address indexed user, uint256 amount);
    event Burn(address indexed user, uint256 amount);
    event MarketSet(address indexed market);

    constructor(string memory name, string memory symbol, address _underlyingToken) ERC20(name, symbol) Ownable(msg.sender) {
        require(_underlyingToken != address(0), "Invalid underlying token");
        underlyingToken = IERC20(_underlyingToken);
    }

    function setMarket(address _market) external onlyOwner {
        require(_market != address(0), "Invalid market address");
        require(!marketSet, "Market already set");

        marketSet = true;
        market = _market;

        emit MarketSet(_market);
    }

    function mint(address to, uint256 amount) external onlyMarket(){
        _mint(to, amount);
        emit Mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMarket(){
        _burn(from, amount);
        emit Burn(from, amount);
    }

    function underlying() external view returns (address) {
        return address(underlyingToken);
    }

    function balanceOfUnderlying(address account) external view returns (uint256) {
        require(marketSet, "Market not set");

        uint256 lBal = balanceOf(account);
        uint256 rate = ILendingMarketLike(market).exchangeRateStored(); // WAD 1e18

        return (lBal * rate) / 1e18;
    }

}