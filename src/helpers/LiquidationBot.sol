// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../core/LendingMarket.sol";
import "../core/LendingMarketFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LiquidationBot {
    using SafeERC20 for IERC20;

    LendingMarketFactory public factory;

    constructor(address factoryAddress) {
        require(factoryAddress != address(0), "Invalid factory");
        factory = LendingMarketFactory(factoryAddress);
    }

    /// @notice Filtra cuentas liquidables (shortfall > 0)
    function findLiquidatableAccounts(address[] calldata accounts) external view returns (address[] memory) {
        // 1) contar
        uint256 count = 0;
        for (uint256 i = 0; i < accounts.length; i++) {
            (, uint256 shortfall) = factory.getAccountLiquidity(accounts[i]);
            if (shortfall > 0) count++;
        }

        // 2) construir array
        address[] memory result = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < accounts.length; i++) {
            (, uint256 shortfall) = factory.getAccountLiquidity(accounts[i]);
            if (shortfall > 0) {
                result[idx] = accounts[i];
                idx++;
            }
        }

        return result;
    }

    /// @notice Ganancia estimada en "lTokens del collateral" (seizeTokens - repayEquivalentInCollateralLTokens)
    /// @dev Esto es una aproximación: mide lo que "seizeas" en lTokens vs coste estimado de repay convertido a lTokens
    function calculateLiquidationProfit(
        address borrower,
        address marketBorrowed,
        address marketCollateral,
        uint256 repayAmount
    ) external view returns (uint256) {
        // if not allowed, profit = 0
        uint256 allowed = factory.liquidateBorrowAllowed(marketBorrowed, marketCollateral, address(this), borrower, repayAmount);
        if (allowed != 0) return 0;

        uint256 seizeTokens = factory.liquidateCalculateSeizeTokens(marketBorrowed, marketCollateral, repayAmount);
        if (seizeTokens == 0) return 0;

        // coste aproximado en lTokens del collateral: convertir repayAmount a "seizeTokens sin incentivo"
        // => dividimos por liquidationIncentive: seizeTokens / (liquidationIncentive/BPS)
        // Nota: esta aproximación asume linealidad y que seizeTokens ya incluye incentive.
        uint256 incentive = factory.liquidationIncentive(); // BPS
        if (incentive <= factory.BPS()) return 0;

        uint256 costInCollateralLTokens = (seizeTokens * factory.BPS()) / incentive;

        if (seizeTokens > costInCollateralLTokens) return seizeTokens - costInCollateralLTokens;
        return 0;
    }

    /// @notice Ejecuta liquidación (el caller debe haber aprobado al bot para mover el underlying del marketBorrowed)
    function executeLiquidation(
        address borrower,
        address marketBorrowed,
        address marketCollateral,
        uint256 repayAmount
    ) external {
        // Se paga con el underlying del marketBorrowed
        address underlyingBorrow = factory.marketToUnderlying(marketBorrowed);
        require(underlyingBorrow != address(0), "Invalid borrow underlying");

        // Transferir underlying desde el msg.sender al bot y aprobar al marketBorrowed
        IERC20(underlyingBorrow).safeTransferFrom(msg.sender, address(this), repayAmount);
        IERC20(underlyingBorrow).forceApprove(marketBorrowed, repayAmount);

        // Ejecutar liquidación: el liquidator efectivo será ESTE contrato (LiquidationBot)
        LendingMarket(marketBorrowed).liquidateBorrow(borrower, repayAmount, marketCollateral);

        // Nota: el bot recibirá lTokens del collateral. Tú puedes:
        // - dejarlos aquí
        // - o transferirlos al msg.sender si quieres (requeriría interfaz del lToken o snapshot adicional)
    }
}