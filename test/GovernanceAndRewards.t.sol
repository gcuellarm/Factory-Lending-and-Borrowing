// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/Governance/GovernanceToken.sol";
import "../src/Governance/RewardsDistributor.sol";

import "../src/core/LendingMarketFactory.sol";
import "../src/core/LendingMarket.sol";
import "../src/core/LendingToken.sol";
import "../src/oracles/PriceOracle.sol";
import "../src/models/InterestRateModel.sol";

import "./mocks/MockERC20.sol";

contract GovernanceAndRewardsTest is Test {
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    MockERC20 weth;
    MockERC20 usdc;
    MockERC20 dai;

    PriceOracle oracle;
    InterestRateModel irm;
    LendingMarket impl;
    LendingMarketFactory factory;

    GovernanceToken gov;
    RewardsDistributor rd;

    address marketUSDC;
    address marketDAI;

    function setUp() external {
        weth = new MockERC20("WETH", "WETH", 18);
        usdc = new MockERC20("USDC", "USDC", 6);
        dai  = new MockERC20("DAI", "DAI", 18);

        oracle = new PriceOracle(address(weth));
        oracle.setPrice(address(weth), 3000e8);
        oracle.setPrice(address(usdc), 1e8);
        oracle.setPrice(address(dai), 1e8);

        irm = new InterestRateModel(0.02e18, 0.2e18, 1e18, 0.8e18);
        impl = new LendingMarket();
        factory = new LendingMarketFactory(address(oracle), address(impl));

        marketUSDC = factory.createMarket(address(usdc), 8000, 1000, address(irm), "lUSDC", "lUSDC");
        marketDAI  = factory.createMarket(address(dai), 8000, 1000, address(irm), "lDAI", "lDAI");

        factory.listMarket(address(usdc));
        factory.listMarket(address(dai));

        // deploy governance + RD
        gov = new GovernanceToken();
        rd = new RewardsDistributor(address(gov), address(factory));

        // RD must be owner to mint rewards
        gov.transferOwnership(address(rd));

        // wire RD into factory
        factory.setRewardsDistributor(address(rd));

        // fund users
        usdc.mint(alice, 1_000_000e6);
        dai.mint(alice, 1_000_000e18);

        usdc.mint(bob, 1_000_000e6);
        dai.mint(bob, 1_000_000e18);

        vm.prank(alice);
        usdc.approve(marketUSDC, type(uint256).max);
        vm.prank(alice);
        dai.approve(marketDAI, type(uint256).max);

        vm.prank(bob);
        usdc.approve(marketUSDC, type(uint256).max);
        vm.prank(bob);
        dai.approve(marketDAI, type(uint256).max);

        _enter(alice);
        _enter(bob);
    }

    function _enter(address who) internal {
        address[] memory mkts = new address[](2);
        mkts[0] = marketUSDC;
        mkts[1] = marketDAI;
        vm.prank(who);
        factory.enterMarkets(mkts);
    }

    function testGovernanceToken_initialSupplyMinted() external view {
        assertEq(gov.balanceOf(address(this)), 1_000_000e18);
    }

    function testGovernanceToken_onlyOwnerMint() external {
        vm.prank(alice);
        vm.expectRevert();
        gov.mint(alice, 1);

        // owner is RD (after transferOwnership)
        vm.prank(address(rd));
        gov.mint(alice, 10e18);
        assertEq(gov.balanceOf(alice), 10e18);
    }

    function testSetRewardSpeed_updatesAndEmits() external {
        rd.setRewardSpeed(marketUSDC, 1e18, 2e18);
        assertEq(rd.supplyRewardSpeed(marketUSDC), 1e18);
        assertEq(rd.borrowRewardSpeed(marketUSDC), 2e18);
    }

    function testUpdateIndexes_initPaths() external {
        // first call initializes lastBlockUpdated and index=WAD
        rd.updateSupplyIndex(marketUSDC);
        rd.updateBorrowIndex(marketUSDC);

        (uint256 idxS, uint256 bS) = _stateSupply(marketUSDC);
        (uint256 idxB, uint256 bB) = _stateBorrow(marketUSDC);

        assertEq(idxS, 1e18);
        assertEq(bS, block.number);

        assertEq(idxB, 1e18);
        assertEq(bB, block.number);
    }

    function testDistributeSupplierReward_accrues() external {
        rd.setRewardSpeed(marketUSDC, 10e18, 0);

        // supply
        vm.prank(alice);
        LendingMarket(marketUSDC).deposit(1000e6);

        // first distribution sets user index only
        rd.distributeSupplierReward(marketUSDC, alice);
        assertEq(rd.supplierIndex(marketUSDC, alice), 1e18);

        // advance blocks
        vm.roll(block.number + 100);

        // trigger distribution again via market deposit (it calls RD)
        vm.prank(alice);
        LendingMarket(marketUSDC).deposit(1e6);

        uint256 accrued = rd.supplierRewards(marketUSDC, alice);
        assertGt(accrued, 0);
    }

    function testDistributeBorrowerReward_accrues() external {
        rd.setRewardSpeed(marketDAI, 0, 5e18);

        // provide DAI cash
        vm.prank(bob);
        LendingMarket(marketDAI).deposit(10_000e18);

        // alice supplies collateral
        vm.prank(alice);
        LendingMarket(marketUSDC).deposit(1000e6);

        // borrow some DAI
        vm.prank(alice);
        LendingMarket(marketDAI).borrow(500e18);

        // first distribution sets index
        rd.distributeBorrowerReward(marketDAI, alice);
        assertEq(rd.borrowerIndex(marketDAI, alice), 1e18);

        vm.roll(block.number + 50);

        // another borrow triggers RD call
        vm.prank(alice);
        LendingMarket(marketDAI).borrow(10e18);

        uint256 accrued = rd.borrowerRewards(marketDAI, alice);
        assertGt(accrued, 0);
    }

    function testGetUnclaimedRewards_andClaimRewards() external {
        rd.setRewardSpeed(marketUSDC, 10e18, 0);
        rd.setRewardSpeed(marketDAI, 0, 5e18);

        // provide DAI cash
        vm.prank(bob);
        LendingMarket(marketDAI).deposit(10_000e18);

        // alice supplies + borrows
        vm.prank(alice);
        LendingMarket(marketUSDC).deposit(1000e6);

        vm.prank(alice);
        LendingMarket(marketDAI).borrow(500e18);

        // advance blocks to accumulate pending
        vm.roll(block.number + 200);

        uint256 pending = rd.getUnclaimedRewards(alice);
        assertGt(pending, 0);

        rd.claimRewards(alice);

        assertGt(gov.balanceOf(alice), 0);

        // after claim, should be ~0 pending (may still have tiny pending if new blocks mined)
        uint256 afterPending = rd.getUnclaimedRewards(alice);
        assertLt(afterPending, pending);
    }

    function testClaimRewards_revertsIfNone() external {
        vm.expectRevert(bytes("No rewards to claim"));
        rd.claimRewards(alice);
    }

    function testUpdateIndex_requiresMarketSupported() external {
        vm.expectRevert(bytes("Market not supported"));
        rd.updateSupplyIndex(address(0x123));
    }

    // ----- helpers -----
    function _stateSupply(address m) internal view returns (uint256, uint256) {
        (uint256 idx, uint256 b) = rd.supplyState(m);
        return (idx, b);
    }

    function _stateBorrow(address m) internal view returns (uint256, uint256) {
        (uint256 idx, uint256 b) = rd.borrowState(m);
        return (idx, b);
    }
}