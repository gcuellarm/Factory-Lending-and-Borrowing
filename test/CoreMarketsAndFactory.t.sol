// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/core/LendingMarketFactory.sol";
import "../src/core/LendingMarket.sol";
import "../src/core/LendingToken.sol";
import "../src/oracles/PriceOracle.sol";
import "../src/models/InterestRateModel.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./mocks/MockERC20.sol";
// import "./mocks/RevertingRewardsDistributor.sol"; // TODO: Create this mock if needed

contract CoreMarketsAndFactoryTest is Test {
    // actors
    address owner = address(this);
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address liq   = address(0x11111d);

    // tokens
    MockERC20 weth;
    MockERC20 usdc; // 6
    MockERC20 dai;  // 18

    // protocol
    PriceOracle oracle;
    InterestRateModel irm;
    LendingMarket marketImpl;
    LendingMarketFactory factory;

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

        irm = new InterestRateModel(
            0.02e18,
            0.2e18,
            1.0e18,
            0.8e18
        );

        marketImpl = new LendingMarket();
        factory = new LendingMarketFactory(address(oracle), address(marketImpl));

        // create markets
        marketUSDC = factory.createMarket(
            address(usdc),
            8000, // 80% collateral
            1000, // 10% reserves
            address(irm),
            "lUSDC",
            "lUSDC"
        );

        marketDAI = factory.createMarket(
            address(dai),
            8000,
            1000,
            address(irm),
            "lDAI",
            "lDAI"
        );

        factory.listMarket(address(usdc));
        factory.listMarket(address(dai));

        // fund actors
        usdc.mint(alice, 1_000_000e6);
        dai.mint(alice, 1_000_000e18);

        usdc.mint(bob, 1_000_000e6);
        dai.mint(bob, 1_000_000e18);

        usdc.mint(liq, 1_000_000e6);
        dai.mint(liq, 1_000_000e18);

        // approvals
        vm.prank(alice);
        usdc.approve(marketUSDC, type(uint256).max);
        vm.prank(alice);
        dai.approve(marketDAI, type(uint256).max);

        vm.prank(bob);
        usdc.approve(marketUSDC, type(uint256).max);
        vm.prank(bob);
        dai.approve(marketDAI, type(uint256).max);

        vm.prank(liq);
        usdc.approve(marketUSDC, type(uint256).max);
        vm.prank(liq);
        dai.approve(marketDAI, type(uint256).max);
    }

    function _enter2(address who) internal {
        address[] memory mkts = new address[](2);
        mkts[0] = marketUSDC;
        mkts[1] = marketDAI;
        vm.prank(who);
        factory.enterMarkets(mkts);
    }

    // ------------------- LendingToken basics -------------------

    function testLToken_setMarket_onlyOnce() external {
        LendingToken l = LendingMarket(marketUSDC).lToken();

        // owner del lToken es la factory (porque lo deployó)
        vm.prank(address(factory));
        vm.expectRevert(bytes("Market already set"));
        l.setMarket(address(123));
    }

    function testLToken_mintBurn_onlyMarket() external {
        LendingToken l = LendingMarket(marketUSDC).lToken();

        vm.expectRevert(bytes("Only market can call this function"));
        l.mint(alice, 1);

        vm.expectRevert(bytes("Only market can call this function"));
        l.burn(alice, 1);
    }

    function testLToken_underlying_and_balanceOfUnderlying() external {
        LendingMarket m = LendingMarket(marketUSDC);
        LendingToken l = m.lToken();

        assertEq(l.underlying(), address(usdc));

        // deposit and check balanceOfUnderlying
        _enter2(alice);
        vm.prank(alice);
        m.deposit(1000e6);

        uint256 underlyingBal = l.balanceOfUnderlying(alice);
        // should be ~ deposit (exchangeRate starts at 1e18)
        assertApproxEqAbs(underlyingBal, 1000e6, 2);
    }

    // ------------------- LendingMarket init guards -------------------

    function testMarket_initializedByFactory_sanity() external view {
        LendingMarket m = LendingMarket(marketUSDC);

        // El market debe estar marcado como inicializado
        assertTrue(m.initialized());

        // Los índices iniciales deben ser WAD
        assertEq(m.borrowIndex(), 1e18);
        assertEq(m.supplyIndex(), 1e18);

        // Debe apuntar al underlying correcto
        assertEq(m.underlying(), address(usdc));

        // Owner debe ser la factory (porque initialize transfiere ownership)
        assertEq(m.owner(), address(factory));

        // lToken y factory deben estar seteados
        assertEq(address(m.lToken()), address(LendingMarket(marketUSDC).lToken()));
        assertEq(m.factory(), address(factory));
    }

    // ------------------- Deposit/Withdraw -------------------

    function testDeposit_mintsLtokens_andUpdatesSupply() external {
        LendingMarket m = LendingMarket(marketUSDC);
        LendingToken l = m.lToken();

        _enter2(alice);

        vm.prank(alice);
        uint256 minted = m.deposit(1000e6);

        assertGt(minted, 0);
        assertEq(l.balanceOf(alice), minted);

        (uint256 supplied,,,) = _user(m, alice);
        assertEq(supplied, 1000e6);
    }

    function testWithdraw_revertsIfWouldBecomeUndercollateralized() external {
        // Alice supplies USDC, borrows DAI, then tries to withdraw too much collateral
        LendingMarket mUSDC = LendingMarket(marketUSDC);
        LendingMarket mDAI  = LendingMarket(marketDAI);

        _enter2(alice);

        vm.prank(alice);
        mUSDC.deposit(1000e6);

        // provide DAI liquidity from bob
        _enter2(bob);
        vm.prank(bob);
        mDAI.deposit(10_000e18);

        // borrow some DAI
        vm.prank(alice);
        mDAI.borrow(700e18); // collateral 1000 * 0.8 = 800 => ok

        // attempt withdraw most collateral
        uint256 lBal = mUSDC.lToken().balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(bytes("Would become undercollateralized"));
        mUSDC.withdraw(lBal); // withdrawing all breaks ratio
    }

    function testWithdraw_ok_whenSafe() external {
        LendingMarket m = LendingMarket(marketUSDC);
        _enter2(alice);

        vm.prank(alice);
        m.deposit(1000e6);

        uint256 lBal = m.lToken().balanceOf(alice);

        vm.prank(alice);
        uint256 out = m.withdraw(lBal / 2);

        assertGt(out, 0);
    }

    // ------------------- Borrow/Repay -------------------

    function testBorrow_revertsIfInsufficientCash() external {
        LendingMarket m = LendingMarket(marketDAI);
        _enter2(alice);

        // no liquidity in marketDAI => borrow fails
        vm.prank(alice);
        vm.expectRevert(bytes("Insufficient cash"));
        m.borrow(1e18);
    }

    function testBorrow_andRepay_flow() external {
        LendingMarket mUSDC = LendingMarket(marketUSDC);
        LendingMarket mDAI  = LendingMarket(marketDAI);

        _enter2(alice);
        _enter2(bob);

        // Bob provides DAI cash
        vm.prank(bob);
        mDAI.deposit(10_000e18);

        // Alice supplies USDC collateral
        vm.prank(alice);
        mUSDC.deposit(1000e6);

        // Alice borrows DAI
        vm.prank(alice);
        mDAI.borrow(500e18);

        assertEq(mDAI.borrowBalanceStored(alice), 500e18);

        // repay
        vm.prank(alice);
        dai.approve(marketDAI, type(uint256).max);

        vm.prank(alice);
        mDAI.repay(200e18);
        assertEq(mDAI.borrowBalanceStored(alice), 300e18);
    }

    function testBorrowBalanceCurrent_accruesInterest() external {
        LendingMarket mUSDC = LendingMarket(marketUSDC);
        LendingMarket mDAI  = LendingMarket(marketDAI);
        _enter2(alice);
        _enter2(bob);

        vm.prank(bob);
        mDAI.deposit(10_000e18);

        vm.prank(alice);
        mUSDC.deposit(1000e6);

        vm.prank(alice);
        mDAI.borrow(500e18);

        uint256 stored = mDAI.borrowBalanceStored(alice);
        assertEq(stored, 500e18);

        // advance blocks and accrue
        vm.roll(block.number + 100);

        uint256 current = mDAI.borrowBalanceCurrent(alice);
        assertGt(current, stored);
    }

    function testSupplyBalanceCurrent_accruesInterestOnMarket() external {
        LendingMarket m = LendingMarket(marketUSDC);
        _enter2(alice);
        vm.prank(alice);
        m.deposit(1000e6);

        vm.roll(block.number + 100);
        uint256 cur = m.supplyBalanceCurrent(alice);
        // supplyIndex grows, but your suppliedAmount is also being “capitalized” inside _accrueUser
        // Here we just assert it returns >0.
        assertGt(cur, 0);
    }

    // ------------------- Factory enter/exit -------------------

    function testEnterMarkets_errorsForUnsupported() external {
        address[] memory mkts = new address[](1);
        mkts[0] = address(0x1234567890123456789012345678901234567890);

        vm.prank(alice);
        uint256[] memory res = factory.enterMarkets(mkts);

        assertEq(res.length, 1);
        assertEq(res[0], 1);
    }

    function testExitMarket_revertsIfOutstandingBorrow() external {
        LendingMarket mUSDC = LendingMarket(marketUSDC);
        LendingMarket mDAI  = LendingMarket(marketDAI);
        _enter2(alice);
        _enter2(bob);

        vm.prank(bob);
        mDAI.deposit(10_000e18);

        vm.prank(alice);
        mUSDC.deposit(1000e6);

        vm.prank(alice);
        mDAI.borrow(100e18);

        vm.prank(alice);
        vm.expectRevert(bytes("Outstanding borrow"));
        factory.exitMarket(marketDAI);
    }

    function testExitMarket_ok_whenNoBorrow() external {
        _enter2(alice);
        vm.prank(alice);
        uint256 code = factory.exitMarket(marketUSDC);
        assertEq(code, 0);
    }

    // ------------------- Liquidation (cross-market) -------------------

    function testLiquidation_flow_crossMarket() external {
        LendingMarket mUSDC = LendingMarket(marketUSDC);
        LendingMarket mDAI  = LendingMarket(marketDAI);

        _enter2(alice);
        _enter2(bob);
        _enter2(liq);

        // Provide DAI liquidity
        vm.prank(bob);
        mDAI.deposit(10_000e18);

        // Alice supplies USDC collateral
        vm.prank(alice);
        mUSDC.deposit(1000e6);

        // Alice borrows DAI (close to limit)
        vm.prank(alice);
        mDAI.borrow(790e18); // collateral = 800 => slightly safe

        // Price of USDC drops to 0.8
        oracle.setPrice(address(usdc), 0.8e8);

        (, uint256 shortfall) = factory.getAccountLiquidity(alice);
        assertGt(shortfall, 0);

        // Liquidator repays within closeFactor=50% => max ~395
        uint256 repayAmt = 300e18;

        // approve DAI from liq
        vm.prank(liq);
        dai.approve(marketDAI, type(uint256).max);

        uint256 liqLBefore = mUSDC.lToken().balanceOf(liq);
        uint256 aliceLBefore = mUSDC.lToken().balanceOf(alice);

        vm.prank(liq);
        mDAI.liquidateBorrow(alice, repayAmt, marketUSDC);

        uint256 liqLAfter = mUSDC.lToken().balanceOf(liq);
        uint256 aliceLAfter = mUSDC.lToken().balanceOf(alice);

        assertGt(liqLAfter, liqLBefore);
        assertLt(aliceLAfter, aliceLBefore);
    }

    function testLiquidation_revertsIfNotAllowed() external {
        LendingMarket mDAI = LendingMarket(marketDAI);

        vm.prank(liq);
        vm.expectRevert(bytes("Liquidation not allowed"));
        mDAI.liquidateBorrow(alice, 1, marketUSDC);
    }

    function testSeize_revertsIfCallerNotMarket() external {
        LendingMarket mUSDC = LendingMarket(marketUSDC);

        vm.prank(alice);
        vm.expectRevert(bytes("Caller not market"));
        mUSDC.seize(liq, alice, 1);
    }

    // ------------------- Rewards try/catch behavior -------------------

    // TODO: Create RevertingRewardsDistributor mock to test this
    /*function testRewards_tryCatch_doesNotBreakDeposit() external {
        RevertingRewardsDistributor bad = new RevertingRewardsDistributor();
        factory.setRewardsDistributor(address(bad));

        LendingMarket m = LendingMarket(marketUSDC);
        _enter2(alice);

        vm.prank(alice);
        // should not revert even though RD reverts
        m.deposit(1000e6);
    }*/

    function testReserves_addReduce_onlyOwner() external {
        LendingMarket m = LendingMarket(marketUSDC);

        // non-owner
        vm.prank(alice);
        vm.expectRevert();
        m.addReserves(1);

        // owner is factory
        usdc.mint(address(factory), 100e6);
        vm.prank(address(factory));
        usdc.approve(marketUSDC, type(uint256).max);

        vm.prank(address(factory));
        m.addReserves(10e6);

        vm.prank(address(factory));
        m.reduceReserves(5e6);
    }

    function testPause_unpause_onlyOwner() external {
        LendingMarket m = LendingMarket(marketUSDC);

        vm.prank(alice);
        vm.expectRevert();
        m.pause();

        vm.prank(address(factory));
        m.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        m.deposit(1);

        vm.prank(address(factory));
        m.unpause();
    }

    // ------------------- helpers -------------------

    function _user(LendingMarket m, address a)
        internal
        view
        returns (uint256 supplied, uint256 borrowed, uint256 sIdx, uint256 bIdx)
    {
        (supplied, borrowed, sIdx, bIdx) = m.users(a);
    }
}