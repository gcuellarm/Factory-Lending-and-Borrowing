// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/oracles/PriceOracle.sol";
import "../src/models/InterestRateModel.sol";
import "test/mocks/MockERC20.sol";
import "test/mocks/MockAggregator.t.sol";

contract OracleAndIRMTest is Test {
    PriceOracle oracle;
    MockERC20 weth;
    MockERC20 usdc;
    MockAggregator agg;

    function setUp() external {
        weth = new MockERC20("WETH", "WETH", 18);
        usdc = new MockERC20("USDC", "USDC", 6);
        oracle = new PriceOracle(address(weth));

        // set manual prices
        oracle.setPrice(address(weth), 3000e8); // 3000 USD
        oracle.setPrice(address(usdc), 1e8);    // 1 USD

        agg = new MockAggregator();
    }

    function testOracle_setPrice_revertsOnZero() external {
        vm.expectRevert(bytes("Price must be greater than 0"));
        oracle.setPrice(address(usdc), 0);
    }

    function testOracle_setPrice_revertsOnZeroToken() external {
        vm.expectRevert(bytes("Invalid token address"));
        oracle.setPrice(address(0), 1e8);
    }

    function testOracle_manualPrice_getPrice_ok() external {
        uint256 p = oracle.getPrice(address(usdc));
        assertEq(p, 1e8);
    }

    function testOracle_setPriceFeed_usesChainlink() external {
        agg.setAnswer(123e8);
        oracle.setPriceFeed(address(usdc), address(agg));

        uint256 p = oracle.getPrice(address(usdc));
        assertEq(p, 123e8);
    }

    function testOracle_chainlinkReverts_fallbackManual() external {
        agg.setRevert(true);
        oracle.setPriceFeed(address(usdc), address(agg));

        // manual fallback exists (1e8)
        uint256 p = oracle.getPrice(address(usdc));
        assertEq(p, 1e8);
    }

    function testOracle_chainlinkReturnsInvalid_reverts() external {
        agg.setAnswer(-1);
        oracle.setPriceFeed(address(usdc), address(agg));
        vm.expectRevert(bytes("Invalid price from Chainlink"));
        oracle.getPrice(address(usdc));
    }

    function testOracle_chainlinkReverts_noFallback_reverts() external {
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        agg.setRevert(true);
        oracle.setPriceFeed(address(dai), address(agg));

        vm.expectRevert(bytes("No fallback price available"));
        oracle.getPrice(address(dai));
    }

    function testOracle_getPriceInEth_ok() external view {
        uint256 tokenPrice = 1e8;
        uint256 ethPrice = 3000e8;

        uint256 expected = (tokenPrice * 1e18) / ethPrice;

        uint256 pEth = oracle.getPriceInEth(address(usdc));
        assertEq(pEth, expected);
    }

    function testOracle_batchGetPrices_ok() external view {
        address[] memory t = new address[](2);
        t[0] = address(weth);
        t[1] = address(usdc);

        uint256[] memory ps = oracle.batchGetPrices(t);
        assertEq(ps.length, 2);
        assertEq(ps[0], 3000e8);
        assertEq(ps[1], 1e8);
    }

    // ---------------- IRM ----------------

    function testIRM_utilizationRate_basic() external {
        InterestRateModel irm = new InterestRateModel(
            0.02e18,
            0.2e18,
            1.0e18,
            0.8e18
        );

        assertEq(irm.utilizationRate(100, 0, 0), 0);

        uint256 util = irm.utilizationRate(100e18, 50e18, 0);

        uint256 one = 1e18;
        uint256 expected = one / 3;

        assertEq(util, expected);
    }

    function testIRM_utilizationRate_reservesTooHigh_returns0() external {
        InterestRateModel irm = new InterestRateModel(0, 0, 0, 0.8e18);
        // cash+borrows <= reserves => 0
        assertEq(irm.utilizationRate(10, 10, 100), 0);
    }

    function testIRM_borrowRate_belowKink() external {
        InterestRateModel irm = new InterestRateModel(0.02e18, 0.2e18, 1e18, 0.8e18);
        uint256 util = 0.5e18;
        // borrowRate = base + util*multiplier
        // = 0.02 + 0.5*0.2 = 0.12
        uint256 r = irm.getBorrowRate(100e18, 100e18, 100e18); // util depends; we just validate monotonic by direct util? no direct
        // better: choose cash/borrows/reserves that produce util=0.5:
        // util = borrows/(cash+borrows) => set cash=borrows => 0.5
        r = irm.getBorrowRate(100e18, 100e18, 0);
        assertEq(r, 0.02e18 + (util * 0.2e18) / 1e18);
    }

    function testIRM_borrowRate_aboveKink() external {
        InterestRateModel irm = new InterestRateModel(0.02e18, 0.2e18, 1e18, 0.8e18);
        // util=0.9 => cash ~ 11.111..., borrows=100 => util=100/(111.111)=0.9
        uint256 cash = 11111111111111111111; // ~11.111e18
        uint256 borrows = 100e18;

        uint256 r = irm.getBorrowRate(cash, borrows, 0);

        // expected:
        // normalRate = base + kink*multiplier = 0.02 + 0.8*0.2 = 0.18
        // excess = 0.1 * jump(1.0) = 0.1
        // total = 0.28
        // allow small rounding
        uint256 expectedRate = 0.28e18;
        uint256 delta = 5e14;
        assertLe(r, expectedRate + delta);
        assertGe(r, expectedRate - delta);
    }

    function testIRM_supplyRate_reserveFactor_applied() external {
        InterestRateModel irm = new InterestRateModel(0.02e18, 0.2e18, 1e18, 0.8e18);
        // util=0.5 with cash=borrows
        uint256 cash = 100e18;
        uint256 borrows = 100e18;

        uint256 borrowRate = irm.getBorrowRate(cash, borrows, 0);
        uint256 util = irm.utilizationRate(cash, borrows, 0);

        uint256 supplyRate = irm.getSupplyRate(cash, borrows, 0, 1000); // 10%
        uint256 rateToPool = (borrowRate * util) / 1e18;
        uint256 expected = (rateToPool * (10000 - 1000)) / 10000;

        assertEq(supplyRate, expected);
    }

    function testIRM_supplyRate_revertsOnBadReserveFactor() external {
        InterestRateModel irm = new InterestRateModel(0, 0, 0, 0.8e18);
        vm.expectRevert(bytes("reserveFactor>100%"));
        irm.getSupplyRate(1, 1, 0, 10001);
    }

    function testIRM_perBlock_helpers() external {
        InterestRateModel irm = new InterestRateModel(0.02e18, 0.2e18, 1e18, 0.8e18);

        uint256 br = irm.getBorrowRate(100e18, 100e18, 0);
        uint256 brpb = irm.getBorrowRatePerBlock(100e18, 100e18, 0);
        assertEq(brpb, br / irm.BLOCKS_PER_YEAR());

        uint256 sr = irm.getSupplyRate(100e18, 100e18, 0, 0);
        uint256 srpb = irm.getSupplyRatePerBlock(100e18, 100e18, 0, 0);
        assertEq(srpb, sr / irm.BLOCKS_PER_YEAR());
    }
}