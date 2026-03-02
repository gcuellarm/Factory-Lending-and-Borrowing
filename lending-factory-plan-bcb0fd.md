# Plan de Desarrollo: Factoría de Markets de Lending and Borrowing (7-10 Días)

Este plan detalla la transformación del LendingProtocol existente en una arquitectura completa de factoría que permite crear y gestionar múltiples markets independientes de lending and borrowing.

---

## ARQUITECTURA GENERAL DEL PROYECTO

El proyecto se compondrá de los siguientes contratos principales:

1. **LendingMarketFactory.sol** - Contrato factoría que crea y gestiona markets
2. **LendingMarket.sol** - Contrato individual de market (basado en LendingProtocol.sol)
3. **ILendingMarket.sol** - Interface para los markets
4. **PriceOracle.sol** - Oráculo de precios para valoración de activos
5. **InterestRateModel.sol** - Modelo de tasas de interés dinámicas
6. **LendingToken.sol** - Token ERC20 que representa depósitos (lToken)

---

## DÍA 1: DISEÑO DE INTERFACES Y ESTRUCTURAS BASE

### Objetivo del día
Crear las interfaces y estructuras de datos fundamentales que servirán como base para toda la arquitectura de la factoría.

### Archivo a crear: ILendingMarket.sol

**Imports necesarios:**
- IERC20 de OpenZeppelin

**Structs a definir:**

1. **MarketInfo**
   - token (address) - Dirección del token del market
   - lToken (address) - Dirección del token de liquidez (lToken)
   - totalSupply (uint256) - Total depositado
   - totalBorrow (uint256) - Total prestado
   - supplyRate (uint256) - Tasa de suministro actual
   - borrowRate (uint256) - Tasa de préstamo actual
   - collateralFactor (uint256) - Factor de colateralización
   - reserveFactor (uint256) - Factor de reserva del protocolo
   - lastUpdateTimestamp (uint256) - Última actualización de tasas
   - isActive (bool) - Estado del market

2. **UserPosition**
   - supplied (uint256) - Cantidad depositada por el usuario
   - borrowed (uint256) - Cantidad prestada por el usuario
   - supplyIndex (uint256) - Índice de interés de suministro
   - borrowIndex (uint256) - Índice de interés de préstamo
   - lastInterestUpdate (uint256) - Última actualización de intereses

**Eventos a definir:**

1. **Deposit(address indexed user, uint256 amount, uint256 lTokensMinted)**
   - Se emite cuando un usuario deposita tokens

2. **Withdraw(address indexed user, uint256 amount, uint256 lTokensBurned)**
   - Se emite cuando un usuario retira tokens

3. **Borrow(address indexed user, uint256 amount)**
   - Se emite cuando un usuario toma un préstamo

4. **Repay(address indexed user, uint256 amount)**
   - Se emite cuando un usuario repaga un préstamo

5. **Liquidation(address indexed liquidator, address indexed borrower, uint256 repayAmount, uint256 seizedCollateral)**
   - Se emite cuando se liquida una posición

6. **InterestAccrued(uint256 totalSupply, uint256 totalBorrow, uint256 supplyRate, uint256 borrowRate)**
   - Se emite cuando se actualizan los intereses

**Funciones de la interface:**

1. **deposit(uint256 amount) external returns (uint256)**
   - Parámetros: amount (cantidad a depositar)
   - Tipo: external - Llamada por usuarios externos
   - Retorna: Cantidad de lTokens acuñados
   - Propósito: Permitir a usuarios depositar tokens y recibir lTokens

2. **withdraw(uint256 lTokenAmount) external returns (uint256)**
   - Parámetros: lTokenAmount (cantidad de lTokens a quemar)
   - Tipo: external - Llamada por usuarios externos
   - Retorna: Cantidad de tokens subyacentes recibidos
   - Propósito: Permitir a usuarios retirar sus depósitos quemando lTokens

3. **borrow(uint256 amount) external**
   - Parámetros: amount (cantidad a pedir prestada)
   - Tipo: external - Llamada por usuarios externos
   - Retorna: Nada
   - Propósito: Permitir a usuarios pedir prestado contra su colateral

4. **repay(uint256 amount) external**
   - Parámetros: amount (cantidad a repagar)
   - Tipo: external - Llamada por usuarios externos
   - Retorna: Nada
   - Propósito: Permitir a usuarios repagar sus préstamos

5. **liquidate(address borrower, uint256 repayAmount) external**
   - Parámetros: borrower (usuario a liquidar), repayAmount (cantidad a repagar)
   - Tipo: external - Llamada por liquidadores
   - Retorna: Nada
   - Propósito: Permitir liquidación de posiciones insolventes

6. **accrueInterest() external**
   - Parámetros: Ninguno
   - Tipo: external - Puede ser llamada por cualquiera
   - Retorna: Nada
   - Propósito: Actualizar los intereses acumulados del market

7. **getMarketInfo() external view returns (MarketInfo memory)**
   - Parámetros: Ninguno
   - Tipo: external view - Solo lectura
   - Retorna: Información completa del market
   - Propósito: Consultar el estado actual del market

8. **getUserPosition(address user) external view returns (UserPosition memory)**
   - Parámetros: user (dirección del usuario)
   - Tipo: external view - Solo lectura
   - Retorna: Posición del usuario en el market
   - Propósito: Consultar la posición de un usuario específico

9. **getAccountLiquidity(address user) external view returns (uint256 liquidity, uint256 shortfall)**
   - Parámetros: user (dirección del usuario)
   - Tipo: external view - Solo lectura
   - Retorna: liquidity (liquidez disponible), shortfall (déficit si está en riesgo)
   - Propósito: Calcular la salud financiera de una cuenta

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 1

**¿Por qué crear una interface primero?**

Las interfaces en Solidity son contratos fundamentales que definen un estándar de comunicación. Crear ILendingMarket.sol primero es crucial porque:

1. **Estandarización:** Define un contrato claro de qué funciones debe implementar cada market, asegurando consistencia en toda la factoría.
2. **Desacoplamiento:** Permite que otros contratos (como la factoría) interactúen con markets sin conocer su implementación interna.
3. **Planificación:** Obliga a pensar en la arquitectura completa antes de escribir código, evitando refactorizaciones costosas.
4. **Testing:** Facilita la creación de mocks para testing sin necesidad de implementaciones completas.

**¿Por qué el struct MarketInfo?**

Este struct centraliza toda la información de un market en una sola estructura. Razones:

- **Eficiencia en queries:** Permite obtener todo el estado del market en una sola llamada, reduciendo costos de gas en lecturas múltiples.
- **Organización:** Agrupa datos relacionados lógicamente (token, lToken, tasas, factores).
- **Escalabilidad:** Facilita añadir nuevos campos sin romper la interface existente.
- **lastUpdateTimestamp:** Crítico para calcular intereses acumulados basados en tiempo transcurrido.
- **reserveFactor:** Determina qué porcentaje de intereses va al protocolo vs. a los depositantes (modelo de sostenibilidad económica).

**¿Por qué el struct UserPosition?**

Rastrea la posición individual de cada usuario en un market:

- **supplied y borrowed:** Cantidades base sin intereses acumulados.
- **supplyIndex y borrowIndex:** Índices personales que permiten calcular intereses de forma eficiente sin iterar sobre todos los bloques. Este es el modelo de Compound: cada usuario tiene un "checkpoint" de cuándo actualizó su posición por última vez.
- **lastInterestUpdate:** Timestamp para cálculos de interés compuesto.

**¿Por qué estos eventos específicos?**

Los eventos son fundamentales para:

1. **Deposit/Withdraw con lTokensMinted/Burned:** Permite a frontends y usuarios rastrear exactamente cuántos lTokens recibieron/quemaron, crucial para calcular rendimientos.
2. **InterestAccrued:** Permite monitorear cambios en tasas de interés en tiempo real, esencial para dashboards y análisis.
3. **Liquidation:** Transparencia en liquidaciones, permite a bots y usuarios ver oportunidades y riesgos.

**¿Por qué deposit() retorna uint256?**

Retornar la cantidad de lTokens acuñados es crítico porque:

- El exchange rate cambia constantemente (aumenta con intereses acumulados).
- Un depósito de 100 USDC hoy puede dar 95 lUSDC, mañana podría dar 94 lUSDC.
- El usuario necesita saber exactamente cuántos lTokens recibió para cálculos futuros.

**¿Por qué withdraw() usa lTokenAmount en lugar de amount?**

Esto es fundamental en el diseño de lending protocols:

- Los lTokens representan "shares" del pool total.
- El usuario quema lTokens para reclamar su porción del pool (que ha crecido con intereses).
- Similar a cómo funcionan los LP tokens en AMMs.
- Permite que el valor de cada lToken aumente con el tiempo (exchange rate creciente).

**¿Por qué accrueInterest() es external y puede ser llamada por cualquiera?**

Razones de diseño:

1. **Transparencia:** Cualquiera puede actualizar el estado, no hay control centralizado.
2. **Incentivos:** Bots pueden llamarla para mantener el protocolo actualizado.
3. **Precisión:** Asegura que antes de operaciones críticas, los intereses estén al día.
4. **Gas optimization:** Permite que usuarios paguen el gas de actualización solo cuando les convenga.

**¿Por qué getAccountLiquidity retorna dos valores (liquidity y shortfall)?**

Este diseño evita usar números negativos:

- **liquidity > 0, shortfall = 0:** Cuenta saludable, puede pedir más prestado.
- **liquidity = 0, shortfall > 0:** Cuenta en riesgo, puede ser liquidada.
- Más claro y eficiente que usar int256 con valores negativos.
- Permite cálculos más simples en contratos que consumen esta función.

---

## DÍA 2: CONTRATO DE ORACLE DE PRECIOS

### Objetivo del día
Implementar un sistema de oráculo de precios que permita valorar diferentes activos en el protocolo.

### Archivo a crear: PriceOracle.sol

**Imports necesarios:**
- Ownable de OpenZeppelin
- AggregatorV3Interface de Chainlink (para integración futura)

**Variables de estado:**

1. **prices** - mapping(address => uint256)
   - Mapeo de token a precio en USD (con 8 decimales)

2. **priceFeeds** - mapping(address => address)
   - Mapeo de token a dirección del price feed de Chainlink

3. **PRICE_DECIMALS** - uint256 constant = 8
   - Decimales usados para los precios

**Eventos:**

1. **PriceUpdated(address indexed token, uint256 oldPrice, uint256 newPrice)**
   - Se emite cuando se actualiza el precio de un token

2. **PriceFeedSet(address indexed token, address indexed priceFeed)**
   - Se emite cuando se configura un price feed de Chainlink

**Funciones a implementar:**

1. **setPrice(address token, uint256 price) external onlyOwner**
   - Parámetros: token (dirección del token), price (precio en USD con 8 decimales)
   - Tipo: external onlyOwner - Solo el owner puede actualizar precios manualmente
   - Retorna: Nada
   - Propósito: Establecer precio manual para testing o tokens sin oracle
   - Validaciones: token != address(0), price > 0

2. **setPriceFeed(address token, address priceFeed) external onlyOwner**
   - Parámetros: token (dirección del token), priceFeed (dirección del Chainlink feed)
   - Tipo: external onlyOwner - Solo el owner puede configurar feeds
   - Retorna: Nada
   - Propósito: Configurar un price feed de Chainlink para un token
   - Validaciones: token != address(0), priceFeed != address(0)

3. **getPrice(address token) external view returns (uint256)**
   - Parámetros: token (dirección del token)
   - Tipo: external view - Solo lectura, puede ser llamada por cualquiera
   - Retorna: Precio del token en USD con 8 decimales
   - Propósito: Obtener el precio actual de un token
   - Lógica: Si existe priceFeed, consultar Chainlink; sino, usar precio manual

4. **getPriceInEth(address token) external view returns (uint256)**
   - Parámetros: token (dirección del token)
   - Tipo: external view - Solo lectura
   - Retorna: Precio del token en ETH
   - Propósito: Obtener precio en términos de ETH para cálculos internos

5. **getUnderlyingPrice(address lToken) external view returns (uint256)**
   - Parámetros: lToken (dirección del lending token)
   - Tipo: external view - Solo lectura
   - Retorna: Precio del token subyacente
   - Propósito: Obtener precio del token subyacente dado un lToken

6. **batchGetPrices(address[] calldata tokens) external view returns (uint256[] memory)**
   - Parámetros: tokens (array de direcciones de tokens)
   - Tipo: external view - Solo lectura
   - Retorna: Array de precios correspondientes
   - Propósito: Optimización para obtener múltiples precios en una sola llamada

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 2

**¿Por qué necesitamos un oráculo de precios?**

El oráculo es el componente más crítico de un protocolo de lending porque:

1. **Valoración de colateral:** Para saber si un usuario puede pedir prestado, necesitamos valorar su colateral en una unidad común (USD).
2. **Detección de liquidaciones:** Comparar el valor del colateral vs. deuda requiere precios actualizados.
3. **Cross-asset lending:** Permite depositar ETH y pedir prestado USDC, por ejemplo.
4. **Prevención de insolvencia:** Precios incorrectos pueden llevar a bad debt en el protocolo.

**¿Por qué usar dos sistemas de precios (manual y Chainlink)?**

Esta arquitectura híbrida ofrece flexibilidad:

- **Precios manuales (mapping prices):** Útil para testing, tokens nuevos sin oracle, o situaciones de emergencia.
- **Chainlink feeds (mapping priceFeeds):** Precios descentralizados y confiables para producción.
- **Fallback logic:** Si Chainlink falla, puede usar precio manual como backup.

**¿Por qué PRICE_DECIMALS = 8?**

Estandarización de precisión:

- Chainlink usa 8 decimales para precios USD.
- Mantener consistencia evita errores de conversión.
- 8 decimales da suficiente precisión ($0.00000001) sin desperdiciar gas.
- Ejemplo: $1,500.00 se representa como 150000000000 (1500 × 10^8).

**¿Por qué setPrice() es onlyOwner?**

Seguridad crítica:

