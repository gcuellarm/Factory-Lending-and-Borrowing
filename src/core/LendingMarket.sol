// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
    LendingMarket (Día 5) - Single-token market (tipo Compound)
    - Opción A (Factory + clones): constructor vacío + initialize()
    - lToken se despliega fuera (Factory) y se conecta aquí por initialize()
    - Intereses por índices globales (borrowIndex/supplyIndex)
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./LendingToken.sol";
import "../oracles/PriceOracle.sol";
import "../models/InterestRateModel.sol";

interface ILendingMarketFactoryLike {
    function getAccountLiquidity(address account) external view returns (uint256 liquidity, uint256 shortfall);

    // Día 7: liquidez hipotética (cross-market checks)
    function getHypotheticalAccountLiquidity(
        address account,
        address marketModify,
        uint256 redeemUnderlying,
        uint256 borrowUnderlying
    ) external view returns (uint256 liquidity, uint256 shortfall);

    function closeFactor() external view returns (uint256); // BPS

    function liquidateCalculateSeizeTokens(
        address marketBorrowed,
        address marketCollateral,
        uint256 repayAmount
    ) external view returns (uint256 seizeTokens);

    // Día 7: validaciones Comptroller-style (códigos de error)
    function liquidateBorrowAllowed(
        address marketBorrowed,
        address marketCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external view returns (uint256);

    function seizeAllowed(
        address marketCollateral,
        address marketBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external view returns (uint256);

    // Día 7: endurecer seize() -> solo markets válidos
    function isMarket(address market) external view returns (bool);

    // Dia 8
    function rewardsDistributor() external view returns (address);
}

interface ILendingMarketCollateralLike {
    function accrueInterest() external;
    function seize(address liquidator, address borrower, uint256 seizeTokens) external;
}

interface IRewardsDistributorLike {
    function distributeSupplierReward(address market, address supplier) external;
    function distributeBorrowerReward(address market, address borrower) external;
}

contract LendingMarket is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // -----------------------------
    // Constants
    // -----------------------------
    uint256 public constant WAD = 1e18;
    uint256 public constant BPS = 10_000;

    // Liquidation params (se usarán más en Factory D6/D7; aquí quedan declarados por coherencia)
    uint256 public constant LIQUIDATION_THRESHOLD_BPS = 8_000; // 80%
    uint256 public constant LIQUIDATION_PENALTY_BPS = 500;      // 5%

    // -----------------------------
    // Structs
    // -----------------------------
    struct User {
        uint256 suppliedAmount; // principal (sin intereses aplicados)
        uint256 borrowedAmount; // principal (sin intereses aplicados)
        uint256 supplyIndex;    // checkpoint del índice global (WAD)
        uint256 borrowIndex;    // checkpoint del índice global (WAD)
    }

    // -----------------------------
    // State
    // -----------------------------
    IERC20 public underlyingToken;              // set en initialize (NO immutable por clones)
    LendingToken public lToken;                 // set en initialize
    PriceOracle public priceOracle;             // set en initialize
    InterestRateModel public interestRateModel; // set en initialize
    address public factory;                     // set en initialize

    bool public initialized;

    // Protocol accounting (Compound-like)
    uint256 public totalBorrows;    // total outstanding borrows
    uint256 public totalReserves;   // reserves acumuladas
    uint256 public borrowIndex;     // índice global borrow (WAD, 1e18)
    uint256 public supplyIndex;     // índice global supply (WAD, 1e18)
    uint256 public accrualBlockNumber;

    // Params
    uint256 public reserveFactorBps;    // 0..10000
    uint256 public collateralFactorBps; // 0..10000 (lo usa principalmente Factory)

    mapping(address => User) public users;

    // -----------------------------
    // Events
    // -----------------------------
    event MarketInitialized(address indexed underlying, address indexed lToken, address indexed factory);
    event Deposit(address indexed user, uint256 underlyingAmount, uint256 lTokensMinted);
    event Withdraw(address indexed user, uint256 underlyingAmount, uint256 lTokensBurned);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Seize(address indexed liquidator, address indexed borrower, uint256 seizeTokens);
    event LiquidateBorrow(address indexed liquidator, address indexed borrower, address indexed marketCollateral, uint256 repayAmount, uint256 seizeTokens);
    event InterestAccrued(uint256 cashPrior, uint256 interestAccumulated, uint256 borrowIndex, uint256 totalBorrows);
    event ReservesAdded(uint256 amount, uint256 totalReserves);
    event ReservesReduced(uint256 amount, uint256 totalReserves);

    // Solo debería ser callable por OTROS markets del protocolo o por la Factory.
    // Para el Día 7, seize() se endurece y ya no usa onlyFactory (ver abajo).
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    // -----------------------------
    // Constructor (clones friendly)
    // -----------------------------
    constructor() Ownable(msg.sender) {}

    function _factory() internal view returns (ILendingMarketFactoryLike) {
        return ILendingMarketFactoryLike(factory);
    }

    // -----------------------------
    // Initializer (Opción A)
    // -----------------------------
    function initialize(
        address _underlyingToken,
        address _factoryAddr,
        address _oracle,
        address _interestRateModel,
        address _lToken,
        uint256 _collateralFactorBps,
        uint256 _reserveFactorBps
    ) external {
        require(!initialized, "Already initialized");
        initialized = true;

        require(_underlyingToken != address(0), "Invalid underlying");
        require(_factoryAddr != address(0), "Invalid factory");
        require(_oracle != address(0), "Invalid oracle");
        require(_interestRateModel != address(0), "Invalid IRM");
        require(_lToken != address(0), "Invalid lToken");

        require(_reserveFactorBps <= BPS, "reserveFactor too high");
        require(_collateralFactorBps <= BPS, "collateralFactor too high");

        underlyingToken = IERC20(_underlyingToken);
        factory = _factoryAddr;
        priceOracle = PriceOracle(_oracle);
        interestRateModel = InterestRateModel(_interestRateModel);
        lToken = LendingToken(_lToken);

        collateralFactorBps = _collateralFactorBps;
        reserveFactorBps = _reserveFactorBps;

        // init indices
        borrowIndex = WAD;
        supplyIndex = WAD;

        accrualBlockNumber = block.number;

        // Admin centralizado en la factory
        _transferOwnership(_factoryAddr);

        emit MarketInitialized(_underlyingToken, _lToken, _factoryAddr);
    }

    // -----------------------------
    // (1) underlying() helper
    // -----------------------------
    function underlying() external view returns (address) {
        return address(underlyingToken);
    }

    // -----------------------------
    // Views
    // -----------------------------
    function getCash() public view returns (uint256) {
        return underlyingToken.balanceOf(address(this));
    }

    /// @notice exchange rate (WAD) = (cash + borrows - reserves) / lTokenSupply
    function exchangeRateStored() public view returns (uint256) {
        uint256 lSupply = lToken.totalSupply();
        if (lSupply == 0) return WAD;

        uint256 cash = getCash();
        // totalUnderlying = cash + totalBorrows - totalReserves
        if (cash + totalBorrows <= totalReserves) return WAD; // defensive
        uint256 totalUnderlying = cash + totalBorrows - totalReserves;

        return (totalUnderlying * WAD) / lSupply;
    }

    // -----------------------------
    // (2) exchangeRateCurrent()
    // -----------------------------
    function exchangeRateCurrent() public returns (uint256) {
        accrueInterest();
        return exchangeRateStored();
    }

    // -----------------------------
    // Supply balance helpers (Día 7)
    // -----------------------------

    /// @notice Balance de supply usando SOLO storage (sin accrue)
    /// @dev Devuelve el underlying equivalente a lTokens usando exchangeRateStored()
    function supplyBalanceStored(address account) public view returns (uint256) {
        uint256 lBal = lToken.balanceOf(account);
        return (lBal * exchangeRateStored()) / WAD;
    }

    /// @notice Balance de supply "a fecha de ahora": fuerza accrueInterest()
    /// @dev Cambia estado (por el accrue global del market).
    function supplyBalanceCurrent(address account) external returns (uint256) {
        accrueInterest();
        return supplyBalanceStored(account);
    }

    // -----------------------------
    // Borrow balance helpers (Día 7)
    // -----------------------------

    /// @notice Balance de borrow usando SOLO storage (sin accrue)
    /// @dev Si el market NO ha hecho accrue recientemente, esto estará "stale".
    function borrowBalanceStored(address account) public view returns (uint256) {
        User storage u = users[account];

        uint256 principal = u.borrowedAmount;
        if (principal == 0) return 0;

        uint256 userIndex = u.borrowIndex;
        require(userIndex != 0, "Invalid user borrowIndex");

        return (principal * borrowIndex) / userIndex;
    }

    /// @notice Balance de borrow "a fecha de ahora": fuerza accrueInterest()
    /// @dev Cambia estado (por el accrue global del market).
    function borrowBalanceCurrent(address account) external returns (uint256) {
        accrueInterest();
        return borrowBalanceStored(account);
    }

    // -----------------------------
    // (3) getAccountSnapshot()
    // -----------------------------
    function getAccountSnapshot(address account)
        external
        view
        returns (uint256 lTokenBalance, uint256 borrowBalance, uint256 exchangeRate)
    {
        lTokenBalance = lToken.balanceOf(account);
        borrowBalance = borrowBalanceStored(account);
        exchangeRate = exchangeRateStored();
    }

    // -----------------------------
    // Core accrual
    // -----------------------------
    function accrueInterest() public {
        if (accrualBlockNumber == block.number) return;

        uint256 cashPrior = getCash();
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalReserves;
        uint256 borrowIndexPrior = borrowIndex;

        uint256 borrowRatePerBlock = interestRateModel.getBorrowRatePerBlock(
            cashPrior,
            borrowsPrior,
            reservesPrior
        );

        uint256 blockDelta = block.number - accrualBlockNumber;

        if (borrowsPrior == 0) {
            accrualBlockNumber = block.number;
            return;
        }

        uint256 interestAccumulated = (borrowsPrior * borrowRatePerBlock * blockDelta) / WAD;

        totalBorrows = borrowsPrior + interestAccumulated;

        uint256 reservesAdded = (interestAccumulated * reserveFactorBps) / BPS;
        totalReserves = reservesPrior + reservesAdded;

        uint256 simpleInterestFactor = (borrowRatePerBlock * blockDelta); // WAD
        borrowIndex = borrowIndexPrior + (borrowIndexPrior * simpleInterestFactor) / WAD;

        uint256 supplyRatePerBlock = interestRateModel.getSupplyRatePerBlock(
            cashPrior,
            borrowsPrior,
            reservesPrior,
            reserveFactorBps
        );
        uint256 supplyFactor = (supplyRatePerBlock * blockDelta); // WAD
        supplyIndex = supplyIndex + (supplyIndex * supplyFactor) / WAD;

        accrualBlockNumber = block.number;

        emit InterestAccrued(cashPrior, interestAccumulated, borrowIndex, totalBorrows);
    }

    // -----------------------------
    // User accrual (checkpoint indices)
    // -----------------------------
    function _accrueUser(address account) internal {
        User storage u = users[account];

        if (u.supplyIndex == 0) u.supplyIndex = supplyIndex;
        if (u.borrowIndex == 0) u.borrowIndex = borrowIndex;

        if (u.suppliedAmount > 0) {
            uint256 factorSupply = (supplyIndex * WAD) / u.supplyIndex;
            u.suppliedAmount = (u.suppliedAmount * factorSupply) / WAD;
        }
        u.supplyIndex = supplyIndex;

        if (u.borrowedAmount > 0) {
            uint256 factorBorrow = (borrowIndex * WAD) / u.borrowIndex;
            u.borrowedAmount = (u.borrowedAmount * factorBorrow) / WAD;
        }
        u.borrowIndex = borrowIndex;
    }

    // -----------------------------
    // Deposit / Withdraw
    // -----------------------------
    function deposit(uint256 amount) external nonReentrant whenNotPaused returns (uint256 lTokensMinted) {
        require(amount > 0, "Amount=0");

        accrueInterest();
        _accrueUser(msg.sender);

        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 rate = exchangeRateStored();
        lTokensMinted = (amount * WAD) / rate;

        users[msg.sender].suppliedAmount += amount;

        lToken.mint(msg.sender, lTokensMinted);

        address rd = _rewardsDistributor();
        if (rd != address(0)) {
            try IRewardsDistributorLike(rd).distributeSupplierReward(address(this), msg.sender) {} catch {}
        }

        emit Deposit(msg.sender, amount, lTokensMinted);
    }

    function withdraw(uint256 lTokenAmount) external nonReentrant whenNotPaused returns (uint256 underlyingAmount) {
        require(lTokenAmount > 0, "Amount=0");

        accrueInterest();
        _accrueUser(msg.sender);

        address rd = _rewardsDistributor();
        if (rd != address(0)) {
            try IRewardsDistributorLike(rd).distributeSupplierReward(address(this), msg.sender) {} catch {}
        }

        uint256 rate = exchangeRateStored();
        underlyingAmount = (lTokenAmount * rate) / WAD;

        // Día 7: no permitir retirar colateral si rompe ratio (validación cross-market en Factory)
        (, uint256 shortfall) = _factory().getHypotheticalAccountLiquidity(
            msg.sender,
            address(this),
            underlyingAmount,
            0
        );
        require(shortfall == 0, "Would become undercollateralized");

        require(users[msg.sender].suppliedAmount >= underlyingAmount, "Insufficient supply");
        users[msg.sender].suppliedAmount -= underlyingAmount;

        lToken.burn(msg.sender, lTokenAmount);
        underlyingToken.safeTransfer(msg.sender, underlyingAmount);

        emit Withdraw(msg.sender, underlyingAmount, lTokenAmount);
    }

    // -----------------------------
    // Borrow / Repay
    // -----------------------------
    function borrow(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount=0");

        accrueInterest();
        _accrueUser(msg.sender);

        require(getCash() >= amount, "Insufficient cash");

        // Día 7: collateral checks cross-market belong to Factory
        (, uint256 shortfall) = _factory().getHypotheticalAccountLiquidity(
            msg.sender,
            address(this),
            0,
            amount
        );
        require(shortfall == 0, "Insufficient collateral");

        users[msg.sender].borrowedAmount += amount;
        totalBorrows += amount;

        underlyingToken.safeTransfer(msg.sender, amount);

        address rd = _rewardsDistributor();
        if (rd != address(0)) {
            try IRewardsDistributorLike(rd).distributeBorrowerReward(address(this), msg.sender) {} catch {}
        }

        emit Borrow(msg.sender, amount);
    }

    function repay(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount=0");

        accrueInterest();
        _accrueUser(msg.sender);

        address rd = _rewardsDistributor();
        if (rd != address(0)) {
            try IRewardsDistributorLike(rd).distributeBorrowerReward(address(this), msg.sender) {} catch {}
        }

        User storage u = users[msg.sender];
        require(u.borrowedAmount >= amount, "Repay exceeds debt");

        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);

        u.borrowedAmount -= amount;
        totalBorrows -= amount;

        emit Repay(msg.sender, amount);
    }

