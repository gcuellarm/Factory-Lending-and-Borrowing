// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface ILendingToken {
    function underlying() external view returns (address);
}

contract PriceOracle is Ownable {
    
    //State variables
    uint256 public constant PRICE_DECIMALS = 8;
    address public immutable WETH;

    // Mappings
    mapping(address => uint256) public prices; // Mapping of token addresses to their prices in USD
    mapping(address => address) public priceFeeds; // Mapping of token addresses to their price feeds

    // Events
    event PriceUpdates(address indexed token, uint256 oldPrice, uint256 newPrice);  // Event emitted when a price is updated
    event PriceFeedSet(address indexed token, address indexed priceFeed); // Event emitted when a price feed is set


    constructor(address weth) Ownable(msg.sender) {
        require(weth != address(0), "Invalid WETH");
        WETH = weth;
    }

    function setPrice(address token, uint256 price) external onlyOwner {
        require(price > 0, "Price must be greater than 0");
        require(token!=address(0), "Invalid token address");
        
        uint256 oldPrice = prices[token];
        prices[token] = price;

        emit PriceUpdates(token, oldPrice, price);
    }

    function setPriceFeed(address token, address priceFeed) external onlyOwner(){
        require(token != address(0), "Invalid token address");
        require(priceFeed != address(0), "Invalid price feed address");

        priceFeeds[token] = priceFeed;
        
        emit PriceFeedSet(token, priceFeed);
    }

    function getPrice(address token) external view returns(uint256) {
        address priceFeed = priceFeeds[token];
        
        // If exists a Chainlink price feed, use it (decentralized)
        if (priceFeed != address(0)) {
            try AggregatorV3Interface(priceFeed).latestRoundData() returns (
                uint80,
                int256 answer,
                uint256,
                uint256,
                uint80
            ) {
                require(answer > 0, "Invalid price from Chainlink");
                return uint256(answer);
            } catch {
                // If Chainlink fails, use manual price as fallback
                uint256 fallbackPrice = prices[token];
                require(fallbackPrice > 0, "No fallback price available");
                return fallbackPrice;
            }
        }
        // If no price feed, use manual price
        uint256 manual = prices[token];
        require(manual > 0, "No price available");
        return manual;
    }

    function getPriceInEth(address token) external view returns (uint256) {
        uint256 ethPrice = this.getPrice(WETH);     // ETH price in USD
        uint256 tokenPrice = this.getPrice(token);  // token price in USD
        return (tokenPrice * 1e18) / ethPrice;
    }

    function getUnderlyingPrice(address lToken) external view returns(uint256) {
        // Get the underlying token from the lToken and return its price
        address underlying = ILendingToken(lToken).underlying();
        return this.getPrice(underlying);   
    }

    function batchGetPrices(address[] calldata tokens) external view returns(uint256[] memory) {
        uint256[] memory priceList = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            priceList[i] = this.getPrice(tokens[i]);  // Use hybrid system
        }
        return priceList;
    }
}