- Precios incorrectos pueden drenar el protocolo.
- Un atacante con control de precios podría: establecer precio de token basura = $1M, depositar 1 token, pedir prestado todo el protocolo.
- Solo el admin debe poder establecer precios manualmente.

**¿Por qué getPrice() consulta Chainlink primero?**

Priorización de descentralización:

```
if (priceFeed exists) {
    return Chainlink price (descentralizado, confiable)
} else {
    return manual price (centralizado, para emergencias)
}
```

Esto asegura que en producción se usen precios descentralizados cuando estén disponibles.

**¿Por qué getPriceInEth()?**

Optimización para cálculos internos:

- Algunos cálculos son más eficientes en términos de ETH.
- Evita conversiones múltiples USD → ETH en el código.
- Útil para gas optimization en funciones que comparan valores.

**¿Por qué getUnderlyingPrice(lToken)?**

Conveniencia para la factoría:

- La factoría trabaja con direcciones de markets (que tienen lTokens).
- Esta función permite obtener el precio del token subyacente directamente desde el lToken.
- Evita que la factoría tenga que rastrear qué token subyacente corresponde a cada lToken.

**¿Por qué batchGetPrices()?**

Optimización de gas crítica:

- Obtener precios de 10 tokens en llamadas separadas = 10 transacciones.
- Batch: 1 transacción para 10 tokens.
- Esencial para funciones como getAccountLiquidity() que necesitan múltiples precios.
- Reduce costos de gas significativamente para usuarios y frontends.

**Consideraciones de seguridad del oráculo:**

1. **Manipulación de precios:** Chainlink usa múltiples nodos, difícil de manipular.
2. **Staleness:** Deberías verificar que el precio no sea muy antiguo (añadir timestamp check).
3. **Circuit breakers:** En producción, añadir límites de cambio de precio (ej: máximo 10% por actualización).
4. **Múltiples oráculos:** Para máxima seguridad, usar promedio de Chainlink + Uniswap TWAP.

---

## DÍA 3: MODELO DE TASAS DE INTERÉS

### Objetivo del día
Crear un modelo de tasas de interés dinámicas basado en la utilización del market.

### Archivo a crear: InterestRateModel.sol

**Conceptos clave:**
- Utilization Rate = Total Borrowed / Total Supply
- Borrow Rate aumenta con la utilización
- Supply Rate = Borrow Rate × Utilization Rate × (1 - Reserve Factor)

**Variables de estado:**

1. **baseRatePerYear** - uint256
   - Tasa base anual cuando utilización es 0%

2. **multiplierPerYear** - uint256
   - Multiplicador de tasa por utilización

3. **jumpMultiplierPerYear** - uint256
   - Multiplicador adicional después del kink

4. **kink** - uint256
   - Punto de inflexión de utilización (ej: 80%)

5. **BLOCKS_PER_YEAR** - uint256 constant
   - Número de bloques por año (para cálculos)

**Funciones a implementar:**

1. **constructor(uint256 baseRate, uint256 multiplier, uint256 jumpMultiplier, uint256 kinkValue)**
   - Parámetros: baseRate, multiplier, jumpMultiplier, kinkValue
   - Propósito: Inicializar el modelo con parámetros específicos

2. **utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public pure returns (uint256)**
   - Parámetros: cash (efectivo disponible), borrows (total prestado), reserves (reservas)
   - Tipo: public pure - Función pura de cálculo
   - Retorna: Tasa de utilización en basis points (0-10000)
   - Propósito: Calcular qué porcentaje del capital está siendo utilizado
   - Fórmula: borrows / (cash + borrows - reserves)

3. **getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256)**
   - Parámetros: cash, borrows, reserves
   - Tipo: external view - Solo lectura
   - Retorna: Tasa de préstamo anual en basis points
   - Propósito: Calcular la tasa de interés para préstamos
   - Lógica: Usar modelo de curva con kink (tasa aumenta más rápido después del kink)

4. **getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactor) external view returns (uint256)**
   - Parámetros: cash, borrows, reserves, reserveFactor
   - Tipo: external view - Solo lectura
   - Retorna: Tasa de suministro anual en basis points
   - Propósito: Calcular la tasa de interés para depositantes
   - Fórmula: borrowRate × utilizationRate × (1 - reserveFactor)

5. **getBorrowRatePerBlock(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256)**
   - Parámetros: cash, borrows, reserves
   - Tipo: external view - Solo lectura
   - Retorna: Tasa de préstamo por bloque
   - Propósito: Obtener tasa por bloque para cálculos de acumulación

6. **getSupplyRatePerBlock(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactor) external view returns (uint256)**
   - Parámetros: cash, borrows, reserves, reserveFactor
   - Tipo: external view - Solo lectura
   - Retorna: Tasa de suministro por bloque
   - Propósito: Obtener tasa por bloque para cálculos de acumulación

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 3

**¿Por qué necesitamos tasas de interés dinámicas?**

Las tasas dinámicas son el corazón económico del protocolo:

1. **Balance oferta/demanda:** Si mucha gente pide prestado (alta utilización), las tasas suben para incentivar más depósitos.
2. **Prevención de insolvencia:** Tasas altas cuando hay poca liquidez evitan que el protocolo se quede sin fondos.
3. **Incentivos económicos:** Tasas bajas cuando hay mucha liquidez incentivan préstamos.
4. **Sostenibilidad:** El modelo asegura que siempre haya liquidez para retiros.

**¿Qué es la Utilization Rate y por qué es fundamental?**

La tasa de utilización mide qué porcentaje del capital disponible está siendo prestado:

```
Utilization = Borrows / (Cash + Borrows - Reserves)
```

Ejemplos:
- Market tiene $1000 depositados, $200 prestados → Utilization = 20%
- Market tiene $1000 depositados, $800 prestados → Utilization = 80% (¡alto riesgo!)

**¿Por qué usar un modelo con "kink"?**

El kink (punto de inflexión) crea dos pendientes:

- **Antes del kink (0-80% utilización):** Tasas suben gradualmente (pendiente suave).
- **Después del kink (80-100% utilización):** Tasas suben drásticamente (pendiente empinada).

Razón económica:
- Con 90% de utilización, hay poco efectivo para retiros → PELIGRO.
- Tasas muy altas incentivan: (a) repagar préstamos, (b) nuevos depósitos.
- Esto restaura la liquidez del protocolo.

**¿Por qué baseRatePerYear?**

Tasa mínima cuando utilización = 0%:

- Asegura que depositantes siempre ganen algo (aunque sea poco).
- Cubre costos operativos del protocolo.
- Típicamente 0-2% anual para stablecoins, 0-5% para activos volátiles.

**¿Por qué multiplierPerYear?**

Controla qué tan rápido suben las tasas con la utilización:

```
BorrowRate = baseRate + (utilization × multiplier)
```

- Multiplier alto = tasas suben rápido con demanda.
- Multiplier bajo = tasas más estables.
- Se ajusta según volatilidad del activo.

**¿Por qué jumpMultiplierPerYear?**

Multiplicador adicional después del kink:

```
Si utilization > kink:
    BorrowRate = baseRate + (kink × multiplier) + ((utilization - kink) × jumpMultiplier)
```

- jumpMultiplier >> multiplier (ej: 10x más grande).
- Crea incentivo fuerte para reducir utilización cuando está peligrosamente alta.
- Protege el protocolo de quedarse sin liquidez.

**¿Por qué BLOCKS_PER_YEAR?**

Conversión de tasas anuales a por-bloque:

- Ethereum: ~2.4 millones de bloques/año (antes de The Merge).
- Post-Merge: ~2.6 millones de bloques/año (12 segundos/bloque).
- Necesario porque los intereses se acumulan cada bloque.

```
ratePerBlock = ratePerYear / BLOCKS_PER_YEAR
```

**¿Por qué utilizationRate() es pure?**

Función pure = no lee ni modifica estado:

- Solo hace cálculos matemáticos con los parámetros.
- Más eficiente en gas.
- Puede ser llamada off-chain sin costo.
- Facilita testing y auditoría.

**¿Por qué Supply Rate < Borrow Rate?**

Matemática del protocolo:

```
Supply Rate = Borrow Rate × Utilization × (1 - Reserve Factor)
```

Ejemplo:
- Borrow Rate = 10% anual
- Utilization = 80%
- Reserve Factor = 10%
- Supply Rate = 10% × 0.8 × 0.9 = 7.2%

Los depositantes ganan menos porque:
1. Solo el dinero prestado genera intereses (utilization factor).
2. El protocolo toma una comisión (reserve factor).
3. Esto es sostenible porque los depositantes tienen liquidez inmediata.

**¿Por qué separar funciones por año vs. por bloque?**

Dos usos diferentes:

- **PerYear:** Para mostrar a usuarios (APY), más intuitivo.
- **PerBlock:** Para cálculos internos del contrato, más preciso.

Frontend usa perYear, smart contracts usan perBlock.

**Ejemplo de configuración típica:**

Para USDC (stablecoin):
- baseRate = 0% (o 0.5%)
- multiplier = 5%
- jumpMultiplier = 109%
- kink = 80%

Para ETH (volátil):
- baseRate = 2%
- multiplier = 10%
- jumpMultiplier = 300%
- kink = 80%

---

## DÍA 4: TOKEN DE LENDING (lToken)

### Objetivo del día
Crear el token ERC20 que representa los depósitos en un market específico.

### Archivo a crear: LendingToken.sol

**Herencia:**
- ERC20 de OpenZeppelin
- Ownable de OpenZeppelin

**Variables de estado:**

1. **underlyingToken** - IERC20
   - Token subyacente que representa este lToken

2. **market** - address
   - Dirección del market que controla este token

**Modificadores:**

1. **onlyMarket**
   - Restricción: Solo el contrato market puede llamar ciertas funciones
   - Propósito: Proteger funciones de mint/burn

**Funciones a implementar:**

1. **constructor(string memory name, string memory symbol, address underlyingTokenAddress)**
   - Parámetros: name (nombre del token), symbol (símbolo), underlyingTokenAddress
   - Propósito: Inicializar el lToken vinculado a un token subyacente
   - Ejemplo: "Lending USDC" (lUSDC) para USDC

2. **setMarket(address marketAddress) external onlyOwner**
   - Parámetros: marketAddress (dirección del market)
   - Tipo: external onlyOwner - Solo owner puede configurar
   - Retorna: Nada
   - Propósito: Establecer qué market controla este token (llamar una sola vez)

3. **mint(address to, uint256 amount) external onlyMarket**
   - Parámetros: to (destinatario), amount (cantidad)
   - Tipo: external onlyMarket - Solo el market puede acuñar
   - Retorna: Nada
   - Propósito: Acuñar lTokens cuando un usuario deposita

4. **burn(address from, uint256 amount) external onlyMarket**
   - Parámetros: from (usuario), amount (cantidad)
   - Tipo: external onlyMarket - Solo el market puede quemar
   - Retorna: Nada
   - Propósito: Quemar lTokens cuando un usuario retira

5. **getUnderlyingToken() external view returns (address)**
   - Parámetros: Ninguno
   - Tipo: external view - Solo lectura
   - Retorna: Dirección del token subyacente
   - Propósito: Consultar qué token representa este lToken

6. **balanceOfUnderlying(address account) external view returns (uint256)**
   - Parámetros: account (dirección del usuario)
   - Tipo: external view - Solo lectura
   - Retorna: Cantidad de tokens subyacentes que representan los lTokens del usuario
   - Propósito: Calcular cuántos tokens subyacentes puede reclamar un usuario
   - Lógica: Consultar al market el exchange rate actual

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 4

**¿Por qué necesitamos un token separado (lToken)?**

El lToken es fundamental para el modelo económico del protocolo:

1. **Representación de shares:** Similar a LP tokens en AMMs, representa tu porción del pool total.
2. **Acumulación automática de intereses:** El valor del lToken aumenta con el tiempo sin necesidad de reclamar.
3. **Transferibilidad:** Los usuarios pueden transferir sus posiciones a otros.
4. **Composabilidad:** Los lTokens pueden usarse en otros protocolos DeFi (como colateral en otros lugares).
5. **Eficiencia de gas:** No necesitas actualizar balances de cada usuario cada bloque.

**¿Cómo funcionan los lTokens matemáticamente?**

Modelo de exchange rate creciente:

```
Día 1: Depositas 100 USDC → Recibes 100 lUSDC (exchange rate = 1.0)
Día 30: Exchange rate = 1.02 (2% interés acumulado)
Día 30: Tus 100 lUSDC ahora valen 102 USDC
```

El exchange rate aumenta porque:
- Total underlying en el pool crece (intereses de préstamos).
- Total lTokens permanece constante (o crece más lento).
- Exchange rate = Total Underlying / Total lTokens.

**¿Por qué heredar de ERC20?**

Estandarización y compatibilidad:

- **ERC20:** Estándar universal, compatible con wallets, exchanges, otros protocolos.
- **transfer/transferFrom:** Usuarios pueden mover sus posiciones.
- **approve/allowance:** Permite integraciones con otros contratos.
- **balanceOf:** Consulta simple de cuántos lTokens tiene un usuario.

**¿Por qué heredar de Ownable?**

Control de inicialización:

- Solo el owner (factoría) puede llamar setMarket().
- Previene que cualquiera establezca el market después del deployment.
- Después de setMarket(), el owner puede renunciar a la propiedad (opcional).

**¿Por qué el modificador onlyMarket?**

Seguridad crítica:

- Solo el market puede mint/burn lTokens.
- Si cualquiera pudiera mint, podría crear lTokens de la nada y drenar el protocolo.
- Si cualquiera pudiera burn, podría destruir lTokens de otros usuarios.

**¿Por qué underlyingToken es necesario?**

Rastreabilidad:

- Cada lToken debe saber qué token representa.
- Necesario para balanceOfUnderlying() y otras funciones.
- Permite verificación de que estás interactuando con el token correcto.

**¿Por qué setMarket() se llama solo una vez?**

Inmutabilidad de la relación:

- Un lToken debe estar vinculado a un solo market para siempre.
- Cambiar el market después rompería toda la contabilidad.
- Se llama durante la inicialización y nunca más.

