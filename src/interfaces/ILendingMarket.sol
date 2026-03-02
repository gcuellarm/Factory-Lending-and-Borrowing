// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILendingMarket {
    
    // Structs
    struct MarketInfo {
        address token;                      // Token address of the market
        address lToken;                     // Liquidity token address
        uint256 totalSupply;                // Total amount deposited
        uint256 totalBorrow;                // Total amount borrowed
        uint256 supplyRate;                 // Current supply rate
        uint256 borrowRate;                 // Current borrow rate
        uint256 collateralFactor;           // Collateral factor
        uint256 reserveFactor;              // Reserve factor
        uint256 lastUpdateTimestamp;        // Last rate update 
        bool isActive;                      // Market's state
    }

    struct UserPosition {
        uint256 suppliedAmount;             // Amount deposited by the user
        uint256 borrowedAmount;             // Amount borrowed by the user
        uint256 supplyIndex;                // Supply's interest index
        uint256 borrowIndex;                // Borrow's interest index
        uint256 lastInterestUpdate;         // Last interest update
    }


    // Events
    event Deposit(address indexed user, uint256 amount, uint256 lTokensMinted);
    event Withdraw(address indexed user, uint256 amount, uint256 lTokensBurned);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidation(address indexed liquidator, address indexed borrower, uint256 repayAmount, uint256 seizedCollateral);
    event InterestAccrued(uint256 totalSupply, uint256 totalBorrow, uint256 supplyRate, uint256 borrowRate);

    // Functions
    /**
     * @dev Deposit tokens into the market
     * @param amount Amount of tokens to deposit
     * @return lTokensMinted Amount of lTokens minted
     */
    function deposit(uint256 amount) external returns(uint256);

    /**
     * @dev Withdraw tokens from the market
     * @param lTokenAmount Amount of lTokens to withdraw
     * @return amount Amount of tokens withdrawn
     */
    
    function withdraw(uint256 lTokenAmount) external returns(uint256);

    /**
     * @dev Borrow tokens from the market
     * @param amount Amount of tokens to borrow
     */
    function borrow(uint256 amount) external;

    /**
     * @dev Repay tokens to the market
     * @param amount Amount of tokens to repay
     */
    function repay(uint256 amount) external;

    /**
     * @dev Liquidate a borrower
     * @param borrower The address of the borrower
     * @param repayAmount Amount of tokens to liquidate that users owes
     */
    function liquidate(address borrower, uint256 repayAmount) external; 

    /**
     * @dev Update interest accumulated 
     */
    function accrueInterest() external;

    /**
     * @dev Returns the market info
     * @return MarketInfo The market info
     */
    function getMarketInfo() external view returns(MarketInfo memory);

    /**
     * @dev Returns the user position
     * @param user The address of the user
     * @return UserPosition The user position
     */
    function getUserPosition(address user) external view returns(UserPosition memory);

    /**
     * @dev Returns the liquidity and shortfall of a user
     * @param user The address of the user
     * @return liquidity The amount of liquidity the user has
     * @return shortfall Shortfall if it's in risky position
     */
    function getAccountLiquidity(address user) external view returns(uint256 liquidity, uint256 shortfall);


    function underlyingToken() external view returns (address);
    function lToken() external view returns (address);
}