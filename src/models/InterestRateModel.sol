//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract InterestRateModel {
    uint256 public constant WAD = 1e18;
    uint256 public constant BPS = 1e4;

    // ~12s por bloque => 365*24*60*60 / 12 = 2,628,000
    // Ajusta si quieres. Lo importante es consistencia.
    uint256 public constant BLOCKS_PER_YEAR = 2_628_000;

    // State variables (WAD per year)
    uint256 public immutable baseRatePerYear;        // ej 0.02e18 = 2% anual
    uint256 public immutable multiplierPerYear;      // slope before the kink (WAD)
    uint256 public immutable jumpMultiplierPerYear;  // slope after the kink (WAD)
    uint256 public immutable kink;

    // Events
    event InterestRateModelCreated(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink
    );

    

    constructor(uint256 _baseRatePerYear, uint256 _multiplierPerYear, uint256 _jumpMultiplierPerYear, uint256 _kink) {
        require(_kink <= WAD, "kink>1");
        baseRatePerYear = _baseRatePerYear;
        multiplierPerYear = _multiplierPerYear;
        jumpMultiplierPerYear = _jumpMultiplierPerYear;
        kink = _kink;

        emit InterestRateModelCreated(_baseRatePerYear, _multiplierPerYear, _jumpMultiplierPerYear, _kink);
    }
/// @notice Utilization = borrows / (cash + borrows - reserves)
    /// @dev retorna WAD (0..1e18)
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves)
        public
        pure
        returns (uint256)
    {
        if (borrows == 0) return 0;

        // Si reserves “se come” todo, evitamos underflow y devolvemos 0 (o podrías revertir)
        if (cash + borrows <= reserves) return 0;

        uint256 available = cash + borrows - reserves;
        if (available == 0) return 0;

        return (borrows * WAD) / available;
    }

    /// @notice BorrowRate anual (WAD)
    /// @dev Curva con kink: antes slope=multiplier, después slope=jumpMultiplier
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves)
        public
        view
        returns (uint256)
    {
        uint256 util = utilizationRate(cash, borrows, reserves);

        // Si util <= kink:
        // borrowRate = base + util * multiplier
        if (util <= kink) {
            return baseRatePerYear + (util * multiplierPerYear) / WAD;
        }

        // Si util > kink:
        // borrowRate = base + kink*multiplier + (util-kink)*jumpMultiplier
        uint256 normalRate = baseRatePerYear + (kink * multiplierPerYear) / WAD;
        uint256 excessUtil = util - kink;

        return normalRate + (excessUtil * jumpMultiplierPerYear) / WAD;

        /*
        Qué calcula: cuánto paga un borrower al año según la utilización.
            - Si el pool está poco utilizado (util baja), la tasa es baja.
            - Si está muy utilizado (util alta), la tasa sube.
            - Cuando cruzas el kink (ej 80%), sube más agresivamente.
        Cómo:
            - antes del kink: base + util * multiplier
            - después: base + kink*multiplier + (util-kink)*jumpMultiplier

        Esto evita que un pool llegue a 99% utilización y aún tenga tasas “suaves” (lo cual sería peligroso porque no hay liquidez para retiros).
        */
    }

    /// @notice SupplyRate anual (WAD)
    /// @dev supplyRate = borrowRate * util * (1 - reserveFactor)
    /// reserveFactor en BPS (0..10000)
    function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorBps) public view returns (uint256) {
        require(reserveFactorBps <= BPS, "reserveFactor>100%");
        uint256 util = utilizationRate(cash, borrows, reserves);
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);

        // rateToPool = borrowRate * util
        uint256 rateToPool = (borrowRate * util) / WAD;

        // supplyRate = rateToPool * (1 - reserveFactor)
        uint256 oneMinusReserve = BPS - reserveFactorBps;
        return (rateToPool * oneMinusReserve) / BPS;

        /*
        Qué calcula: cuánto ganan los depositantes.

        Lógica económica:
            - Los depositantes solo ganan por la parte que se presta (utilization).
            - Si nadie pide prestado (util=0), el supply rate tiende a 0.
            - El protocolo se queda una comisión (reserveFactor) de lo que pagan los borrowers.

        Cómo:
            - calculas borrowRate
            - lo multiplicas por util → “interés efectivo que entra al pool”
            - quitas el porcentaje de reserva → (1 - reserveFactor)
         */
    }

    function getBorrowRatePerBlock(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256) {
        return getBorrowRate(cash, borrows, reserves) / BLOCKS_PER_YEAR;
    }

    function getSupplyRatePerBlock(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorBps) external view returns (uint256) {
        return getSupplyRate(cash, borrows, reserves, reserveFactorBps) / BLOCKS_PER_YEAR;
    }
}