**¿Por qué mint() es onlyMarket?**

Flujo de depósito:

```
1. Usuario llama market.deposit(100 USDC)
2. Market recibe 100 USDC del usuario
3. Market calcula: 100 USDC / exchangeRate = 98 lUSDC (si rate = 1.02)
4. Market llama lToken.mint(usuario, 98)
5. Usuario recibe 98 lUSDC
```

Solo el market sabe el exchange rate correcto y puede validar que recibió los tokens.

**¿Por qué burn() es onlyMarket?**

Flujo de retiro:

```
1. Usuario llama market.withdraw(50 lUSDC)
2. Market calcula: 50 lUSDC × exchangeRate = 51 USDC (si rate = 1.02)
3. Market llama lToken.burn(usuario, 50)
4. Market transfiere 51 USDC al usuario
```

Solo el market puede validar que tiene suficiente underlying para dar al usuario.

**¿Por qué balanceOfUnderlying()?**

Conveniencia para usuarios:

- balanceOf() retorna lTokens (ej: 100 lUSDC).
- balanceOfUnderlying() retorna underlying (ej: 102 USDC).
- Más intuitivo para usuarios ver su balance real en el token original.

Cálculo:
```
balanceOfUnderlying = balanceOf(user) × exchangeRate
```

**¿Por qué los lTokens son transferibles?**

Casos de uso:

1. **Vender posición:** Usuario A puede vender sus lTokens a Usuario B.
2. **Colateral externo:** Usar lTokens como colateral en otro protocolo.
3. **Herencia/Regalos:** Transferir posiciones entre cuentas.
4. **Liquidez secundaria:** Crear pools de lTokens en AMMs.

**Consideraciones de seguridad:**

- **Reentrancy:** Aunque ERC20 tiene protecciones, el market debe usar nonReentrant.
- **Exchange rate manipulation:** El market debe actualizar el rate antes de mint/burn.
- **Approval frontrunning:** Usar increaseAllowance/decreaseAllowance en lugar de approve cuando sea posible.

**Ejemplo práctico:**

```
Alice deposita 1000 USDC cuando exchange rate = 1.0
→ Recibe 1000 lUSDC

Pasan 30 días, se acumulan intereses
Exchange rate ahora = 1.05

Alice quiere retirar todo:
→ Quema 1000 lUSDC
→ Recibe 1050 USDC (ganó 50 USDC de intereses)
```

---

## DÍA 5: MODIFICACIÓN DEL LENDINGPROTOCOL.SOL → LENDINGMARKET.SOL

### Objetivo del día
Transformar el LendingProtocol.sol existente en LendingMarket.sol, adaptándolo para funcionar como un market individual de un solo token.

### Cambios a realizar en el archivo existente:

**CAMBIOS EN LA ESTRUCTURA:**

1. **Renombrar el contrato:**
   - De: contract LendingProtocol
   - A: contract LendingMarket

2. **Eliminar structs y mappings multi-token:**
   - ELIMINAR: mapping(address => Market) public markets
   - ELIMINAR: address[] public supportedTokens
   - ELIMINAR: struct Market (ya no se necesita, ahora es un market de un solo token)

3. **Nuevas variables de estado a AÑADIR:**
   - **underlyingToken** - IERC20 immutable
     - Token único de este market
   
   - **lToken** - LendingToken
     - Token que representa depósitos
   
   - **priceOracle** - PriceOracle
     - Referencia al oráculo de precios
   
   - **interestRateModel** - InterestRateModel
     - Modelo de tasas de interés
   
   - **factory** - address immutable
     - Dirección de la factoría que creó este market
   
   - **totalCash** - uint256
     - Efectivo disponible en el market
   
   - **totalBorrows** - uint256
     - Total prestado del market
   
   - **totalReserves** - uint256
     - Reservas del protocolo
   
   - **borrowIndex** - uint256
     - Índice acumulativo de interés de préstamos
   
   - **supplyIndex** - uint256
     - Índice acumulativo de interés de suministros
   
   - **accrualBlockNumber** - uint256
     - Último bloque donde se acumularon intereses
   
   - **reserveFactor** - uint256
     - Porcentaje de intereses que van a reservas (en basis points)
   
   - **collateralFactor** - uint256
     - Factor de colateralización para este token

4. **Modificar struct User:**
   - CAMBIAR: totalDeposited y totalBorrowed (ahora son específicos de este market)
   - AÑADIR: supplyIndex (índice personal de suministro)
   - AÑADIR: borrowIndex (índice personal de préstamo)
   - AÑADIR: interestAccrued (intereses acumulados no reclamados)

5. **Simplificar mappings:**
   - CAMBIAR: mapping(address => mapping(address => uint256)) public userDeposits
   - A: mapping(address => uint256) public userSupplies
   - CAMBIAR: mapping(address => mapping(address => uint256)) public userBorrows
   - A: mapping(address => uint256) public userBorrows

6. **Nuevos eventos a AÑADIR:**
   - **MarketInitialized(address indexed underlyingToken, address indexed lToken)**
   - **InterestAccrued(uint256 cashPrior, uint256 interestAccumulated, uint256 borrowIndex, uint256 totalBorrows)**
   - **ReservesAdded(uint256 amount, uint256 totalReserves)**
   - **ReservesReduced(uint256 amount, uint256 totalReserves)**

7. **Modificar el constructor:**
   - AÑADIR parámetros: address underlyingTokenAddress, address factoryAddress, address oracleAddress, address interestRateModelAddress, uint256 initialCollateralFactor, uint256 initialReserveFactor
   - Inicializar todas las nuevas variables
   - Crear el LendingToken asociado
   - Establecer borrowIndex = 1e18 y supplyIndex = 1e18 (índices iniciales)

**FUNCIONES A MODIFICAR:**

1. **addMarket y updateMarket:**
   - ELIMINAR estas funciones (ya no se gestionan múltiples markets aquí)

2. **deposit:**
   - CAMBIAR: Eliminar parámetro token (ahora es implícito)
   - AÑADIR: Acuñar lTokens al depositante
   - AÑADIR: Llamar a accrueInterest() antes de depositar
   - CAMBIAR: Actualizar totalCash en lugar de markets[token].totalSupply

3. **withdraw:**
   - CAMBIAR: Eliminar parámetro token
   - CAMBIAR: Parámetro debe ser lTokenAmount en lugar de amount
   - AÑADIR: Quemar lTokens del usuario
   - AÑADIR: Calcular cantidad de underlying basado en exchange rate
   - AÑADIR: Llamar a accrueInterest() antes de retirar

4. **borrow:**
   - CAMBIAR: Eliminar parámetro token
   - AÑADIR: Llamar a accrueInterest() antes de prestar
   - AÑADIR: Verificar liquidez con priceOracle
   - CAMBIAR: Actualizar borrowIndex del usuario

5. **repay:**
   - CAMBIAR: Eliminar parámetro token
   - AÑADIR: Llamar a accrueInterest() antes de repagar
   - CAMBIAR: Actualizar borrowIndex del usuario

6. **liquidate:**
   - CAMBIAR: Eliminar parámetro token
   - AÑADIR: Calcular descuento de liquidación
   - AÑADIR: Usar priceOracle para valoración
   - CAMBIAR: Transferir lTokens del colateral al liquidador

**NUEVAS FUNCIONES A AÑADIR:**

1. **accrueInterest() public**
   - Parámetros: Ninguno
   - Tipo: public - Puede ser llamada por cualquiera
   - Retorna: Nada
   - Propósito: Actualizar los índices de interés y acumular intereses
   - Lógica: Calcular bloques transcurridos, aplicar tasas, actualizar índices

2. **exchangeRateCurrent() public returns (uint256)**
   - Parámetros: Ninguno
   - Tipo: public - Modifica estado (llama accrueInterest)
   - Retorna: Exchange rate actual (underlying por lToken)
   - Propósito: Obtener tasa de cambio actualizada

3. **exchangeRateStored() public view returns (uint256)**
   - Parámetros: Ninguno
   - Tipo: public view - Solo lectura
   - Retorna: Exchange rate almacenado (sin actualizar)
   - Propósito: Consultar tasa de cambio sin gas

4. **getAccountSnapshot(address account) external view returns (uint256 lTokenBalance, uint256 borrowBalance, uint256 exchangeRate)**
   - Parámetros: account (dirección del usuario)
   - Tipo: external view - Solo lectura
   - Retorna: Balance de lTokens, balance de préstamos, exchange rate
   - Propósito: Obtener snapshot completo de una cuenta

5. **getCash() external view returns (uint256)**
   - Parámetros: Ninguno
   - Tipo: external view - Solo lectura
   - Retorna: Efectivo disponible en el contrato
   - Propósito: Consultar liquidez disponible

6. **setReserveFactor(uint256 newReserveFactor) external onlyOwner**
   - Parámetros: newReserveFactor (nuevo factor de reserva)
   - Tipo: external onlyOwner - Solo owner
   - Retorna: Nada
   - Propósito: Ajustar el porcentaje de reservas del protocolo

7. **setCollateralFactor(uint256 newCollateralFactor) external onlyOwner**
   - Parámetros: newCollateralFactor (nuevo factor de colateral)
   - Tipo: external onlyOwner - Solo owner
   - Retorna: Nada
   - Propósito: Ajustar el factor de colateralización

8. **reduceReserves(uint256 amount) external onlyOwner**
   - Parámetros: amount (cantidad a retirar de reservas)
   - Tipo: external onlyOwner - Solo owner
   - Retorna: Nada
   - Propósito: Permitir al owner retirar reservas acumuladas

**FUNCIONES A ELIMINAR:**
- depositWithSignature (simplificar por ahora, se puede añadir después)
- canWithdraw y canBorrow (reemplazar con getAccountLiquidity)
- findBestCollateral (ya no aplica en market de un solo token)

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 5

**¿Por qué transformar LendingProtocol en lugar de crear desde cero?**

Aprovechamiento de código existente:

1. **Lógica base ya funciona:** deposit, withdraw, borrow, repay ya están implementados.
2. **Seguridad probada:** El código existente ya tiene validaciones y protecciones.
3. **Refactorización incremental:** Más fácil modificar que reescribir completamente.
4. **Aprendizaje:** Entiendes mejor el código al transformarlo.

**¿Por qué cambiar de multi-token a single-token?**

Arquitectura de factoría:

- **Antes:** Un contrato gestiona múltiples tokens (markets[address]).
- **Después:** Cada contrato gestiona UN token (underlyingToken immutable).
- **Ventaja:** Separación de concerns, cada market es independiente.
- **Escalabilidad:** Crear nuevos markets no afecta a los existentes.

**¿Por qué usar immutable para underlyingToken y factory?**

Optimización y seguridad:

- **immutable:** Se establece en constructor y nunca cambia.
- **Gas savings:** Más barato leer que storage normal.
- **Seguridad:** Imposible cambiar después del deployment.
- **Claridad:** Deja claro que estos valores son permanentes.

**¿Por qué necesitamos borrowIndex y supplyIndex?**

Sistema de interés compuesto eficiente:

Sin índices (ineficiente):
```
Cada bloque: actualizar balance de CADA usuario → O(n) operaciones
```

Con índices (eficiente):
```
Cada bloque: actualizar UN índice global → O(1) operación
Cuando usuario interactúa: calcular su interés usando su índice personal
```

Matemática:
```
borrowIndex inicial = 1e18
Después de 1000 bloques con 5% APY: borrowIndex = 1.05e18
Usuario con borrowIndex personal = 1e18 debe: amount × (1.05e18 / 1e18) = 1.05 × amount
```

**¿Por qué accrualBlockNumber?**

Rastreo de actualizaciones:

- Guarda el último bloque donde se actualizaron los intereses.
- Permite calcular: bloques transcurridos = block.number - accrualBlockNumber.
- Necesario para aplicar intereses correctamente.

**¿Por qué totalReserves?**

Modelo económico del protocolo:

- Parte de los intereses va al protocolo (no a depositantes).
- totalReserves acumula estas ganancias.
- El owner puede retirarlas con reduceReserves().
- Financia desarrollo, auditorías, seguros, etc.

**¿Por qué reserveFactor?**

Balance económico:

```
Intereses generados = 100 USDC
reserveFactor = 10% (1000 basis points)
→ 10 USDC van a reservas
→ 90 USDC van a depositantes
```

- Típicamente 5-15%.
- Muy bajo: protocolo no genera ingresos.
- Muy alto: depositantes ganan poco, se van a competencia.

**¿Por qué collateralFactor?**

Control de riesgo:

```
collateralFactor = 75% (7500 basis points)
Usuario deposita $100 de ETH
→ Puede pedir prestado máximo $75
```

Razones:
- **Buffer de seguridad:** Si ETH baja 25%, el colateral aún cubre la deuda.
- **Prevención de liquidaciones inmediatas:** Da tiempo para que usuarios actúen.
- **Varía por activo:** Stablecoins 90%, ETH 75%, tokens volátiles 50%.

**¿Por qué accrueInterest() debe llamarse antes de operaciones?**

Precisión y seguridad:

```
Sin accrueInterest():
1. Usuario pide prestado 100 USDC
2. Pasan 1000 bloques (intereses acumulados)
3. Usuario deposita más colateral
4. Sistema calcula si puede pedir prestado MÁS
5. ¡Usa deuda antigua sin intereses! → Usuario puede sobre-endeudarse

Con accrueInterest():
1. Usuario pide prestado 100 USDC
2. Pasan 1000 bloques
3. Usuario deposita más colateral
4. accrueInterest() actualiza deuda a 105 USDC
5. Sistema usa deuda correcta → Cálculos precisos
```

**¿Por qué exchangeRateCurrent() vs exchangeRateStored()?**

Dos casos de uso:

- **exchangeRateCurrent():** Llama accrueInterest(), modifica estado, retorna rate actualizado. Usa cuando necesitas precisión absoluta.
- **exchangeRateStored():** Solo lee, no modifica estado, más barato. Usa para displays o cálculos aproximados.

**¿Por qué getAccountSnapshot()?**

