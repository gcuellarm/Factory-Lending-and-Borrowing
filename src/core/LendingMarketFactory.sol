//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./LendingMarket.sol";
import "./LendingToken.sol";
import "../oracles/PriceOracle.sol";

contract LendingMarketFactory is Ownable {
    using Clones for address;

    // Constants
    uint256 public constant BPS = 10_000; // 100% in basis points

    // Structs
    struct MarketConfig {
        address underlyingToken;
        uint256 collateralFactor; // BPS
        uint256 reserveFactor; // BPS
        address interestRateModel;
        bool isListed;
        bool isActive;
    }

    // State variables
    address[] public allMarkets;

    // underlyingToken => market
    mapping(address => address) public markets;

    // underlyingToken => config
    mapping(address => MarketConfig) public marketConfigs;

    // Comptroller-like (D6): kept as-is
    mapping(address => address[]) public accountAssets;
    mapping(address => mapping(address => bool)) public accountMembership;

    // market (address) => true si es un market creado por esta Factory.
    mapping(address => bool) public isMarket; // market => true/false
    //market (address) => underlyingToken.
    mapping(address => address) public marketToUnderlying; // market => underlying (opcional pero muy útil)

    PriceOracle public priceOracle;
    address public marketImplementation;
    address public rewardsDistributor;
    uint256 public liquidationIncentive; // BPS (e.g., 10800 = 108%)
    uint256 public closeFactor; // BPS (e.g., 5000 = 50%)

    // Events
    event MarketCreated(
        address indexed underlyingToken,
        address indexed market,
        address lToken
    );
    event MarketListed(address underlyingToken, address indexed market);
    event MarketDisabled(address underlyingToken, address indexed market); // disable == isActive=false
    event NewPriceOracle(address oldOracle, address newOracle);
    event NewCloseFactor(uint256 oldFactor, uint256 newFactor);
    event NewLiquidationIncentive(uint256 oldIncentive, uint256 newIncentive);
    event MarketEntered(address indexed market, address indexed account);
    event MarketExited(address indexed market, address indexed account);
    event NewRewardsDistributor(address oldRewardsDistributor, address newRewardsDistributor);

    constructor(
        address oracleAddress,
        address _marketImplementation
    ) Ownable(msg.sender) {
        require(oracleAddress != address(0), "Invalid oracle");
        require(_marketImplementation != address(0), "Invalid implementation");

        priceOracle = PriceOracle(oracleAddress);
        marketImplementation = _marketImplementation;

        liquidationIncentive = 10800; // 108%
        closeFactor = 5000; // 50%
    }

    function createMarket(
        address underlyingToken,
        uint256 collateralFactor,
        uint256 reserveFactor,
        address interestRateModel,
        string calldata lName, // Avoid all lTokens sharing same name
        string calldata lSymbol // Avoid all lTokens sharing same symbol
    ) external onlyOwner returns (address) {
        require(underlyingToken != address(0), "Invalid underlying");
        require(collateralFactor <= 9000, "Collateral factor too high");
        require(reserveFactor <= 5000, "Reserve factor too high");
        require(!marketConfigs[underlyingToken].isListed, "Market already listed");
        require(interestRateModel != address(0), "Invalid IRM");
        require(marketImplementation != address(0), "Implementation not set");

        // 1) Clone market (EIP-1167)
        address market = marketImplementation.clone();

        // Indexación O(1) por market address (evita iterar allMarkets)
        isMarket[market] = true;
        marketToUnderlying[market] = underlyingToken;

        // 2) Deploy lToken (owner = factory because Ownable(msg.sender) in LendingToken constructor)
        LendingToken lToken = new LendingToken(lName, lSymbol, underlyingToken);

        // 3) Initialize market (Opción A)
        LendingMarket(market).initialize(
            underlyingToken,
            address(this),
            address(priceOracle),
            interestRateModel,
            address(lToken),
            collateralFactor,
            reserveFactor
        );

        // 4) Wire lToken -> market (one-time)
        lToken.setMarket(market);

        // 5) Save registry/config
        allMarkets.push(market);
        markets[underlyingToken] = market;

        marketConfigs[underlyingToken] = MarketConfig({
            underlyingToken: underlyingToken,
            collateralFactor: collateralFactor,
            reserveFactor: reserveFactor,
            interestRateModel: interestRateModel,
            isListed: true,
            isActive: false
        });

        emit MarketCreated(underlyingToken, market, address(lToken));
        return market;
    }

    function listMarket(address underlyingToken) external onlyOwner {
        MarketConfig storage cfg = marketConfigs[underlyingToken];

        require(cfg.isListed, "Market not created");
        require(!cfg.isActive, "Market already active");
        require(markets[underlyingToken] != address(0), "Market not deployed");

        cfg.isActive = true;

        emit MarketListed(underlyingToken, markets[underlyingToken]);
    }

    // Renamed: delistMarket -> disableMarket, because you are setting isActive=false (not isListed=false)
    function disableMarket(address underlyingToken) external onlyOwner {
        MarketConfig storage cfg = marketConfigs[underlyingToken];

        require(cfg.isListed, "Market not listed");
        require(cfg.isActive, "Market not active");
        require(markets[underlyingToken] != address(0), "Market not deployed");

        cfg.isActive = false;

        emit MarketDisabled(underlyingToken, markets[underlyingToken]);
    }

    // Renamed: enterMarket -> enterMarkets (matches plan naming and semantics)
    function enterMarkets(
        address[] calldata marketAddresses
    ) external returns (uint256[] memory results) {
        require(marketAddresses.length > 0, "No markets provided");
        require(marketAddresses.length <= 10, "Too many markets");

        results = new uint256[](marketAddresses.length);

        for (uint256 i = 0; i < marketAddresses.length; i++) {
            address market = marketAddresses[i];

            // 1) Validar que es un market del protocolo
            if (!isMarket[market]) {
                results[i] = 1; // error code: MARKET_NOT_SUPPORTED
                continue;
            }

            // 2) Sacar underlying y config
            address underlying = marketToUnderlying[market];
            MarketConfig storage cfg = marketConfigs[underlying];

            // 3) Validar estado
            if (!cfg.isListed) {
                results[i] = 2; // MARKET_NOT_LISTED/CREATED
                continue;
            }
            if (!cfg.isActive) {
                results[i] = 3; // MARKET_NOT_ACTIVE
                continue;
            }

            // 4) Evitar duplicados
            if (!accountMembership[msg.sender][market]) {
                accountMembership[msg.sender][market] = true;
                accountAssets[msg.sender].push(market);
                emit MarketEntered(market, msg.sender);
            }

            results[i] = 0; // success
        }

        return results;
    }

    function exitMarket(address market) external returns (uint256) {
        require(isMarket[market], "Market not supported");
        require(accountMembership[msg.sender][market], "Not in market");

        // No permitir si tiene deuda en ese market
        uint256 borrowBal = LendingMarket(market).borrowBalanceStored(msg.sender);
        require(borrowBal == 0, "Outstanding borrow");

        // Quitar membership
        accountMembership[msg.sender][market] = false;

        // Remover de accountAssets (swap & pop)
        address[] storage assets = accountAssets[msg.sender];
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == market) {
                assets[i] = assets[assets.length - 1];
                assets.pop();
                break;
            }
        }

        emit MarketExited(market, msg.sender);
        return 0;
    }

    // ------------------------------------------------------------------------
    // Patrón tipo Compound: (err, liquidity, shortfall)
    // - err = 0: ok
    // - err != 0: hubo un problema (p.ej. falta de precio)
    // - liquidity/shortfall en USD WAD (1e18)
    // ------------------------------------------------------------------------
    function getAccountLiquidityInternal(
        address account
    ) internal view returns (uint256 err, uint256 liquidity, uint256 shortfall) {
        return getHypotheticalAccountLiquidityInternal(account, address(0), 0, 0);
    }

    // ------------------------------------------------------------------------
    // Día 7:
    // Liquidez hipotética (cross-market) para validar borrow/withdraw sin romper el ratio.
    // - marketModify: market sobre el que aplicas el cambio hipotético
    // - redeemUnderlying: reduce supplyUnderlying en ese market
    // - borrowUnderlying: incrementa borrowUnderlying en ese market
    // ------------------------------------------------------------------------
    function getHypotheticalAccountLiquidityInternal(
        address account,
        address marketModify,
        uint256 redeemUnderlying,
        uint256 borrowUnderlying
    ) internal view returns (uint256 err, uint256 liquidity, uint256 shortfall) {
        address[] storage assets = accountAssets[account];

        if (assets.length == 0) {
            return (0, 0, 0);
        }

        uint256 totalCollateralUsdWad = 0; // USD 1e18
        uint256 totalBorrowUsdWad = 0; // USD 1e18

        for (uint256 i = 0; i < assets.length; i++) {
            address market = assets[i];

            // Solo contar markets del protocolo (seguridad)
            if (!isMarket[market]) continue;

            // Bridge market -> underlying -> config
            address underlying = marketToUnderlying[market];
            MarketConfig storage cfg = marketConfigs[underlying];

            // Si el market está desactivado, lo ignoras (o podrías revertir).
            // Yo prefiero ignorar para que la vista no "rompa" si desactivas algo.
            if (!cfg.isActive) continue;

            // 1) Leer balances del usuario en ese market (en unidades del underlying)
            // (lTokenBalance, borrowBalance, exchangeRate)
            (uint256 lTokenBal, uint256 borrowBalUnderlying, uint256 exchRate) =
                LendingMarket(market).getAccountSnapshot(account);

            uint256 supplyUnderlying = (lTokenBal * exchRate) / 1e18;

            // 1b) Aplicar hipotético solo sobre marketModify
            if (marketModify != address(0) && market == marketModify) {
                if (redeemUnderlying > 0) {
                    if (redeemUnderlying > supplyUnderlying) {
                        return (2, 0, 0); // INSUFFICIENT_SUPPLY_FOR_REDEEM (hypo)
                    }
                    supplyUnderlying -= redeemUnderlying;
                }
                if (borrowUnderlying > 0) {
                    borrowBalUnderlying += borrowUnderlying;
                }
            }

            // 2) Precio del underlying en USD (oracle: 1e8)
            uint256 priceUsd1e8 = priceOracle.getPrice(underlying);

            // Si no hay precio y el usuario tiene posición, devolvemos error (más seguro para liquidaciones/checks).
            if (priceUsd1e8 == 0) {
                if (supplyUnderlying > 0 || borrowBalUnderlying > 0) {
                    return (1, 0, 0); // PRICE_ERROR
                }
                continue;
            }

            // 3) Normalizar amount según decimals del token y pasar a USD WAD (1e18)
            uint8 dec = IERC20Metadata(underlying).decimals();

            // USD WAD = amount * price(1e8) * 1e10 / 10^dec
            uint256 supplyUsdWad =
                (supplyUnderlying * priceUsd1e8 * 1e10) /
                (10 ** uint256(dec));
            uint256 borrowUsdWad =
                (borrowBalUnderlying * priceUsd1e8 * 1e10) /
                (10 ** uint256(dec));

            // 4) Aplicar collateralFactor al supply (en BPS)
            uint256 collateralUsdWad = (supplyUsdWad * cfg.collateralFactor) / BPS;

            totalCollateralUsdWad += collateralUsdWad;
            totalBorrowUsdWad += borrowUsdWad;
        }

        if (totalCollateralUsdWad >= totalBorrowUsdWad) {
            return (0, totalCollateralUsdWad - totalBorrowUsdWad, 0);
        } else {
            return (0, 0, totalBorrowUsdWad - totalCollateralUsdWad);
        }
    }

    function getAccountLiquidity(
        address account
    ) external view returns (uint256 liquidity, uint256 shortfall) {
        (uint256 err, uint256 liq, uint256 sf) = getAccountLiquidityInternal(account);
        // Si hay error, devolvemos (0,0) para no romper UIs; en funciones críticas usarías el err.
        if (err != 0) return (0, 0);
        return (liq, sf);
    }

    // Día 7: versión pública para checks (borrow/withdraw) usando hipotético
    function getHypotheticalAccountLiquidity(
        address account,
        address marketModify,
        uint256 redeemUnderlying,
        uint256 borrowUnderlying
    ) external view returns (uint256 liquidity, uint256 shortfall) {
        (uint256 err, uint256 liq, uint256 sf) =
            getHypotheticalAccountLiquidityInternal(account, marketModify, redeemUnderlying, borrowUnderlying);

        // Para checks críticos, si hay error, bloqueamos devolviendo shortfall>0.
        if (err != 0) return (0, 1);

        return (liq, sf);
    }

    // ------------------------------------------------------------------------
    // Día 7 (plan): validar si una liquidación es válida (código de error)
    // 0 = permitido
    // ------------------------------------------------------------------------
    function liquidateBorrowAllowed(
        address marketBorrowed,
        address marketCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external view returns (uint256) {
        // Validaciones básicas
        if (!isMarket[marketBorrowed] || !isMarket[marketCollateral]) return 1; // MARKET_NOT_SUPPORTED
        if (marketBorrowed == marketCollateral) return 2; // SAME_MARKET
        if (borrower == address(0) || liquidator == address(0)) return 3; // INVALID_ADDRESS
        if (repayAmount == 0) return 4; // INVALID_REPAY

        // Validar que ambos markets estén activos/listados
        {
            address ub = marketToUnderlying[marketBorrowed];
            address uc = marketToUnderlying[marketCollateral];
            if (ub == address(0) || uc == address(0)) return 5; // INVALID_UNDERLYING
            MarketConfig storage cfgB = marketConfigs[ub];
            MarketConfig storage cfgC = marketConfigs[uc];
            if (!cfgB.isListed || !cfgC.isListed) return 6; // NOT_LISTED
            if (!cfgB.isActive || !cfgC.isActive) return 7; // NOT_ACTIVE
        }

        // Borrower debe ser liquidable (shortfall > 0)
        (, uint256 shortfall) = this.getAccountLiquidity(borrower);
        if (shortfall == 0) return 8; // NOT_LIQUIDATABLE

        // closeFactor: repayAmount <= closeFactor * totalBorrow (en marketBorrowed)
        uint256 borrowBal = LendingMarket(marketBorrowed).borrowBalanceStored(borrower);
        if (borrowBal == 0) return 9; // NO_DEBT
        if (repayAmount > borrowBal) return 10; // REPAY_EXCEEDS_BORROW

        uint256 maxClose = (borrowBal * closeFactor) / BPS;
        if (repayAmount > maxClose) return 11; // EXCEEDS_CLOSE_FACTOR

        return 0;
    }

    // ------------------------------------------------------------------------
    // Día 7 (plan): validar si un embargo (seize) es válido (código de error)
    // 0 = permitido
    // ------------------------------------------------------------------------
    function seizeAllowed(
        address marketCollateral,
        address marketBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external view returns (uint256) {
        if (!isMarket[marketCollateral] || !isMarket[marketBorrowed]) return 1; // MARKET_NOT_SUPPORTED
        if (liquidator == address(0) || borrower == address(0)) return 2; // INVALID_ADDRESS
        if (liquidator == borrower) return 3; // SELF_SEIZE
        if (seizeTokens == 0) return 4; // INVALID_SEIZE

        // Validar listado/activo en ambos
        address uc = marketToUnderlying[marketCollateral];
        address ub = marketToUnderlying[marketBorrowed];
        if (uc == address(0) || ub == address(0)) return 5; // INVALID_UNDERLYING

        MarketConfig storage cfgC = marketConfigs[uc];
        MarketConfig storage cfgB = marketConfigs[ub];
        if (!cfgC.isListed || !cfgB.isListed) return 6; // NOT_LISTED
        if (!cfgC.isActive || !cfgB.isActive) return 7; // NOT_ACTIVE

        return 0;
    }

    // ------------------------------------------------------------------------
    // Devuelve seizeTokens en unidades de lToken del marketCollateral.
    // Fórmula:
    // - repayAmount (borrow underlying) -> USD
    // - USD * liquidationIncentive -> USD a "seize"
    // - USD -> seizeUnderlying (collateral underlying)
    // - seizeUnderlying / exchangeRate -> seizeTokens (lToken units)
    // ------------------------------------------------------------------------
    function liquidateCalculateSeizeTokens(
        address marketBorrowed,
        address marketCollateral,
        uint256 repayAmount
    ) external view returns (uint256 seizeTokens) {
        require(isMarket[marketBorrowed], "Borrow market not supported");
        require(isMarket[marketCollateral], "Collateral market not supported");

        address underlyingBorrow = marketToUnderlying[marketBorrowed];
        address underlyingColl = marketToUnderlying[marketCollateral];

        require(underlyingBorrow != address(0) && underlyingColl != address(0), "Invalid underlying");

        uint256 priceBorrow1e8 = priceOracle.getPrice(underlyingBorrow);
        uint256 priceColl1e8 = priceOracle.getPrice(underlyingColl);

        require(priceBorrow1e8 > 0 && priceColl1e8 > 0, "Missing price");

        uint8 borrowDec = IERC20Metadata(underlyingBorrow).decimals();
        uint8 collDec = IERC20Metadata(underlyingColl).decimals();

        // repayUsdWad = repayAmount * priceBorrow(1e8) * 1e10 / 10^borrowDec
        uint256 repayUsdWad =
            (repayAmount * priceBorrow1e8 * 1e10) /
            (10 ** uint256(borrowDec));

        // seizeUsdWad = repayUsdWad * liquidationIncentive(BPS) / BPS
        uint256 seizeUsdWad = (repayUsdWad * liquidationIncentive) / BPS;

        // seizeUnderlying = seizeUsdWad * 10^collDec / (priceColl(1e8) * 1e10)
        uint256 seizeUnderlying =
            (seizeUsdWad * (10 ** uint256(collDec))) /
            (priceColl1e8 * 1e10);

        // exchangeRate (WAD): underlying per 1 lToken
        uint256 exchangeRate = LendingMarket(marketCollateral).exchangeRateStored();
        require(exchangeRate > 0, "Invalid exchange rate");

        // seizeTokens = seizeUnderlying * 1e18 / exchangeRate
        seizeTokens = (seizeUnderlying * 1e18) / exchangeRate;
    }

    function getAllMarkets() external view returns (address[] memory) {
        return allMarkets;
    }

    function getMarketByToken(address token) external view returns (address) {
        return markets[token];
    }

    function getAssetsIn(address account) external view returns (address[] memory) {
        return accountAssets[account];
    }

    function setPriceOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Invalid oracle");
        address old = address(priceOracle);
        priceOracle = PriceOracle(newOracle);
        emit NewPriceOracle(old, newOracle);
    }

    function setCloseFactor(uint256 newCloseFactor) external onlyOwner {
        require(newCloseFactor > 0, "Invalid close factor");
        require(newCloseFactor <= BPS, "Close factor too high");
        uint256 old = closeFactor;
        closeFactor = newCloseFactor;
        emit NewCloseFactor(old, newCloseFactor);
    }

    function setLiquidationIncentive(uint256 newIncentive) external onlyOwner {
        // típicamente >= 100% (BPS) y con un cap razonable
        require(newIncentive >= BPS, "Incentive < 100%");
        require(newIncentive <= 12_000, "Incentive too high"); // 120% cap (ajustable)
        uint256 old = liquidationIncentive;
        liquidationIncentive = newIncentive;
        emit NewLiquidationIncentive(old, newIncentive);
    }

    function setRewardsDistributor(address newRD) external onlyOwner {
        address old = rewardsDistributor;
        rewardsDistributor = newRD;
        emit NewRewardsDistributor(old, newRD);
    }
}