    // -----------------------------
    // Reserves management (owner=factory)
    // -----------------------------
    function addReserves(uint256 amount) external nonReentrant onlyOwner {
        require(amount > 0, "Amount=0");
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        totalReserves += amount;
        emit ReservesAdded(amount, totalReserves);
    }

    function reduceReserves(uint256 amount) external nonReentrant onlyOwner {
        require(amount > 0, "Amount=0");
        require(getCash() >= amount, "Insufficient cash");
        require(totalReserves >= amount, "Insufficient reserves");

        totalReserves -= amount;
        underlyingToken.safeTransfer(msg.sender, amount);

        emit ReservesReduced(amount, totalReserves);
    }

    // -----------------------------
    // Admin
    // -----------------------------
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // -----------------------------
    // Liquidación cross-market (Día 7)
    // -----------------------------

    /// @notice Liquida deuda del borrower en ESTE market (marketBorrowed = address(this))
    /// y se queda con colateral en marketCollateral en forma de lTokens.
    function liquidateBorrow(address borrower, uint256 repayAmount, address marketCollateral) external nonReentrant whenNotPaused {
        require(borrower != address(0), "Invalid borrower");
        require(marketCollateral != address(0), "Invalid collateral market");
        require(marketCollateral != address(this), "Same market");
        require(repayAmount > 0, "Repay=0");

        // Validación Comptroller-style en Factory (código 0 = permitido)
        uint256 allowed = _factory().liquidateBorrowAllowed(
            address(this),
            marketCollateral,
            msg.sender,
            borrower,
            repayAmount
        );
        require(allowed == 0, "Liquidation not allowed");

        // 1) Actualizar intereses en ambos markets para no liquidar con números viejos
        accrueInterest();
        ILendingMarketCollateralLike(marketCollateral).accrueInterest();

        // Muy importante: capitalizar deuda del borrower en ESTE market antes de tocar principal
        _accrueUser(borrower);

        // 2) Cobrar repayAmount al liquidator y reducir deuda del borrower en ESTE market
        underlyingToken.safeTransferFrom(msg.sender, address(this), repayAmount);

        User storage u = users[borrower];
        require(u.borrowedAmount >= repayAmount, "Repay > debt");

        u.borrowedAmount -= repayAmount;
        totalBorrows -= repayAmount;

        // 3) Calcular cuántos lTokens del marketCollateral se deben seize
        uint256 seizeTokens = _factory().liquidateCalculateSeizeTokens(
            address(this),
            marketCollateral,
            repayAmount
        );
        require(seizeTokens > 0, "Seize=0");

        // 4) Ejecutar seize en el marketCollateral (mueve lTokens borrower -> liquidator)
        ILendingMarketCollateralLike(marketCollateral).seize(msg.sender, borrower, seizeTokens);

        emit LiquidateBorrow(msg.sender, borrower, marketCollateral, repayAmount, seizeTokens);
    }

    /// @notice Transferir lTokens del borrower al liquidator durante liquidación
    /// @dev Día 7: Solo llamable por otros markets del protocolo (cross-market liquidation).
    function seize(address liquidator, address borrower, uint256 seizeTokens) external nonReentrant {
        // Validación de caller: debe ser un market del protocolo
        require(_factory().isMarket(msg.sender), "Caller not market");

        // Validación Comptroller-style (código 0 = permitido)
        uint256 allowed = _factory().seizeAllowed(
            address(this),   // marketCollateral = este market
            msg.sender,      // marketBorrowed = caller
            liquidator,
            borrower,
            seizeTokens
        );
        require(allowed == 0, "Seize not allowed");

        require(liquidator != address(0) && borrower != address(0), "Invalid addr");
        require(seizeTokens > 0, "Seize=0");

        // Mover lTokens del borrower al liquidator sin approvals (burn+mint)
        lToken.burn(borrower, seizeTokens);
        lToken.mint(liquidator, seizeTokens);

        emit Seize(liquidator, borrower, seizeTokens);
    }

    function _rewardsDistributor() internal view returns (address) {
        return ILendingMarketFactoryLike(factory).rewardsDistributor();
    }
}