Optimización para la factoría:

```
Sin snapshot:
- Llamar lToken.balanceOf(user)
- Llamar market.borrowBalance(user)
- Llamar market.exchangeRate()
= 3 llamadas externas

Con snapshot:
- Llamar market.getAccountSnapshot(user)
= 1 llamada externa
```

Reduce gas significativamente en getAccountLiquidity() de la factoría.

**¿Por qué getCash()?**

Transparencia y cálculos:

- cash = balance de underlying tokens en el contrato.
- Necesario para calcular utilization rate.
- Permite verificar liquidez disponible.
- Usado por InterestRateModel.

**¿Por qué permitir ajustar reserveFactor y collateralFactor?**

Gobernanza y adaptabilidad:

- **Condiciones de mercado cambian:** En crisis, reducir collateralFactor para más seguridad.
- **Competencia:** Ajustar reserveFactor para ser más atractivo.
- **Optimización:** Encontrar balance óptimo con el tiempo.
- **onlyOwner:** Solo admin puede cambiar (eventualmente, governance).

**¿Por qué reduceReserves()?**

Sostenibilidad del protocolo:

- Permite al protocolo usar sus ganancias acumuladas.
- Financiar desarrollo continuo.
- Pagar auditorías de seguridad.
- Crear fondo de seguros.
- onlyOwner previene que cualquiera drene las reservas.

**¿Por qué eliminar depositWithSignature()?**

Simplificación:

- Funcionalidad avanzada, no esencial para MVP.
- Añade complejidad de seguridad (validación de firmas).
- Puede añadirse después si hay demanda.
- Permite enfocarse en funcionalidad core primero.

**¿Por qué eliminar canWithdraw y canBorrow?**

Reemplazo por mejor diseño:

- Estas funciones iteraban sobre múltiples tokens.
- En single-token market, la lógica cambia.
- getAccountLiquidity() en la factoría hace este trabajo mejor.
- Reduce duplicación de código.

**Flujo completo de acumulación de intereses:**

```
Bloque 1000: accrualBlockNumber = 1000, borrowIndex = 1.0e18
Bloque 2000: accrueInterest() se llama
  → Bloques transcurridos = 1000
  → Tasa por bloque = 0.0001% (ejemplo)
  → Interés = 1000 × 0.0001% = 0.1%
  → Nuevo borrowIndex = 1.0e18 × 1.001 = 1.001e18
  → accrualBlockNumber = 2000

Usuario con deuda de 100 USDC desde bloque 1000:
  → Su borrowIndex personal = 1.0e18
  → Deuda actual = 100 × (1.001e18 / 1.0e18) = 100.1 USDC
```

---

## DÍA 6: CONTRATO FACTORÍA (LendingMarketFactory.sol)

### Objetivo del día
Crear el contrato principal que gestiona la creación y administración de múltiples markets.

### Archivo a crear: LendingMarketFactory.sol

**Imports necesarios:**
- Ownable de OpenZeppelin
- LendingMarket
- PriceOracle
- InterestRateModel
- Clones de OpenZeppelin (para crear markets con minimal proxy pattern)

**Structs:**

1. **MarketConfig**
   - underlyingToken (address) - Token del market
   - collateralFactor (uint256) - Factor de colateralización
   - reserveFactor (uint256) - Factor de reservas
   - interestRateModel (address) - Modelo de tasas
   - isListed (bool) - Si el market está listado
   - isActive (bool) - Si el market está activo

**Variables de estado:**

1. **allMarkets** - address[]
   - Array con todas las direcciones de markets creados

2. **markets** - mapping(address => address)
   - Mapeo de token subyacente a dirección del market

3. **marketConfigs** - mapping(address => MarketConfig)
   - Configuración de cada market

4. **priceOracle** - PriceOracle
   - Oráculo de precios compartido

5. **marketImplementation** - address
   - Implementación base para crear clones

6. **admin** - address
   - Administrador del protocolo

7. **liquidationIncentive** - uint256
   - Incentivo para liquidadores (ej: 108% = 10800 basis points)

8. **closeFactor** - uint256
   - Máximo porcentaje de deuda que se puede liquidar de una vez

**Eventos:**

1. **MarketCreated(address indexed underlyingToken, address indexed market, address lToken)**
   - Se emite cuando se crea un nuevo market

2. **MarketListed(address indexed market)**
   - Se emite cuando un market se lista en el protocolo

3. **MarketDelisted(address indexed market)**
   - Se emite cuando un market se elimina del protocolo

4. **NewPriceOracle(address oldOracle, address newOracle)**
   - Se emite cuando se actualiza el oráculo

5. **NewCloseFactor(uint256 oldFactor, uint256 newFactor)**
   - Se emite cuando se actualiza el close factor

6. **NewLiquidationIncentive(uint256 oldIncentive, uint256 newIncentive)**
   - Se emite cuando se actualiza el incentivo de liquidación

7. **MarketEntered(address indexed market, address indexed account)**
   - Se emite cuando un usuario entra a un market

8. **MarketExited(address indexed market, address indexed account)**
   - Se emite cuando un usuario sale de un market

**Mappings para gestión de colateral:**

1. **accountAssets** - mapping(address => address[])
   - Markets en los que cada usuario tiene posiciones

2. **accountMembership** - mapping(address => mapping(address => bool))
   - Si un usuario es miembro de un market específico

**Funciones a implementar:**

1. **constructor(address oracleAddress)**
   - Parámetros: oracleAddress (dirección del oráculo)
   - Propósito: Inicializar la factoría con el oráculo de precios
   - Establecer liquidationIncentive = 10800 (108%)
   - Establecer closeFactor = 5000 (50%)

2. **createMarket(address underlyingToken, uint256 collateralFactor, uint256 reserveFactor, address interestRateModel) external onlyOwner returns (address)**
   - Parámetros: underlyingToken, collateralFactor, reserveFactor, interestRateModel
   - Tipo: external onlyOwner - Solo owner puede crear markets
   - Retorna: Dirección del nuevo market creado
   - Propósito: Crear un nuevo market para un token específico
   - Validaciones: Token no debe tener market existente, collateralFactor <= 90%, reserveFactor <= 50%
   - Lógica: Usar Clones.clone() para crear minimal proxy del market

3. **listMarket(address market) external onlyOwner**
   - Parámetros: market (dirección del market)
   - Tipo: external onlyOwner - Solo owner
   - Retorna: Nada
   - Propósito: Listar un market en el protocolo (activarlo)

4. **delistMarket(address market) external onlyOwner**
   - Parámetros: market (dirección del market)
   - Tipo: external onlyOwner - Solo owner
   - Retorna: Nada
   - Propósito: Deslistar un market (desactivarlo)

5. **enterMarkets(address[] calldata marketAddresses) external returns (uint256[] memory)**
   - Parámetros: marketAddresses (array de markets a entrar)
   - Tipo: external - Llamada por usuarios
   - Retorna: Array de códigos de error (0 = éxito)
   - Propósito: Permitir a usuarios usar sus depósitos como colateral
   - Lógica: Añadir markets a accountAssets del usuario

6. **exitMarket(address market) external returns (uint256)**
   - Parámetros: market (dirección del market)
   - Tipo: external - Llamada por usuarios
   - Retorna: Código de error (0 = éxito)
   - Propósito: Permitir a usuarios dejar de usar un market como colateral
   - Validación: No debe dejar la cuenta en riesgo de liquidación

7. **getAccountLiquidity(address account) external view returns (uint256 liquidity, uint256 shortfall)**
   - Parámetros: account (dirección del usuario)
   - Tipo: external view - Solo lectura
   - Retorna: liquidity (exceso de colateral), shortfall (déficit de colateral)
   - Propósito: Calcular la salud financiera global de una cuenta
   - Lógica: Iterar sobre todos los markets del usuario, sumar colateral y deuda valorados en USD

8. **getAccountLiquidityInternal(address account) internal view returns (uint256, uint256, uint256)**
   - Parámetros: account
   - Tipo: internal view - Uso interno
   - Retorna: error code, liquidity, shortfall
   - Propósito: Versión interna de getAccountLiquidity con más detalles

9. **liquidateCalculateSeizeTokens(address marketBorrowed, address marketCollateral, uint256 repayAmount) external view returns (uint256)**
   - Parámetros: marketBorrowed, marketCollateral, repayAmount
   - Tipo: external view - Solo lectura
   - Retorna: Cantidad de tokens de colateral a embargar
   - Propósito: Calcular cuánto colateral se embarga en una liquidación
   - Fórmula: (repayAmount × priceBorrowed × liquidationIncentive) / priceCollateral

10. **getAllMarkets() external view returns (address[] memory)**
    - Parámetros: Ninguno
    - Tipo: external view - Solo lectura
    - Retorna: Array con todos los markets
    - Propósito: Obtener lista completa de markets

11. **getMarketByToken(address token) external view returns (address)**
    - Parámetros: token (dirección del token subyacente)
    - Tipo: external view - Solo lectura
    - Retorna: Dirección del market correspondiente
    - Propósito: Buscar market por su token subyacente

12. **getAssetsIn(address account) external view returns (address[] memory)**
    - Parámetros: account (dirección del usuario)
    - Tipo: external view - Solo lectura
    - Retorna: Array de markets donde el usuario tiene posiciones
    - Propósito: Consultar en qué markets participa un usuario

13. **setPriceOracle(address newOracle) external onlyOwner**
    - Parámetros: newOracle (nueva dirección del oráculo)
    - Tipo: external onlyOwner - Solo owner
    - Retorna: Nada
    - Propósito: Actualizar el oráculo de precios

14. **setCloseFactor(uint256 newCloseFactor) external onlyOwner**
    - Parámetros: newCloseFactor (nuevo close factor)
    - Tipo: external onlyOwner - Solo owner
    - Retorna: Nada
    - Propósito: Actualizar el porcentaje máximo liquidable
    - Validación: Debe estar entre 5% y 90%

15. **setLiquidationIncentive(uint256 newIncentive) external onlyOwner**
    - Parámetros: newIncentive (nuevo incentivo)
    - Tipo: external onlyOwner - Solo owner
    - Retorna: Nada
    - Propósito: Actualizar el incentivo para liquidadores
    - Validación: Debe estar entre 100% y 150%

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 6

**¿Por qué necesitamos una factoría?**

La factoría es el cerebro del protocolo:

1. **Gestión centralizada:** Un punto de control para todos los markets.
2. **Creación eficiente:** Deployar nuevos markets sin redeployar toda la lógica.
3. **Coordinación cross-market:** Permite que markets se comuniquen entre sí.
4. **Cálculos globales:** Evaluar la salud de una cuenta a través de múltiples markets.
5. **Gobernanza unificada:** Un solo punto para actualizar parámetros del protocolo.

**¿Por qué usar Clones (minimal proxy pattern)?**

Optimización de gas extrema:

```
Sin Clones:
- Deployar market 1: 3M gas
- Deployar market 2: 3M gas
- Deployar market 3: 3M gas
Total: 9M gas

Con Clones:
- Deployar implementación: 3M gas
- Clonar market 1: 50k gas
- Clonar market 2: 50k gas
- Clonar market 3: 50k gas
Total: 3.15M gas (¡65% ahorro!)
```

Cómo funciona:
- marketImplementation = contrato completo con toda la lógica.
- Cada clone es un proxy tiny que delega llamadas a la implementación.
- Cada clone tiene su propio storage (datos únicos).

**¿Por qué struct MarketConfig?**

Metadatos de cada market:

- **underlyingToken:** Qué token maneja este market.
- **collateralFactor:** Cuánto puedes pedir prestado contra depósitos aquí.
- **reserveFactor:** Qué porcentaje de intereses va al protocolo.
- **interestRateModel:** Qué modelo de tasas usa.
- **isListed:** Si el market está activo en el protocolo.
- **isActive:** Si acepta nuevas operaciones (puede pausarse).

**¿Por qué allMarkets array?**

Iteración y queries:

- Permite obtener todos los markets con getAllMarkets().
- Necesario para calcular getAccountLiquidity() (iterar sobre markets del usuario).
- Útil para frontends que quieren mostrar todos los markets disponibles.

**¿Por qué mapping markets (token → market)?**

Búsqueda eficiente:

```
Usuario quiere depositar USDC
→ getMarketByToken(USDC_ADDRESS)
→ Retorna market de USDC
→ Usuario llama market.deposit()
```

O(1) lookup en lugar de iterar sobre allMarkets.

**¿Por qué accountAssets y accountMembership?**

Gestión de colateral:

- **accountAssets[user]:** Array de markets donde el usuario tiene posiciones.
- **accountMembership[user][market]:** Bool rápido para verificar membresía.

Ejemplo:
```
Alice deposita en market USDC
Alice deposita en market ETH
Alice llama enterMarkets([USDC, ETH])
→ accountAssets[Alice] = [USDC_market, ETH_market]
→ accountMembership[Alice][USDC_market] = true
→ accountMembership[Alice][ETH_market] = true
→ Ahora Alice puede pedir prestado contra ambos
```

**¿Por qué enterMarkets() es necesario?**

Opt-in de colateral:

- No todos los depósitos deben ser colateral automáticamente.
- Usuario puede depositar en market A solo para ganar intereses (sin usarlo como colateral).
- Debe explícitamente "entrar" al market para usarlo como colateral.
- Previene liquidaciones inesperadas.

**¿Por qué exitMarket()?**

Flexibilidad del usuario:

```
Alice tiene:
- 1000 USDC depositados (colateral)
- 500 DAI prestados

Alice quiere retirar USDC pero no puede (es colateral)
Alice repaga los 500 DAI
Alice llama exitMarket(USDC_market)
→ Ahora puede retirar sus USDC
```

Validación crítica: No puede salir si eso lo deja en riesgo de liquidación.

**¿Por qué getAccountLiquidity() es tan importante?**

Función más crítica del protocolo:

```
Calcula:
1. Total colateral valorado en USD (suma de todos los markets)
2. Total deuda valorado en USD (suma de todos los markets)
3. Compara: colateral × collateralFactor vs deuda

Si colateral > deuda: liquidity = exceso, shortfall = 0 (saludable)
Si colateral < deuda: liquidity = 0, shortfall = déficit (liquidable)
```

