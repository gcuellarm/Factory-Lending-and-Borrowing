# 🏦 Factory Lending & Borrowing Protocol

## 📌 Overview

Factory Lending & Borrowing is a modular DeFi lending protocol inspired by Compound-style architectures.

The system allows users to:

- Deposit ERC20 tokens and earn interest
- Borrow assets against collateral
- Liquidate undercollateralized positions
- Earn governance token rewards
- Participate in on-chain governance

The protocol is designed with a **Factory pattern**, enabling the creation of isolated lending markets for different assets while maintaining centralized risk management and liquidity checks.

It includes:

- Interest rate modeling
- Cross-market collateral evaluation
- Liquidation mechanics
- Reward distribution system
- Governance token with voting power
- Optional liquidation bot helper

---

# 🧱 Architecture Overview

The protocol is divided into the following main components:
```text
Factory
├── Lending Markets (clones)
│   ├── LendingToken (lToken)
│   ├── Interest accrual
│   ├── Borrow / Repay
│   └── Liquidation logic
│
├── Price Oracle
├── Interest Rate Model
├── Rewards Distributor
└── Governance Token
```

---

# 📂 Smart Contracts Breakdown

## 🏭 LendingMarketFactory.sol

### Role
Acts as the central controller (Comptroller-style contract).

### Responsibilities

- Deploy new LendingMarket clones
- Deploy corresponding LendingTokens
- Manage market configuration
- Track user market membership
- Perform cross-market liquidity checks
- Validate liquidations
- Calculate seize amounts
- Store global protocol parameters:
  - `closeFactor`
  - `liquidationIncentive`
  - `rewardsDistributor`
  - `priceOracle`

### Key Features

- Uses EIP-1167 minimal proxy pattern (`Clones`)
- Cross-market collateral evaluation
- Hypothetical liquidity checks for borrow/withdraw validation
- Comptroller-style error codes for liquidation validation

---

## 🏦 LendingMarket.sol

### Role
Handles all core lending operations for a single asset.

Each market manages one ERC20 underlying token.

### Core Responsibilities

- Deposit underlying tokens
- Mint lTokens
- Withdraw underlying
- Borrow
- Repay
- Accrue interest
- Manage reserves
- Execute cross-market liquidations
- Track user principal and interest indexes

### Key Concepts

#### 🔁 Interest Accrual

The protocol uses index-based interest accounting:

- `borrowIndex`
- `supplyIndex`

Interest is accrued per block using the `InterestRateModel`.

#### 💰 Exchange Rate
exchangeRate = (cash + totalBorrows - reserves) / totalSupply
#### 🧮 User Accounting

Each user tracks:

- `suppliedAmount`
- `borrowedAmount`
- `supplyIndex`
- `borrowIndex`

#### ⚖️ Liquidation

Liquidations are cross-market:

1. Liquidator repays debt in market A
2. Protocol calculates seize amount in market B
3. lTokens are transferred from borrower to liquidator

---

## 🪙 LendingToken.sol

### Role
Interest-bearing ERC20 token (cToken-style).

### Responsibilities

- Represents deposited position
- Minted on deposit
- Burned on withdraw
- Stores exchange rate relationship
- Only callable by its associated LendingMarket

---

## 📈 InterestRateModel.sol

### Role
Defines the borrowing and supply rates.

### Model Type
Jump Rate Model with kink.

### Parameters

- `baseRate`
- `multiplier`
- `jumpMultiplier`
- `kink`

### Behavior

- Below kink → linear growth
- Above kink → steeper growth
- Supply rate derived from borrow rate and reserve factor

---

## 🔮 PriceOracle.sol

### Role
Provides asset prices in USD (1e8 precision).

### Features

- Manual price setting (for testing)
- Optional Chainlink feed integration
- Fallback logic
- Batch price retrieval
- Price in ETH conversion

Used by Factory to compute:

- Collateral value
- Borrow value
- Liquidation thresholds

---

## 🗳 GovernanceToken.sol

### Role
ERC20Votes-based governance token.

### Features

- ERC20Permit support
- On-chain vote delegation
- Snapshot voting power
- Mintable by owner (RewardsDistributor)

Used for:

- Governance proposals (future extension)
- Incentive rewards distribution

---

## 🎁 RewardsDistributor.sol

### Role
Distributes governance token rewards to:

- Suppliers
- Borrowers

### Mechanism

Uses index-based accounting similar to Compound’s COMP distribution model.

Per market:

- `supplyRewardSpeed`
- `borrowRewardSpeed`
- `supplyState`
- `borrowState`

Per user:

- `supplierIndex`
- `borrowerIndex`
- `supplierRewards`
- `borrowerRewards`

### Flow

1. Market action triggers `distributeSupplierReward` or `distributeBorrowerReward`
2. User’s accrued rewards are updated
3. User calls `claimRewards()`
4. Governance tokens are minted

Rewards logic is wrapped in `try/catch` inside LendingMarket to prevent protocol breakage.

---

## 🤖 LiquidationBot.sol

### Role
Helper contract for liquidators.

### Responsibilities

- Scan accounts for liquidation opportunities
- Estimate liquidation profitability
- Execute liquidation transactions

Optional utility for automation or off-chain bots.

---

# 🔁 Core Protocol Flow

### Deposit

1. User approves token
2. Calls `deposit`
3. Underlying transferred
4. lTokens minted
5. Rewards updated

### Borrow

1. Factory checks hypothetical liquidity
2. Debt recorded
3. Underlying transferred
4. Rewards updated

### Repay

1. Debt reduced
2. Rewards updated

### Withdraw

1. Hypothetical liquidity check
2. lTokens burned
3. Underlying returned

### Liquidation

1. Borrower enters shortfall
2. Liquidator repays up to `closeFactor`
3. Factory calculates seize amount
4. Collateral market transfers lTokens

---

# 🧪 Testing

The project includes extensive Foundry test coverage:

- Oracle validation
- Interest rate model
- Lending flows
- Cross-market collateral checks
- Liquidation paths
- Governance token voting
- Reward distribution
- Failure and revert paths

Run:

```bash
forge test
forge coverage --ir-minimum
```

---
### ⚙️ Design Decisions

- Modular factory architecture
- Index-based accounting (gas efficient)
- Cross-market risk engine
- Comptroller-style validation
- try/catch around reward distribution
- ERC20Votes for governance readiness

### 🚀 Future Improvements

- Governance proposals & timelock
- Dynamic risk parameters
- Frontend integration
- Advanced liquidation incentives
- Emission schedule control
- Upgradeable governance

### 📚 Inspiration
Inspired by:

- Compound V2 architecture
- Comptroller pattern
- Index-based interest accounting
- COMP distribution model
