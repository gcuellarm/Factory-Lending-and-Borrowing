// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../core/LendingMarket.sol";
import "../core/LendingMarketFactory.sol";
import "../core/LendingToken.sol";
import "./GovernanceToken.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

interface ILendingMarketView {
    function lToken() external view returns (address);
    function totalBorrows() external view returns (uint256);
}

contract RewardsDistributor is Ownable {
    
    // State variables
    GovernanceToken public governanceToken;
    LendingMarketFactory public factory;
    uint256 public constant WAD = 1e18;

    struct RewardState{
        uint256 index; // WAD (1e18)
        uint256 lastBlockUpdated;
    }

    mapping(address => uint256) public supplyRewardSpeed;  // market => tokens per block (WAD)
    mapping(address => uint256) public borrowRewardSpeed;  // market => tokens per block (WAD)

    mapping(address => RewardState) public supplyState;  // market => state
    mapping(address => RewardState) public borrowState;  // market => state

    // Personal Indexes (market => user => index)
    mapping(address => mapping(address => uint256)) public supplierIndex; // market => user => index
    mapping(address => mapping(address => uint256)) public borrowerIndex; // market => user => index

    // Rewards acumuladas por usuario y market (market => user => accrued)
    mapping(address => mapping(address => uint256)) public supplierRewards; // market => user => accrued
    mapping(address => mapping(address => uint256)) public borrowerRewards; // market => user => accrued

    // Events
    event RewardSpeedUpdated(address indexed market, uint256 newSupplySpeed, uint256 newBorrowSpeed);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsAccrued(address indexed user, address indexed market, uint256 amount);

    // Modifiers
    modifier onlyMarket() {
        require(factory.isMarket(msg.sender), "Only market");
        _;
    }

    constructor(address token, address factory_) Ownable(msg.sender) {
        require(token != address(0), "Invalid token");
        require(factory_ != address(0), "Invalid factory");
        governanceToken = GovernanceToken(token);
        factory = LendingMarketFactory(factory_);
    }


    function updateSupplyIndex(address market) public {
        RewardState storage state = supplyState[market];
        require(factory.isMarket(market), "Market not supported");

        // init
        if (state.lastBlockUpdated == 0) {
            state.lastBlockUpdated = block.number;
            if (state.index == 0) state.index = WAD;
            return;
        }

        uint256 deltaBlocks = block.number - state.lastBlockUpdated;
        if (deltaBlocks == 0) return;

        uint256 speed = supplyRewardSpeed[market];
        state.lastBlockUpdated = block.number;

        if (speed == 0) return;

        address lTokenAddr = ILendingMarketView(market).lToken();
        uint256 lSupply = LendingToken(lTokenAddr).totalSupply();
        if (lSupply == 0) return;

        uint256 rewardsAccrued = deltaBlocks * speed; // tokens
        uint256 indexDelta = (rewardsAccrued * WAD) / lSupply;

        state.index += indexDelta;
    }

    function updateBorrowIndex(address market) public {
        RewardState storage state = borrowState[market];
        require(factory.isMarket(market), "Market not supported");

        // init
        if (state.lastBlockUpdated == 0) {
            state.lastBlockUpdated = block.number;
            if (state.index == 0) state.index = WAD;
            return;
        }

        uint256 deltaBlocks = block.number - state.lastBlockUpdated;
        if (deltaBlocks == 0) return;

        uint256 speed = borrowRewardSpeed[market];
        state.lastBlockUpdated = block.number;

        if (speed == 0) return;

        uint256 borrows = ILendingMarketView(market).totalBorrows();
        if (borrows == 0) return;

        uint256 rewardsAccrued = deltaBlocks * speed; // tokens
        uint256 indexDelta = (rewardsAccrued * WAD) / borrows;

        state.index += indexDelta;
    }

    function setRewardSpeed(address market, uint256 newSupplySpeed, uint256 newBorrowSpeed) external onlyOwner(){
        require(market != address(0), "Invalid market");
        require(factory.isMarket(market), "Market not supported");

        //1 Close acumulation with old speeds
        updateSupplyIndex(market);
        updateBorrowIndex(market);

        //2 Set nre speeds
        supplyRewardSpeed[market] = newSupplySpeed;
        borrowRewardSpeed[market] = newBorrowSpeed;

        emit RewardSpeedUpdated(market, newSupplySpeed, newBorrowSpeed);
    }

    function distributeSupplierReward(address market, address supplier) public {
        require(market != address(0), "Invalid market");
        require(factory.isMarket(market), "Market not supported");
        require(supplier != address(0), "Invalid supplier");

        // 1) Update global supply index for this market
        updateSupplyIndex(market);

        RewardState storage state = supplyState[market];
        uint256 globalIndex = state.index; // WAD

        // 2) Read user's personal index (checkpoint)
        uint256 userIndex = supplierIndex[market][supplier];

        // If first time, initialize user's index to current globalIndex (so no retroactive rewards)
        if (userIndex == 0) {
            supplierIndex[market][supplier] = globalIndex;
            return;
        }

        // 3) Delta index
        uint256 deltaIndex = globalIndex - userIndex;
        if (deltaIndex == 0) {
            supplierIndex[market][supplier] = globalIndex;
            return;
        }

        // 4) Supplier balance in this market = lToken balance (matches lToken.totalSupply() denominator)
        address lTokenAddr = ILendingMarketView(market).lToken();
        uint256 supplierBalance = LendingToken(lTokenAddr).balanceOf(supplier);

        // 5) Accrue rewards: balance * deltaIndex
        uint256 accrued = (supplierBalance * deltaIndex) / WAD;

        if (accrued > 0) {
            supplierRewards[market][supplier] += accrued;
            emit RewardsAccrued(supplier, market, accrued);
        }

        // 6) Update user's index checkpoint
        supplierIndex[market][supplier] = globalIndex;
    }

    function distributeBorrowerReward(address market, address borrower) public {
        require(market != address(0), "Invalid market");
        require(factory.isMarket(market), "Market not supported");
        require(borrower != address(0), "Invalid borrower");

        // 1) Update global supply index for this market
        updateBorrowIndex(market);

        RewardState storage state = borrowState[market];
        uint256 globalIndex = state.index; // WAD

        // 2) Read user's personal index (checkpoint)
        uint256 userIndex = borrowerIndex[market][borrower];
        // If first time, initialize user's index to current globalIndex (so no retroactive rewards)
        if (userIndex == 0) {
            borrowerIndex[market][borrower] = globalIndex;
            return;
        }

        // 3) Delta index
        uint256 deltaIndex = globalIndex - userIndex;
        if (deltaIndex == 0) {
            borrowerIndex[market][borrower] = globalIndex;
            return;
        }

        // 4) Borrower balance in this market = borrow balance (underlying), matches totalBorrows() denominator
        uint256 borrowerBalance = LendingMarket(market).borrowBalanceStored(borrower);

        // 5) Accrue rewards: balance * deltaIndex
        uint256 accrued = (borrowerBalance * deltaIndex) / WAD;

        if (accrued > 0) {
            borrowerRewards[market][borrower] += accrued;
            emit RewardsAccrued(borrower, market, accrued);
        }

        // 6) Update user's index checkpoint
        borrowerIndex[market][borrower] = globalIndex;
    }

    function claimRewards(address holder) external {
        require(holder != address(0), "Invalid holder");
        
        address[] memory assets = factory.getAssetsIn(holder);

        uint256 totalToMint = 0;

        for (uint256 i = 0; i < assets.length; i++) {
            address market = assets[i];
            if(!factory.isMarket(market)) continue;

            //Actualiza y acumula rewards del holder en este market
            distributeSupplierReward(market, holder);
            distributeBorrowerReward(market, holder);

            uint256 sup = supplierRewards[market][holder];
            uint256 bor = borrowerRewards[market][holder];
            
            if(sup > 0) {
                supplierRewards[market][holder] = 0;
                totalToMint += sup;
            }
            
            if(bor > 0) {
                borrowerRewards[market][holder] = 0;
                totalToMint += bor;
            }
        }

        require(totalToMint > 0, "No rewards to claim");

        governanceToken.mint(holder, totalToMint);

        emit RewardsClaimed(holder, totalToMint);
    }

    function _pendingSupplyIndex(address market) internal view returns (uint256) {
        RewardState memory state = supplyState[market];

        // si nunca se inicializó, asumimos base WAD
        uint256 idx = (state.index == 0) ? WAD : state.index;
        uint256 last = state.lastBlockUpdated;

        if (last == 0 || block.number == last) return idx;

        uint256 speed = supplyRewardSpeed[market];
        if (speed == 0) return idx;

        address lTokenAddr = ILendingMarketView(market).lToken();
        uint256 lSupply = LendingToken(lTokenAddr).totalSupply();
        if (lSupply == 0) return idx;

        uint256 deltaBlocks = block.number - last;
        uint256 rewardsAccrued = deltaBlocks * speed;
        uint256 indexDelta = (rewardsAccrued * WAD) / lSupply;

        return idx + indexDelta;
    }

    function _pendingBorrowIndex(address market) internal view returns (uint256) {
        RewardState memory state = borrowState[market];

        uint256 idx = (state.index == 0) ? WAD : state.index;
        uint256 last = state.lastBlockUpdated;

        if (last == 0 || block.number == last) return idx;

        uint256 speed = borrowRewardSpeed[market];
        if (speed == 0) return idx;

        uint256 borrows = ILendingMarketView(market).totalBorrows();
        if (borrows == 0) return idx;

        uint256 deltaBlocks = block.number - last;
        uint256 rewardsAccrued = deltaBlocks * speed;
        uint256 indexDelta = (rewardsAccrued * WAD) / borrows;

        return idx + indexDelta;
    }

    function getUnclaimedRewards(address holder) external view returns (uint256) {
        require(holder != address(0), "Invalid holder");

        address[] memory assets = factory.getAssetsIn(holder);
        uint256 total = 0;

        for (uint256 i = 0; i < assets.length; i++) {
            address market = assets[i];
            if (!factory.isMarket(market)) continue;

            // 1) lo ya acumulado en storage
            total += supplierRewards[market][holder];
            total += borrowerRewards[market][holder];

            // 2) añadir lo pendiente (simulado)
            // ---- Supply ----
            uint256 globalSup = _pendingSupplyIndex(market);
            uint256 userSup = supplierIndex[market][holder];
            if (userSup != 0 && globalSup > userSup) {
                uint256 delta = globalSup - userSup;
                address lTokenAddr = ILendingMarketView(market).lToken();
                uint256 bal = LendingToken(lTokenAddr).balanceOf(holder);
                total += (bal * delta) / WAD;
            }

            // ---- Borrow ----
            uint256 globalBor = _pendingBorrowIndex(market);
            uint256 userBor = borrowerIndex[market][holder];
            if (userBor != 0 && globalBor > userBor) {
                uint256 delta = globalBor - userBor;
                uint256 borBal = LendingMarket(market).borrowBalanceStored(holder);
                total += (borBal * delta) / WAD;
            }
        }

        return total;
    }
}