Usado en:
- Verificar si usuario puede pedir más prestado.
- Verificar si usuario puede retirar colateral.
- Verificar si usuario es liquidable.

**¿Por qué liquidationIncentive?**

Incentivo económico para liquidadores:

```
liquidationIncentive = 108% (10800 basis points)

Liquidador repaga: 100 USDC de deuda
Liquidador recibe: 108 USDC de colateral
Ganancia: 8 USDC
```

Razones:
- **Incentivo:** Hace rentable liquidar posiciones.
- **Bots:** Liquidadores automáticos mantienen el protocolo sano.
- **Velocidad:** Liquidaciones rápidas previenen bad debt.
- **Balance:** No muy alto (sería injusto para borrowers), no muy bajo (nadie liquidaría).

**¿Por qué closeFactor?**

Protección del borrower:

```
closeFactor = 50% (5000 basis points)

Usuario debe: 1000 USDC
Liquidador puede repagar máximo: 500 USDC (50%)
```

Razones:
- **Liquidaciones parciales:** No liquidan todo de una vez.
- **Da oportunidad:** Usuario puede salvar su posición repagando el resto.
- **Previene manipulación:** Evita que liquidadores grandes barran todo.
- **Múltiples liquidadores:** Permite que varios participen.

**¿Por qué liquidateCalculateSeizeTokens()?**

Cálculo preciso de liquidación:

```
Borrower debe 100 USDC en market A
Borrower tiene colateral en market B (ETH)

Precio USDC = $1
Precio ETH = $2000
liquidationIncentive = 108%

Liquidador repaga: 100 USDC
Valor a embargar: 100 × 1.08 = $108
ETH a embargar: $108 / $2000 = 0.054 ETH
```

Usa priceOracle para valoración cross-asset.

**¿Por qué getAccountLiquidityInternal() es internal?**

Reutilización de código:

- getAccountLiquidity() (external) llama a getAccountLiquidityInternal().
- Otras funciones internas también pueden usarla.
- Retorna error code adicional para manejo interno.
- Evita duplicación de lógica compleja.

**¿Por qué setPriceOracle() permite cambiar el oráculo?**

Flexibilidad y upgrades:

- Oráculos pueden fallar o quedar obsoletos.
- Nuevos oráculos mejores pueden aparecer.
- En emergencia, cambiar a oráculo backup.
- onlyOwner previene cambios maliciosos.

**¿Por qué validar rangos en setCloseFactor y setLiquidationIncentive?**

Protección del protocolo:

```
closeFactor = 100%: Liquidaciones completas, muy agresivo
closeFactor = 1%: Liquidaciones inútiles, no protege protocolo
→ Rango razonable: 5-90%

liquidationIncentive = 200%: Liquidadores roban, injusto
liquidationIncentive = 100%: Sin incentivo, nadie liquida
→ Rango razonable: 100-150%
```

**Flujo completo de usuario multi-market:**

```
1. Alice deposita 10 ETH en market ETH
2. Alice deposita 5000 USDC en market USDC
3. Alice llama enterMarkets([ETH_market, USDC_market])
4. Factory calcula: colateral = (10 ETH × $2000 × 75%) + (5000 USDC × $1 × 90%) = $15000 + $4500 = $19500
5. Alice puede pedir prestado hasta $19500
6. Alice pide prestado 10000 DAI del market DAI
7. Factory verifica: $10000 < $19500 ✓ Permitido
8. Precio ETH baja a $1000
9. Nuevo colateral = (10 × $1000 × 75%) + (5000 × $1 × 90%) = $7500 + $4500 = $12000
10. Deuda = $10000
11. $12000 > $10000 pero cerca del límite
12. Si ETH baja más, Alice será liquidable
```

---

## DÍA 7: INTEGRACIÓN Y SISTEMA DE LIQUIDACIÓN CROSS-MARKET

### Objetivo del día
Integrar todos los componentes y añadir funcionalidad de liquidación que funcione entre diferentes markets.

### Modificaciones en LendingMarket.sol:

**Nuevas funciones a AÑADIR:**

1. **liquidateBorrow(address borrower, uint256 repayAmount, address marketCollateral) external nonReentrant**
   - Parámetros: borrower (usuario a liquidar), repayAmount (cantidad a repagar), marketCollateral (market del colateral)
   - Tipo: external nonReentrant - Llamada por liquidadores
   - Retorna: Nada
   - Propósito: Liquidar préstamo de un usuario usando colateral de otro market
   - Validaciones: Verificar con factory que borrower es liquidable
   - Lógica: Repagar deuda, calcular colateral a embargar, transferir colateral

2. **seize(address liquidator, address borrower, uint256 seizeTokens) external nonReentrant**
   - Parámetros: liquidator, borrower, seizeTokens (cantidad de lTokens a embargar)
   - Tipo: external nonReentrant - Solo llamable por otros markets
   - Retorna: Nada
   - Propósito: Transferir lTokens del borrower al liquidator durante liquidación
   - Validación: Solo otro market puede llamar esta función

3. **borrowBalanceCurrent(address account) external returns (uint256)**
   - Parámetros: account (dirección del usuario)
   - Tipo: external - Modifica estado (llama accrueInterest)
   - Retorna: Balance de préstamo actualizado con intereses
   - Propósito: Obtener deuda actual de un usuario

4. **borrowBalanceStored(address account) external view returns (uint256)**
   - Parámetros: account
   - Tipo: external view - Solo lectura
   - Retorna: Balance de préstamo almacenado (sin actualizar)
   - Propósito: Consultar deuda sin gas

5. **supplyBalanceCurrent(address account) external returns (uint256)**
   - Parámetros: account
   - Tipo: external - Modifica estado
   - Retorna: Balance de suministro actualizado con intereses
   - Propósito: Obtener depósitos actuales de un usuario

6. **supplyBalanceStored(address account) external view returns (uint256)**
   - Parámetros: account
   - Tipo: external view - Solo lectura
   - Retorna: Balance de suministro almacenado
   - Propósito: Consultar depósitos sin gas

### Modificaciones en LendingMarketFactory.sol:

**Nuevas funciones a AÑADIR:**

1. **liquidateBorrowAllowed(address marketBorrowed, address marketCollateral, address liquidator, address borrower, uint256 repayAmount) external view returns (uint256)**
   - Parámetros: marketBorrowed, marketCollateral, liquidator, borrower, repayAmount
   - Tipo: external view - Solo lectura
   - Retorna: Código de error (0 = permitido)
   - Propósito: Verificar si una liquidación es válida
   - Validaciones: Borrower debe ser liquidable, repayAmount <= closeFactor × totalBorrow

2. **seizeAllowed(address marketCollateral, address marketBorrowed, address liquidator, address borrower, uint256 seizeTokens) external view returns (uint256)**
   - Parámetros: marketCollateral, marketBorrowed, liquidator, borrower, seizeTokens
   - Tipo: external view - Solo lectura
   - Retorna: Código de error (0 = permitido)
   - Propósito: Verificar si el embargo de colateral es válido
   - Validaciones: Ambos markets deben estar listados

### Archivo nuevo: LiquidationBot.sol (Opcional - Helper para liquidadores)

**Propósito:** Contrato helper que facilita encontrar y ejecutar liquidaciones rentables.

**Funciones:**

1. **findLiquidatableAccounts(address[] calldata accounts) external view returns (address[] memory)**
   - Parámetros: accounts (array de cuentas a verificar)
   - Tipo: external view - Solo lectura
   - Retorna: Array de cuentas liquidables
   - Propósito: Filtrar cuentas que están en riesgo

2. **calculateLiquidationProfit(address borrower, address marketBorrowed, address marketCollateral, uint256 repayAmount) external view returns (uint256)**
   - Parámetros: borrower, marketBorrowed, marketCollateral, repayAmount
   - Tipo: external view - Solo lectura
   - Retorna: Ganancia estimada de la liquidación
   - Propósito: Calcular si una liquidación es rentable

3. **executeLiquidation(address borrower, address marketBorrowed, address marketCollateral, uint256 repayAmount) external**
   - Parámetros: borrower, marketBorrowed, marketCollateral, repayAmount
   - Tipo: external - Ejecuta liquidación
   - Retorna: Nada
   - Propósito: Ejecutar liquidación de forma optimizada

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 7

**¿Por qué necesitamos liquidación cross-market?**

Escenario real que requiere cross-market:

```
Bob deposita 10 ETH en market ETH (colateral)
Bob pide prestado 5000 USDC en market USDC (deuda)
Precio ETH cae de $2000 a $1200
Colateral: 10 ETH × $1200 × 75% = $9000
Deuda: 5000 USDC × $1 = $5000
Ratio: $9000 / $5000 = 180% (aún saludable pero cerca del límite)

Si ETH cae a $1000:
Colateral: 10 ETH × $1000 × 75% = $7500
Deuda: $5000
Ratio: 150% (¡liquidable si threshold es 150%!)

Liquidador debe:
1. Repagar deuda en market USDC
2. Embargar colateral del market ETH
→ Esto es cross-market
```

**¿Por qué liquidateBorrow() necesita marketCollateral como parámetro?**

Flexibilidad del liquidador:

- Borrower puede tener colateral en múltiples markets (ETH, USDC, DAI).
- Liquidador elige qué colateral embargar.
- Típicamente elige el más líquido o el que prefiera.
- Permite estrategias de liquidación optimizadas.

**¿Por qué seize() solo puede ser llamada por otro market?**

Seguridad crítica:

```
Flujo correcto:
1. Liquidador llama marketBorrowed.liquidateBorrow()
2. marketBorrowed valida la liquidación
3. marketBorrowed llama marketCollateral.seize()
4. marketCollateral transfiere lTokens al liquidador

Si seize() fuera pública:
1. Atacante llama directamente marketCollateral.seize()
2. ¡Roba lTokens sin repagar deuda!
```

Solo markets pueden llamar seize(), y solo después de validar con la factoría.

**¿Por qué borrowBalanceCurrent() vs borrowBalanceStored()?**

Dos casos de uso diferentes:

- **borrowBalanceCurrent():** Llama accrueInterest(), retorna deuda con intereses actualizados. Usa en liquidaciones y operaciones críticas.
- **borrowBalanceStored():** Solo lee storage, más barato. Usa en displays o cálculos aproximados.

Mismo patrón para supply balances.

**¿Por qué liquidateBorrowAllowed() en la factoría?**

Validación centralizada:

```
Market no puede saber si borrower es liquidable porque:
- Necesita ver TODOS los markets del usuario
- Necesita calcular colateral total vs deuda total
- Solo la factoría tiene esta vista global

Factory.liquidateBorrowAllowed() verifica:
1. ¿Borrower es liquidable? (shortfall > 0)
2. ¿repayAmount <= closeFactor × totalBorrow?
3. ¿Ambos markets están listados?
```

**¿Por qué seizeAllowed() es necesario?**

Validación adicional:

- Verifica que ambos markets están activos.
- Previene seize de markets deslistados.
- Puede añadir lógica adicional (ej: pausas de emergencia).
- Punto de control centralizado.

**¿Por qué LiquidationBot.sol es opcional?**

Helper para liquidadores:

- No es parte del protocolo core.
- Facilita encontrar oportunidades de liquidación.
- Calcula rentabilidad antes de ejecutar.
- Útil para liquidadores menos sofisticados.
- Bots avanzados pueden implementar su propia lógica.

**¿Por qué findLiquidatableAccounts()?**

Eficiencia para bots:

```
Sin helper:
- Bot debe llamar getAccountLiquidity() para cada cuenta
- Si hay 10,000 cuentas, son 10,000 llamadas
- Muy costoso en gas

Con helper:
- Bot pasa array de cuentas sospechosas
- Helper filtra las liquidables en una llamada
- Retorna solo las que valen la pena
```

**¿Por qué calculateLiquidationProfit()?**

Análisis de rentabilidad:

```
Calcula:
1. Costo: repayAmount en tokens prestados
2. Ganancia: seizeTokens × price × liquidationIncentive
3. Profit = Ganancia - Costo

Si profit > gas costs: ejecutar liquidación
Si profit < gas costs: no vale la pena
```

Previene liquidaciones no rentables.

**Flujo completo de liquidación cross-market:**

```
Estado inicial:
- Alice tiene 5 ETH en market ETH (colateral)
- Alice debe 4000 USDC en market USDC (deuda)
- Precio ETH = $2000, colateralFactor = 75%
- Colateral: 5 × $2000 × 75% = $7500
- Deuda: $4000
- Ratio: 187.5% (saludable)

Precio ETH cae a $1400:
- Colateral: 5 × $1400 × 75% = $5250
- Deuda: $4000
- Ratio: 131% (¡liquidable si threshold es 150%!)

Liquidación:
1. Bob (liquidador) detecta que Alice es liquidable
2. Bob llama marketUSDC.liquidateBorrow(Alice, 2000 USDC, marketETH)
   - closeFactor = 50%, puede repagar máximo 50% de $4000 = $2000
3. marketUSDC verifica con factory.liquidateBorrowAllowed()
   - Factory calcula: Alice tiene shortfall > 0 ✓
   - repayAmount ($2000) <= closeFactor × totalBorrow ($2000) ✓
4. marketUSDC recibe 2000 USDC de Bob
5. marketUSDC reduce deuda de Alice: $4000 → $2000
6. marketUSDC calcula seizeTokens:
   - Valor a embargar: $2000 × 1.08 = $2160
   - ETH a embargar: $2160 / $1400 = 1.543 ETH
7. marketUSDC llama marketETH.seize(Bob, Alice, 1.543 lETH)
8. marketETH verifica con factory.seizeAllowed() ✓
9. marketETH transfiere 1.543 lETH de Alice a Bob
10. Bob ganó: 1.543 ETH × $1400 - $2000 = $2160 - $2000 = $160

Estado final:
- Alice tiene 3.457 ETH (colateral)
- Alice debe 2000 USDC (deuda)
- Ratio mejoró: (3.457 × $1400 × 75%) / $2000 = 181% (más saludable)
- Bob ganó $160 por liquidar
```

**Consideraciones de seguridad:**

1. **Reentrancy:** Ambos liquidateBorrow() y seize() deben ser nonReentrant.
2. **Oracle manipulation:** Usar precios TWAP o múltiples oráculos para prevenir manipulación.
3. **Front-running:** Liquidadores compiten, el que paga más gas gana (esto es esperado).
4. **Partial liquidation:** closeFactor previene liquidaciones totales abusivas.

---

## DÍA 8: SISTEMA DE REWARDS Y GOVERNANCE TOKEN

### Objetivo del día
Añadir un sistema de recompensas para incentivar el uso del protocolo y crear un token de gobernanza.

### Archivo a crear: GovernanceToken.sol

**Herencia:**
- ERC20 de OpenZeppelin
- ERC20Votes de OpenZeppelin (para voting power)
- Ownable de OpenZeppelin

**Variables de estado:**

1. **INITIAL_SUPPLY** - uint256 constant
   - Suministro inicial del token (ej: 100,000,000 tokens)

**Funciones:**

1. **constructor() ERC20("Lending Protocol Token", "LPT") ERC20Permit("Lending Protocol Token")**
   - Propósito: Crear token de gobernanza con capacidad de voting

2. **mint(address to, uint256 amount) external onlyOwner**
   - Parámetros: to, amount
   - Tipo: external onlyOwner
   - Retorna: Nada
   - Propósito: Acuñar nuevos tokens (para rewards)

### Archivo a crear: RewardsDistributor.sol

**Propósito:** Distribuir tokens de gobernanza a usuarios que depositan y piden prestado.

**Variables de estado:**

1. **governanceToken** - GovernanceToken
   - Token que se distribuye como recompensa

2. **factory** - LendingMarketFactory
   - Referencia a la factoría

3. **supplyRewardSpeed** - mapping(address => uint256)
   - Tokens por bloque para suppliers de cada market

4. **borrowRewardSpeed** - mapping(address => uint256)
   - Tokens por bloque para borrowers de cada market

5. **supplyState** - mapping(address => RewardState)
   - Estado de rewards de supply por market

6. **borrowState** - mapping(address => RewardState)
   - Estado de rewards de borrow por market

7. **supplierRewards** - mapping(address => mapping(address => uint256))
   - Rewards acumulados por supplier por market

8. **borrowerRewards** - mapping(address => mapping(address => uint256))
   - Rewards acumulados por borrower por market

**Struct:**

1. **RewardState**
   - index (uint256) - Índice acumulativo de rewards
   - block (uint256) - Último bloque actualizado

**Eventos:**

1. **RewardSpeedUpdated(address indexed market, uint256 newSupplySpeed, uint256 newBorrowSpeed)**
2. **RewardsClaimed(address indexed user, uint256 amount)**
3. **RewardsAccrued(address indexed user, address indexed market, uint256 amount)**

**Funciones:**

1. **setRewardSpeed(address market, uint256 supplySpeed, uint256 borrowSpeed) external onlyOwner**
   - Parámetros: market, supplySpeed (tokens/bloque para suppliers), borrowSpeed (tokens/bloque para borrowers)
   - Tipo: external onlyOwner
   - Retorna: Nada
   - Propósito: Configurar velocidad de distribución de rewards para un market

2. **updateSupplyIndex(address market) public**
   - Parámetros: market
   - Tipo: public
   - Retorna: Nada
   - Propósito: Actualizar el índice de rewards de supply

3. **updateBorrowIndex(address market) public**
   - Parámetros: market
   - Tipo: public
   - Retorna: Nada
   - Propósito: Actualizar el índice de rewards de borrow

4. **distributeSupplierReward(address market, address supplier) public**
   - Parámetros: market, supplier
   - Tipo: public
   - Retorna: Nada
   - Propósito: Calcular y acumular rewards para un supplier

5. **distributeBorrowerReward(address market, address borrower) public**
   - Parámetros: market, borrower
   - Tipo: public
   - Retorna: Nada
   - Propósito: Calcular y acumular rewards para un borrower

6. **claimRewards(address holder) external**
   - Parámetros: holder (usuario que reclama)
   - Tipo: external
   - Retorna: Nada
   - Propósito: Permitir a usuarios reclamar sus rewards acumulados

7. **getUnclaimedRewards(address holder) external view returns (uint256)**
   - Parámetros: holder
   - Tipo: external view
   - Retorna: Cantidad de rewards no reclamados
   - Propósito: Consultar rewards pendientes de un usuario

### Integración con LendingMarket.sol:

**Modificar funciones existentes para llamar al RewardsDistributor:**
- En deposit(): Llamar distributeSupplierReward() después de depositar
- En withdraw(): Llamar distributeSupplierReward() antes de retirar
- En borrow(): Llamar distributeBorrowerReward() después de pedir prestado
- En repay(): Llamar distributeBorrowerReward() antes de repagar

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 8

**¿Por qué necesitamos un token de gobernanza?**

Descentralización y alineación de incentivos:

1. **Gobernanza descentralizada:** Holders votan sobre cambios del protocolo (tasas, collateral factors, etc.).
2. **Alineación de incentivos:** Usuarios del protocolo se convierten en owners.
3. **Distribución de valor:** Usuarios que contribuyen al protocolo reciben ownership.
4. **Competitividad:** Protocolos modernos necesitan tokens para competir (ej: Compound, Aave).

**¿Por qué heredar de ERC20Votes?**

Capacidad de votación on-chain:

- **ERC20Votes:** Extensión de ERC20 que añade voting power.
- **Checkpoints:** Rastrea balances históricos para prevenir double-voting.
- **Delegation:** Usuarios pueden delegar su voting power a otros.
- **Snapshots:** Permite votar basado en balance en un bloque específico.

Ejemplo:
```
Alice tiene 1000 LPT en bloque 100
Propuesta creada en bloque 100
Alice vende 500 LPT en bloque 101
Alice aún puede votar con 1000 LPT (balance en snapshot)
```

**¿Por qué ERC20Permit?**

Mejora de UX:

- Permite aprobar y transferir en una sola transacción.
- Usa firmas off-chain en lugar de transacciones on-chain.
- Ahorra gas y mejora experiencia de usuario.
- Estándar moderno de tokens.

**¿Por qué GovernanceToken.mint() es onlyOwner?**

Control de emisión:

- Solo el protocolo (vía RewardsDistributor) debe poder acuñar.
- Previene inflación descontrolada.
- Eventualmente, ownership se transfiere a governance (DAO).
- Permite distribución controlada de rewards.

**¿Por qué necesitamos RewardsDistributor separado?**

Separación de concerns:

- **GovernanceToken:** Solo maneja el token (ERC20 + voting).
- **RewardsDistributor:** Maneja la lógica de distribución.
- Más modular y fácil de actualizar.
- Permite múltiples distribuidores si es necesario.

**¿Por qué supplyRewardSpeed y borrowRewardSpeed separados?**

Incentivos diferenciados:

```
Market USDC:
- supplyRewardSpeed = 10 LPT/bloque
- borrowRewardSpeed = 15 LPT/bloque

¿Por qué borrowers ganan más?
- Pedir prestado tiene más riesgo (liquidación).
- Incentiva uso del protocolo (más préstamos = más ingresos).
- Balance oferta/demanda.
```

Permite ajustar incentivos por market y por lado (supply vs borrow).

**¿Por qué usar índices para rewards (supplyState, borrowState)?**

Eficiencia de gas (mismo patrón que intereses):

```
Sin índices:
- Cada bloque: actualizar rewards de CADA usuario → O(n) gas
- Imposible con miles de usuarios

Con índices:
- Cada bloque: actualizar UN índice global → O(1) gas
- Cuando usuario interactúa: calcular sus rewards usando su índice personal
```

Matemática:
```
rewardIndex inicial = 0
Después de 1000 bloques con 10 LPT/bloque y 100,000 USDC depositados:
rewardIndex += (1000 bloques × 10 LPT) / 100,000 USDC = 0.1 LPT/USDC

Usuario con 1000 USDC depositados desde el inicio:
rewards = 1000 USDC × 0.1 LPT/USDC = 100 LPT
```

**¿Por qué struct RewardState tiene index y block?**

Rastreo de actualizaciones:

- **index:** Índice acumulativo de rewards por token depositado/prestado.
- **block:** Último bloque donde se actualizó el índice.
- Permite calcular cuántos bloques han pasado y cuántos rewards acumular.

**¿Por qué supplierRewards y borrowerRewards son mappings anidados?**

Rastreo por usuario y por market:

```
supplierRewards[Alice][marketUSDC] = 50 LPT
supplierRewards[Alice][marketETH] = 30 LPT
borrowerRewards[Alice][marketDAI] = 20 LPT

Total rewards de Alice = 50 + 30 + 20 = 100 LPT
```

Permite acumular rewards de múltiples markets antes de reclamar.

**¿Por qué setRewardSpeed() es onlyOwner?**

Control de emisión:

- Determina cuántos tokens se distribuyen.
- Afecta la inflación del token.
- Debe ser decidido por governance, no por usuarios.
- Permite ajustar incentivos según necesidades del protocolo.

**¿Por qué updateSupplyIndex() y updateBorrowIndex() son públicas?**

Transparencia y actualización:

- Cualquiera puede actualizar los índices.
- Bots pueden mantener índices actualizados.
- No hay riesgo de seguridad (solo actualizan matemática).
- Asegura que rewards se acumulen correctamente.

**¿Por qué distributeSupplierReward() y distributeBorrowerReward()?**

Cálculo de rewards personales:

```
1. Actualizar índice global del market
2. Calcular delta: índice actual - índice personal del usuario
3. Rewards = balance del usuario × delta
4. Acumular en supplierRewards[user][market]
5. Actualizar índice personal del usuario
```

Llamadas automáticamente cuando usuario interactúa con el market.

**¿Por qué claimRewards() es separado?**

Flexibilidad del usuario:

- Rewards se acumulan automáticamente.
- Usuario decide cuándo reclamar (optimización de gas).
- Puede acumular rewards de múltiples markets.
- Reclama todo de una vez en lugar de múltiples transacciones.

**¿Por qué getUnclaimedRewards() es view?**

Consulta sin costo:

- Frontends pueden mostrar rewards pendientes.
- Usuarios pueden ver cuánto tienen antes de reclamar.
- No modifica estado, solo calcula.
- Útil para dashboards y analytics.

**¿Por qué integrar con LendingMarket.sol?**

Automatización de distribución:

```
Usuario deposita 1000 USDC:
1. market.deposit(1000)
2. market.accrueInterest()
3. rewardsDistributor.distributeSupplierReward(market, user)
4. Rewards se acumulan automáticamente
5. Usuario no necesita hacer nada extra
```

Experiencia de usuario fluida, rewards pasivos.

**Ejemplo completo de rewards:**

```
Setup:
- Market USDC: supplyRewardSpeed = 10 LPT/bloque
- Alice deposita 10,000 USDC (50% del pool)
- Bob deposita 10,000 USDC (50% del pool)
- Total pool: 20,000 USDC

Bloque 1000:
- supplyIndex = 0
- Alice deposita → su índice personal = 0

Bloque 2000 (1000 bloques después):
- updateSupplyIndex() se llama
- Rewards acumulados: 1000 bloques × 10 LPT = 10,000 LPT
- supplyIndex += 10,000 LPT / 20,000 USDC = 0.5 LPT/USDC
- Bob deposita → distributeSupplierReward(Alice) se llama
- Rewards de Alice: 10,000 USDC × (0.5 - 0) = 5,000 LPT
- Índice personal de Alice = 0.5
- Índice personal de Bob = 0.5

Bloque 3000 (1000 bloques más):
- supplyIndex += 10,000 LPT / 20,000 USDC = 1.0 LPT/USDC total
- Alice reclama rewards:
  - Rewards adicionales: 10,000 × (1.0 - 0.5) = 5,000 LPT
  - Total de Alice: 5,000 + 5,000 = 10,000 LPT
- Bob reclama:
  - Rewards de Bob: 10,000 × (1.0 - 0.5) = 5,000 LPT
```

**Consideraciones de tokenomics:**

- **Emisión total:** Definir cap máximo (ej: 10M LPT).
- **Distribución inicial:** Team, investors, treasury, rewards.
- **Vesting:** Team tokens con vesting para alineación long-term.
- **Decay:** Reducir reward speeds con el tiempo (similar a Bitcoin halving).

---

## DÍA 9: TESTING Y SCRIPTS DE DEPLOYMENT

### Objetivo del día
Crear tests completos y scripts de deployment para el protocolo.

### Archivos a crear en /test:

**1. PriceOracle.t.sol**

Funciones de test:
- testSetPrice() - Verificar que owner puede establecer precios
- testSetPriceFeed() - Verificar configuración de Chainlink feeds
- testGetPrice() - Verificar obtención de precios
- testUnauthorizedSetPrice() - Verificar que no-owner no puede establecer precios
- testBatchGetPrices() - Verificar obtención de múltiples precios

**2. InterestRateModel.t.sol**

Funciones de test:
- testUtilizationRate() - Verificar cálculo de utilización
- testBorrowRateAtZeroUtilization() - Verificar tasa base
- testBorrowRateBeforeKink() - Verificar tasas antes del kink
- testBorrowRateAfterKink() - Verificar tasas después del kink
- testSupplyRate() - Verificar cálculo de tasa de supply

**3. LendingToken.t.sol**

Funciones de test:
- testMintOnlyMarket() - Verificar que solo market puede acuñar
- testBurnOnlyMarket() - Verificar que solo market puede quemar
- testTransfer() - Verificar transferencias normales
- testBalanceOfUnderlying() - Verificar cálculo de balance subyacente

**4. LendingMarket.t.sol**

Funciones de test:
- testDeposit() - Verificar depósito básico
- testWithdraw() - Verificar retiro básico
- testBorrow() - Verificar préstamo básico
- testRepay() - Verificar repago básico
- testAccrueInterest() - Verificar acumulación de intereses
- testExchangeRate() - Verificar cálculo de exchange rate
- testCannotBorrowMoreThanCollateral() - Verificar límites de préstamo
- testCannotWithdrawCollateralInUse() - Verificar protección de colateral

**5. LendingMarketFactory.t.sol**

Funciones de test:
- testCreateMarket() - Verificar creación de market
- testListMarket() - Verificar listado de market
- testEnterMarkets() - Verificar entrada a markets
- testExitMarket() - Verificar salida de market
- testGetAccountLiquidity() - Verificar cálculo de liquidez
- testCannotExitMarketWithBorrow() - Verificar protección al salir

**6. Liquidation.t.sol**

Funciones de test:
- testLiquidation() - Verificar liquidación básica
- testLiquidationIncentive() - Verificar incentivo de liquidación
- testCannotLiquidateHealthyAccount() - Verificar protección de cuentas sanas
- testPartialLiquidation() - Verificar liquidación parcial
- testCrossMarketLiquidation() - Verificar liquidación entre markets

**7. Integration.t.sol**

Funciones de test:
- testFullUserJourney() - Simular journey completo de usuario
- testMultipleMarketsInteraction() - Verificar interacción con múltiples markets
- testRewardsDistribution() - Verificar distribución de rewards
- testComplexLiquidationScenario() - Escenario complejo de liquidación

### Archivos a crear en /script:

**1. DeployPriceOracle.s.sol**

Script para:
- Deployar PriceOracle
- Configurar precios iniciales para tokens comunes (USDC, USDT, DAI, WETH, WBTC)

**2. DeployInterestRateModels.s.sol**

Script para:
- Deployar múltiples InterestRateModels con diferentes parámetros
- Modelo para stablecoins (tasas bajas)
- Modelo para ETH (tasas medias)
- Modelo para tokens volátiles (tasas altas)

**3. DeployFactory.s.sol**

Script para:
- Deployar GovernanceToken
- Deployar RewardsDistributor
- Deployar LendingMarketFactory
- Configurar relaciones entre contratos

**4. CreateMarkets.s.sol**

Script para:
- Crear markets para tokens principales (USDC, USDT, DAI, WETH)
- Configurar collateral factors apropiados
- Listar markets en la factoría
- Configurar reward speeds

**5. SetupProtocol.s.sol**

Script maestro que:
- Ejecuta todos los scripts anteriores en orden
- Verifica que todo esté correctamente configurado
- Imprime resumen de direcciones deployadas

### Configuración de testing:

**Crear archivo: test/utils/TestSetup.sol**

Helper contract con:
- setUp() común para todos los tests
- Funciones helper para crear usuarios de prueba
- Funciones helper para mintear tokens de prueba
- Funciones helper para avanzar bloques/tiempo
- Funciones helper para verificar estados

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 9

**¿Por qué el testing es tan crítico en DeFi?**

Los protocolos DeFi manejan dinero real:

1. **Inmutabilidad:** Una vez deployado, el código no se puede cambiar fácilmente.
2. **Riesgo financiero:** Bugs pueden resultar en pérdida de millones de dólares.
3. **Ataques sofisticados:** Hackers buscan constantemente vulnerabilidades.
4. **Confianza del usuario:** Tests demuestran que el protocolo es seguro.
5. **Auditorías:** Auditores requieren alta cobertura de tests.

**¿Por qué organizar tests por contrato?**

Modularidad y claridad:

- Cada archivo de test se enfoca en un contrato específico.
- Fácil encontrar y ejecutar tests relevantes.
- Permite ejecutar subsets de tests (ej: solo PriceOracle).
- Facilita debugging cuando algo falla.

**¿Por qué testear casos negativos (cannot, unauthorized)?**

Seguridad:

```
testDeposit() → Verifica que funciona correctamente ✓
testUnauthorizedSetPrice() → Verifica que NO funciona cuando no debería ✓
```

Los casos negativos son tan importantes como los positivos:
- Previenen acceso no autorizado.
- Verifican validaciones de input.
- Aseguran que restricciones se cumplan.

**¿Por qué Integration.t.sol es importante?**

Tests de flujo completo:

- Tests unitarios verifican componentes individuales.
- Tests de integración verifican que componentes funcionen juntos.
- Simulan escenarios reales de usuarios.
- Detectan bugs que solo aparecen en interacciones complejas.

Ejemplo:
```
testFullUserJourney():
1. Deployar todo el protocolo
2. Usuario deposita en múltiples markets
3. Usuario entra a markets
4. Usuario pide prestado
5. Precio cambia
6. Usuario es liquidado
7. Verificar que todo funcionó correctamente
```

**¿Por qué scripts de deployment separados?**

Modularidad y reutilización:

- **DeployPriceOracle.s.sol:** Solo deploy del oráculo, reutilizable.
- **DeployFactory.s.sol:** Deploy de la factoría, depende del oráculo.
- **CreateMarkets.s.sol:** Crea markets, depende de la factoría.
- **SetupProtocol.s.sol:** Orquesta todo en orden correcto.

Ventajas:
- Deployar componentes individuales para testing.
- Actualizar componentes sin redeployar todo.
- Diferentes configuraciones para diferentes networks.

**¿Por qué configurar precios iniciales en el script?**

Preparación para testing:

```
DeployPriceOracle.s.sol:
- Deploy PriceOracle
- setPrice(USDC, $1.00)
- setPrice(USDT, $1.00)
- setPrice(DAI, $1.00)
- setPrice(WETH, $2000.00)
- setPrice(WBTC, $40000.00)
```

Permite testing inmediato sin configuración manual.

**¿Por qué múltiples InterestRateModels?**

Diferentes activos, diferentes riesgos:

```
Stablecoins (USDC, USDT, DAI):
- Bajo riesgo, alta liquidez
- baseRate = 0%, multiplier = 5%, jumpMultiplier = 109%, kink = 80%

ETH:
- Riesgo medio, buena liquidez
- baseRate = 2%, multiplier = 10%, jumpMultiplier = 300%, kink = 80%

Tokens volátiles (altcoins):
- Alto riesgo, baja liquidez
- baseRate = 5%, multiplier = 20%, jumpMultiplier = 500%, kink = 70%
```

**¿Por qué TestSetup.sol como helper?**

Evitar duplicación de código:

```
Sin TestSetup:
- Cada test file repite: deploy contracts, create users, mint tokens
- 100+ líneas de setup duplicadas

Con TestSetup:
- setUp() común en TestSetup.sol
- Cada test hereda de TestSetup
- Tests se enfocan en lógica, no en setup
```

Funciones helper típicas:
```
createUser(string name) → Crea usuario con ETH y tokens
mintTokens(address user, address token, uint256 amount)
advanceBlocks(uint256 blocks) → Simula paso del tiempo
assertApproxEq(uint256 a, uint256 b, uint256 tolerance) → Compara con tolerancia
```

**¿Por qué testear edge cases específicos?**

Prevención de bugs sutiles:

- **testBorrowRateAtZeroUtilization:** ¿Qué pasa cuando nadie pide prestado?
- **testBorrowRateAfterKink:** ¿Tasas explotan correctamente en alta utilización?
- **testCannotWithdrawCollateralInUse:** ¿Previene retiros peligrosos?
- **testPartialLiquidation:** ¿closeFactor se respeta?

Estos son casos donde bugs típicamente se esconden.

**¿Por qué testComplexLiquidationScenario()?**

Escenarios del mundo real:

```
Escenario complejo:
1. Alice deposita en 3 markets diferentes
2. Alice pide prestado de 2 markets
3. Precios de múltiples assets cambian
4. Alice se vuelve liquidable
5. Bob liquida parcialmente
6. Verificar: cantidades correctas, eventos emitidos, estado final correcto
```

Simula situaciones reales que pueden causar bugs.

**¿Por qué verificar eventos en tests?**

Validación completa:

```
function testDeposit() public {
    vm.expectEmit(true, true, true, true);
    emit Deposit(alice, 1000e6, 1000e6);
    
    market.deposit(1000e6);
    
    // Verifica que el evento se emitió con parámetros correctos
}
```

Eventos son críticos para:
- Frontends (rastrear transacciones).
- Indexers (construir bases de datos).
- Auditoría (verificar que acciones se registran).

**¿Por qué SetupProtocol.s.sol imprime resumen?**

Documentación del deployment:

```
Deployment Summary:
====================
PriceOracle: 0x1234...
InterestRateModel (Stablecoin): 0x5678...
InterestRateModel (ETH): 0x9abc...
LendingMarketFactory: 0xdef0...
GovernanceToken: 0x1111...
RewardsDistributor: 0x2222...

Markets:
- USDC Market: 0x3333...
- USDT Market: 0x4444...
- DAI Market: 0x5555...
- WETH Market: 0x6666...
```

Permite:
- Verificar deployment correcto.
- Guardar direcciones para configuración.
- Compartir con equipo y usuarios.

**Mejores prácticas de testing:**

1. **AAA Pattern:** Arrange (setup), Act (execute), Assert (verify).
2. **Test isolation:** Cada test debe ser independiente.
3. **Descriptive names:** testCannotBorrowMoreThanCollateral (claro).
4. **Coverage:** Apuntar a >90% line coverage, >80% branch coverage.
5. **Fuzz testing:** Usar Foundry's fuzzing para inputs aleatorios.
6. **Invariant testing:** Verificar invariantes del protocolo (ej: totalBorrows <= totalSupply).

**Comandos útiles de Foundry:**

```
forge test → Ejecutar todos los tests
forge test --match-test testDeposit → Test específico
forge test --match-contract PriceOracle → Contrato específico
forge test -vvv → Verbose (mostrar traces)
forge coverage → Generar reporte de cobertura
forge snapshot → Gas snapshot (optimización)
```

---

## DÍA 10: DOCUMENTACIÓN, AUDITORÍA Y OPTIMIZACIONES

### Objetivo del día
Documentar el protocolo, realizar optimizaciones de gas y preparar para auditoría.

### 1. Documentación (README.md actualizado)

**Secciones a incluir:**

**Introducción**
- Descripción del protocolo
- Características principales
- Arquitectura general

**Contratos principales**
- LendingMarketFactory: Descripción y funciones clave
- LendingMarket: Descripción y funciones clave
- PriceOracle: Descripción y funciones clave
- InterestRateModel: Descripción y funciones clave
- RewardsDistributor: Descripción y funciones clave

**Flujos de usuario**
- Cómo depositar y ganar intereses
- Cómo pedir prestado
- Cómo repagar préstamos
- Cómo liquidar posiciones
- Cómo reclamar rewards

**Deployment**
- Instrucciones paso a paso
- Configuración de networks
- Variables de entorno necesarias

**Testing**
- Cómo ejecutar tests
- Cobertura de tests
- Escenarios cubiertos

**Seguridad**
- Medidas de seguridad implementadas
- Consideraciones importantes
- Recomendaciones para usuarios

### 2. Optimizaciones de gas

**En LendingMarket.sol:**

1. **Usar unchecked para operaciones seguras**
   - En loops donde no hay riesgo de overflow
   - En cálculos donde ya se verificó que no hay underflow

2. **Optimizar storage reads**
   - Cachear variables de storage en memory cuando se usan múltiples veces
   - Ejemplo: uint256 _totalBorrows = totalBorrows; (usar _totalBorrows en la función)

3. **Usar custom errors en lugar de require strings**
   - Definir errors personalizados: error InsufficientBalance();
   - Reemplazar: require(balance >= amount, "Insufficient balance");
   - Por: if (balance < amount) revert InsufficientBalance();

4. **Optimizar loops**
   - Evitar storage writes en loops cuando sea posible
   - Usar ++i en lugar de i++ en loops

5. **Packed storage**
   - Agrupar variables pequeñas (uint128, address, bool) en el mismo slot
   - Ejemplo: struct User { uint128 supplied; uint128 borrowed; bool isActive; }

**En LendingMarketFactory.sol:**

1. **Usar minimal proxy (Clones) para markets**
   - Ya implementado, pero verificar que funcione correctamente

2. **Batch operations**
   - Permitir operaciones en batch donde tenga sentido
   - Ejemplo: enterMarkets() ya lo hace

3. **View functions optimization**
   - Asegurar que funciones view no hagan cálculos innecesarios
   - Cachear resultados cuando sea apropiado

### 3. Checklist de seguridad

**Verificar en todos los contratos:**

1. **Reentrancy protection**
   - Todas las funciones que transfieren tokens deben tener nonReentrant
   - Verificar patrón checks-effects-interactions

2. **Access control**
   - Verificar que funciones admin tengan onlyOwner
   - Verificar que funciones de market solo sean llamables por factory cuando corresponda

3. **Input validation**
   - Verificar que todos los inputs sean validados
   - Verificar que addresses no sean address(0)
   - Verificar que amounts sean > 0 cuando corresponda

4. **Integer overflow/underflow**
   - Usar SafeMath o Solidity 0.8+ (ya incluido)
   - Verificar que no haya casos edge de overflow en cálculos complejos

5. **Oracle manipulation**
   - Implementar protección contra manipulación de precios
   - Considerar usar TWAP o múltiples oráculos

6. **Flash loan attacks**
   - Verificar que accrueInterest() se llame antes de operaciones críticas
   - Verificar que no se puedan manipular tasas con flash loans

7. **Liquidation protection**
   - Verificar que liquidaciones solo ocurran cuando corresponda
   - Verificar que close factor se respete
   - Verificar que incentivo de liquidación sea razonable

### 4. Archivo a crear: SECURITY.md

**Contenido:**

**Medidas de seguridad implementadas**
- ReentrancyGuard en todas las funciones críticas
- Pausable para emergencias
- Access control con Ownable
- SafeERC20 para transferencias seguras
- Validación exhaustiva de inputs

**Riesgos conocidos**
- Dependencia de oráculos externos
- Riesgo de liquidación en mercados volátiles
- Riesgo de smart contract (bugs no descubiertos)

**Proceso de auditoría**
- Tests automatizados con alta cobertura
- Revisión manual de código
- Auditoría externa recomendada antes de mainnet

**Reporte de vulnerabilidades**
- Cómo reportar bugs de seguridad
- Programa de bug bounty (si aplica)

### 5. Archivo a crear: GAS_OPTIMIZATION.md

**Contenido:**

**Optimizaciones implementadas**
- Lista de todas las optimizaciones de gas realizadas
- Comparación de costos antes/después

**Costos estimados**
- Costo de deployment de cada contrato
- Costo de operaciones comunes (deposit, withdraw, borrow, repay)
- Costo de liquidaciones

**Recomendaciones para usuarios**
- Mejores prácticas para minimizar gas
- Cuándo usar funciones batch

### 6. Mejoras adicionales opcionales

**Si hay tiempo, considerar añadir:**

1. **Flash loans**
   - Función flashLoan() en LendingMarket
   - Interface IFlashLoanReceiver
   - Fee por flash loan (0.09%)

2. **Governance**
   - Contrato Governor usando GovernanceToken
   - Timelock para cambios críticos
   - Propuestas y votaciones on-chain

3. **Frontend helpers**
   - Contrato Lens para queries eficientes
   - Funciones para obtener datos de múltiples markets en una llamada
   - Cálculos de APY y métricas

4. **Multi-sig admin**
   - Reemplazar Ownable por multi-sig
   - Usar Gnosis Safe o similar

### EXPLICACIÓN Y FUNDAMENTOS DEL DÍA 10

**¿Por qué la documentación es tan importante?**

La documentación es el puente entre el código y los usuarios:

1. **Onboarding:** Nuevos desarrolladores pueden entender el protocolo rápidamente.
2. **Usuarios:** Entienden cómo usar el protocolo de forma segura.
3. **Auditores:** Pueden revisar el código con contexto completo.
4. **Marketing:** Demuestra profesionalismo y transparencia.
5. **Mantenimiento:** Facilita futuras actualizaciones y debugging.

**¿Por qué usar custom errors en lugar de require strings?**

Optimización de gas significativa:

```
Antes (require con string):
require(balance >= amount, "Insufficient balance");
→ Gas: ~50 bytes de string almacenados en bytecode
→ Costo: ~2400 gas adicional

Después (custom error):
error InsufficientBalance();
if (balance < amount) revert InsufficientBalance();
→ Gas: Solo 4 bytes (selector de error)
→ Costo: ~200 gas
→ Ahorro: ~2200 gas por error
```

En un contrato con 20 requires, esto ahorra ~44,000 gas en deployment.

**¿Por qué cachear variables de storage?**

Storage reads son caros:

```
Ineficiente:
function calculate() public {
    uint256 result = totalBorrows * 2;  // SLOAD: 2100 gas
    result += totalBorrows * 3;          // SLOAD: 2100 gas
    result += totalBorrows * 4;          // SLOAD: 2100 gas
    // Total: 6300 gas en SLOADs
}

Eficiente:
function calculate() public {
    uint256 _totalBorrows = totalBorrows;  // SLOAD: 2100 gas
    uint256 result = _totalBorrows * 2;    // MLOAD: 3 gas
    result += _totalBorrows * 3;           // MLOAD: 3 gas
    result += _totalBorrows * 4;           // MLOAD: 3 gas
    // Total: 2109 gas
    // Ahorro: 4191 gas (66%)
}
```

**¿Por qué usar unchecked para operaciones seguras?**

Solidity 0.8+ tiene overflow protection automática, pero tiene costo:

```
Checked (default):
for (uint256 i = 0; i < 100; i++) {  // Cada i++ verifica overflow
    // Gas: ~30 extra por iteración
}
// Total overhead: 3000 gas

Unchecked (cuando es seguro):
for (uint256 i = 0; i < 100;) {
    // código...
    unchecked { ++i; }  // No verifica overflow (sabemos que i < 100)
}
// Ahorro: 3000 gas
```

Solo usar unchecked cuando estés 100% seguro que no hay riesgo de overflow.

**¿Por qué packed storage?**

Variables pequeñas pueden compartir un slot de storage:

```
Ineficiente (3 slots = 3 SSTOREs):
uint256 supplied;     // Slot 0
uint256 borrowed;     // Slot 1
bool isActive;        // Slot 2
// Costo: 3 × 20,000 gas = 60,000 gas

Eficiente (1 slot = 1 SSTORE):
uint128 supplied;     // Slot 0 (primeros 128 bits)
uint128 borrowed;     // Slot 0 (últimos 128 bits)
bool isActive;        // Slot 1 (packed con otros bools)
// Costo: 1 × 20,000 gas = 20,000 gas
// Ahorro: 40,000 gas (67%)
```

Limitación: uint128 max = 3.4 × 10^38 (suficiente para la mayoría de casos).

**¿Por qué usar ++i en lugar de i++?**

Pequeña optimización:

```
i++:  // Post-increment
1. Guardar valor actual en temp
2. Incrementar i
3. Retornar temp
→ Gas: ~5 extra

++i:  // Pre-increment
1. Incrementar i
2. Retornar i
→ Gas: ~5 menos
```

En loops con 1000 iteraciones, ahorra 5000 gas.

**¿Por qué usar Clones (minimal proxy)?**

Ya explicado en Día 6, pero crítico para gas:

```
Deployar 10 markets sin Clones:
10 × 3M gas = 30M gas
A $50/ETH y 50 gwei: $7,500

Deployar 10 markets con Clones:
1 × 3M (implementación) + 10 × 50k (clones) = 3.5M gas
A $50/ETH y 50 gwei: $875
Ahorro: $6,625 (88%)
```

**¿Por qué verificar reentrancy?**

Uno de los ataques más comunes en DeFi:

```
Vulnerable:
function withdraw(uint256 amount) external {
    uint256 balance = balances[msg.sender];
    require(balance >= amount);
    
    token.transfer(msg.sender, amount);  // ← Llamada externa
    balances[msg.sender] -= amount;      // ← Estado actualizado DESPUÉS
}

Ataque:
1. Atacante llama withdraw(100)
2. En token.transfer(), atacante recibe callback
3. Atacante llama withdraw(100) de nuevo
4. balance aún es 100 (no se actualizó)
5. Atacante retira 100 otra vez
6. Repite hasta drenar el contrato

Protección:
function withdraw(uint256 amount) external nonReentrant {
    uint256 balance = balances[msg.sender];
    require(balance >= amount);
    
    balances[msg.sender] -= amount;      // ← Estado actualizado PRIMERO
    token.transfer(msg.sender, amount);  // ← Llamada externa DESPUÉS
}
```

Patrón checks-effects-interactions + nonReentrant = seguridad.

**¿Por qué protección contra oracle manipulation?**

Oráculos son punto crítico de ataque:

```
Ataque de manipulación:
1. Atacante usa flash loan para comprar mucho ETH en Uniswap
2. Precio de ETH en Uniswap sube artificialmente
3. Protocolo usa precio de Uniswap
4. Atacante deposita ETH sobrevalorado como colateral
5. Atacante pide prestado máximo
6. Atacante vende ETH, precio vuelve a normal
7. Protocolo queda con bad debt

Protecciones:
1. TWAP (Time-Weighted Average Price): Promedio de múltiples bloques
2. Múltiples oráculos: Chainlink + Uniswap, usar mediana
3. Circuit breakers: Rechazar cambios de precio > 10% por bloque
4. Delay: Usar precio de bloque anterior, no actual
```

**¿Por qué SECURITY.md es importante?**

Transparencia y responsabilidad:

- Documenta medidas de seguridad implementadas.
- Reconoce riesgos conocidos (honestidad).
- Proporciona canal para reportar vulnerabilidades.
- Demuestra que seguridad es prioridad.
- Requerido por auditores profesionales.

**¿Por qué GAS_OPTIMIZATION.md?**

Competitividad:

- Usuarios prefieren protocolos más baratos.
- Documenta optimizaciones realizadas.
- Justifica decisiones de diseño.
- Útil para otros desarrolladores.
- Marketing: "50% más barato que Compound".

**¿Por qué considerar flash loans como mejora?**

Utilidad y competitividad:

```
Casos de uso de flash loans:
1. Arbitraje: Comprar barato en DEX A, vender caro en DEX B
2. Refinanciamiento: Mover deuda de protocolo A a protocolo B
3. Liquidaciones: Liquidar sin capital inicial
4. Collateral swap: Cambiar tipo de colateral sin repagar

Implementación:
function flashLoan(uint256 amount, address receiver) external {
    uint256 balanceBefore = token.balanceOf(address(this));
    
    token.transfer(receiver, amount);
    IFlashLoanReceiver(receiver).executeOperation(amount);
    
    uint256 balanceAfter = token.balanceOf(address(this));
    require(balanceAfter >= balanceBefore + fee);
}
```

Fee típico: 0.09% (9 basis points).

**¿Por qué governance on-chain?**

Descentralización verdadera:

```
Sin governance:
- Owner controla todo (centralizado)
- Riesgo de rug pull
- Usuarios no tienen voz

Con governance:
- Token holders votan propuestas
- Timelock previene cambios instantáneos
- Transparencia total
- Verdadera descentralización

Ejemplo de propuesta:
1. Alice propone: "Reducir collateralFactor de ETH de 75% a 70%"
2. Período de votación: 3 días
3. Token holders votan (1 token = 1 voto)
4. Si >50% vota a favor: propuesta pasa
5. Timelock: 2 días antes de ejecución
6. Después de timelock: propuesta se ejecuta automáticamente
```

**¿Por qué Lens contract como mejora?**

Optimización de queries:

```
Sin Lens:
Frontend necesita:
- getAllMarkets() → 1 llamada
- Para cada market:
  - getMarketInfo() → N llamadas
  - getUserPosition(user) → N llamadas
Total: 1 + 2N llamadas

Con Lens:
- getAllMarketsWithUserData(user) → 1 llamada
Total: 1 llamada
Ahorro: 2N - 1 llamadas (99% para 50 markets)
```

Lens contract agrupa múltiples queries en una sola llamada.

**¿Por qué multi-sig admin?**

Seguridad adicional:

```
Ownable (1 clave privada):
- Si se hackea: protocolo comprometido
- Si se pierde: protocolo bloqueado
- Riesgo: Alto

Multi-sig (ej: 3 de 5):
- Requiere 3 de 5 firmas para ejecutar
- Hackear 3 claves es mucho más difícil
- Perder 2 claves no bloquea el protocolo
- Riesgo: Bajo

Gnosis Safe:
- Estándar de industria
- Interface fácil de usar
- Auditado y probado
- Soporta timelock
```

**Checklist final antes de mainnet:**

1. ✓ Tests con >90% coverage
2. ✓ Auditoría profesional completada
3. ✓ Todos los issues de auditoría resueltos
4. ✓ Bug bounty program activo
5. ✓ Documentación completa
6. ✓ Deployment en testnet exitoso
7. ✓ Testing con usuarios reales en testnet
8. ✓ Multi-sig configurado
9. ✓ Timelock configurado
10. ✓ Plan de respuesta a incidentes
11. ✓ Seguro de protocolo (opcional pero recomendado)
12. ✓ Límites de depósito iniciales (ej: $1M max)

**Recursos para auditoría:**

- **Trail of Bits:** Top tier, muy caro ($50k-$200k)
- **OpenZeppelin:** Excelente reputación ($30k-$100k)
- **Consensys Diligence:** Muy buenos ($30k-$100k)
- **Code4rena:** Competitivo, más barato ($10k-$50k)
- **Sherlock:** Asegurado, innovador ($15k-$60k)

**Métricas de éxito post-launch:**

- TVL (Total Value Locked): Cuánto dinero hay depositado
- Utilization Rate: Qué porcentaje está siendo prestado
- APY competitivo: Comparar con Compound, Aave
- Número de usuarios activos
- Volumen de liquidaciones (bajo = bueno)
- Bad debt (debe ser 0 o cercano a 0)

---

## RESUMEN DEL PLAN COMPLETO

**Día 1:** Interfaces y estructuras base (ILendingMarket.sol)

**Día 2:** Oracle de precios (PriceOracle.sol)

**Día 3:** Modelo de tasas de interés (InterestRateModel.sol)

**Día 4:** Token de lending (LendingToken.sol)

**Día 5:** Transformar LendingProtocol.sol en LendingMarket.sol (modificaciones extensas)

**Día 6:** Contrato factoría (LendingMarketFactory.sol)

**Día 7:** Sistema de liquidación cross-market (modificaciones e integraciones)

**Día 8:** Sistema de rewards y governance token (GovernanceToken.sol, RewardsDistributor.sol)

**Día 9:** Testing completo y scripts de deployment

**Día 10:** Documentación, optimizaciones y preparación para auditoría

---

## NOTAS IMPORTANTES

**Sobre el desarrollo:**
- Cada día construye sobre el anterior, así que es importante completar cada día antes de pasar al siguiente
- Los nombres de funciones y variables están en inglés siguiendo las mejores prácticas de Solidity
- Todos los contratos usan Solidity ^0.8.20 para aprovechar protección contra overflow
- Se usa OpenZeppelin para componentes estándar (seguridad probada)

**Sobre testing:**
- Es crítico testear cada contrato a medida que se desarrolla
- Usar Foundry para tests (forge test)
- Apuntar a >90% de cobertura de código

**Sobre deployment:**
- Primero deployar en testnet (Sepolia o Goerli)
- Verificar todos los contratos en Etherscan
- Hacer testing exhaustivo antes de mainnet

**Sobre seguridad:**
- NUNCA deployar a mainnet sin auditoría profesional
- Empezar con límites bajos de depósito
- Tener plan de respuesta a incidentes

**Recursos útiles:**
- Documentación de Compound V2 (arquitectura similar)
- Documentación de Aave (para ideas avanzadas)
- OpenZeppelin Contracts (para componentes seguros)
- Foundry Book (para testing)

---

Este plan te guiará paso a paso en la creación de un protocolo completo de lending and borrowing con arquitectura de factoría. Cada día tiene tareas específicas y claras que puedes implementar de forma incremental. ¡Buena suerte con el desarrollo!
