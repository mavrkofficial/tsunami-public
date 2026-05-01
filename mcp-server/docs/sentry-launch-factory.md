# Sentry Launch Factory

## Overview

The Sentry Launch Factory is a token launchpad contract deployed on Ink that enables anyone to deploy a fully tradable ERC-20 token with a single transaction. It is designed to be the most capital-efficient way to create a low-cap token with immediate on-chain liquidity — no seed capital required from the creator, no manual pool setup, no multi-step process.

When a creator launches a token through Sentry, the factory atomically:

1. Deploys a new ERC-20 token contract
2. Creates a Tsunami V3 concentrated liquidity pool
3. Mints a single-sided LP position at a 1% fee tier
4. Locks the LP NFT permanently (in the factory or in the Citadel LP Locker)
5. Emits indexable events for frontends and analytics

The entire launch happens in one transaction. The resulting token is immediately tradable on Tsunami V3 with locked liquidity that can never be rugged.

---

## Why Sentry Is the Most Capital-Efficient Launch Method

### No Seed Liquidity Required

Traditional token launches require the creator to deposit both sides of a liquidity pair — the new token plus a base asset like ETH. This means creators need to put up real capital just to make their token tradable. Sentry eliminates this entirely.

The factory uses **single-sided liquidity provisioning**, a feature of concentrated liquidity AMMs. Because Tsunami V3 allows positions to be opened at price ranges that are entirely above or below the current tick, the factory can deposit 100% of the new token's supply into one side of the pool without any base token. The market forms naturally as the first buyers swap base tokens into the pool, moving the price into the LP's range and creating a two-sided market organically.

### Ink L2 Economics

Ink is an Optimism-based L2 where transaction costs are a fraction of a cent. This means the gas overhead of deploying a token, creating a pool, minting an LP position, and locking the NFT — all in one transaction — costs effectively nothing. On Ethereum mainnet, this same atomic launch would cost hundreds of dollars in gas. On Ink, it's practically free.

This cost structure makes micro-cap token launches economically viable for the first time. Creators can launch a token with zero capital outlay and near-zero gas cost, and the token is immediately tradable with provably locked liquidity.

### Concentrated Liquidity Efficiency

Unlike constant-product AMMs (Uniswap V2 style) where liquidity is spread across the entire price curve from 0 to infinity, Tsunami V3's concentrated liquidity means the launched token's liquidity is concentrated in a specific price range determined by the pool manager. This provides:

- **Deeper liquidity at relevant prices** — capital is not wasted at prices that will never be reached
- **Better execution for traders** — less slippage per dollar of liquidity
- **Higher fee generation for the LP** — more trades occur in the active range

---

## How a Launch Works

### Step 1: Token Deployment

The factory deploys a new `SentryTokenStandard` contract — a minimal ERC-20 with the following properties:

| Property | Value |
|---|---|
| **Total Supply** | 1,000,000,000 (1 billion) tokens |
| **Decimals** | 18 |
| **Ownership** | Renounced at deployment (owner set to `0x...dEaD`) |
| **Meta-Transactions** | ERC-2771 support via Gelato trusted forwarder |
| **Minting** | None — fixed supply, no mint function |
| **Burning** | None — no burn function |

The entire supply is minted to the factory contract at deployment. Ownership is immediately and irrevocably renounced by setting the owner to the dead address, making the token immutable from the moment it exists.

### Step 2: Pool Manager Consultation

The factory supports multiple base tokens (e.g., WETH), each with its own **pool manager** contract. The pool manager is responsible for calculating the mint parameters:

- `sqrtPriceX96` — the initial price of the pool
- `tickLower` / `tickUpper` — the concentrated liquidity range
- `amount0Desired` / `amount1Desired` — how much of each token to deposit
- `amount0Min` / `amount1Min` — slippage protection

Different base tokens can have different pool managers with different pricing strategies. The pool manager's logic is proprietary and determines the initial market cap and liquidity profile of the launched token.

### Step 3: Pool Creation

The factory calls `createAndInitializePoolIfNecessary` on the Tsunami V3 Position Manager to deploy a new pool. All Sentry launches use the **1% fee tier** (10,000 bps, tick spacing 200). The 1% fee tier was chosen because:

- Newly launched tokens experience high volatility
- Higher fees protect the locked LP from impermanent loss
- 1% fee income makes the locked liquidity self-sustaining
- It matches the expected trading patterns for micro-cap tokens

### Step 4: LP Position Minting

The factory mints a concentrated liquidity position using the parameters from the pool manager. Because this is a single-sided deposit (100% new token, 0% base token), the position's tick range is set such that the current price is outside the range. As buyers enter and push the price into the range, the position begins converting the new token into the base token — functioning as a continuous sell wall that creates an orderly market.

### Step 5: LP Locking

The LP NFT is permanently locked. Depending on the factory's configuration:

- **Default (V1)**: The factory itself holds the NFT in perpetuity. There is no function to transfer or burn LP NFTs held by the factory.
- **Citadel Integration (V2)**: If a Citadel LP Locker address is set, the factory attempts to automatically transfer the NFT to Citadel and lock it via `lockFromFactory`. If the Citadel lock fails for any reason, the factory retains the NFT as a fallback — the launch transaction never reverts due to a Citadel issue.

In either case, the liquidity cannot be removed. The LP is provably locked forever.

### Step 6: Creator Tracking

The factory records the full lineage of every launch:

- `nftCreators[tokenId] → creator address` — who launched this token
- `creatorNFTs[creator] → tokenId[]` — all tokens launched by this creator
- `tokenIdToToken[tokenId] → token address` — which token the LP NFT represents

This mapping enables frontends to show a creator's portfolio, verify launch provenance, and link tokens back to their LP positions.

---

## Fee Collection and Treasury

All trading fees generated by Sentry-launched pools accrue to the locked LP positions. These fees are collected to a single **treasury address** set by the factory owner.

### How Fees Work

1. Every swap through a Sentry-launched pool pays the 1% fee
2. The fee is split proportionally among all in-range liquidity positions
3. Since the factory-locked position is typically the dominant (or sole) LP, it captures most or all of the fees
4. The factory owner calls `collectFees(tokenId)` or `collectMultipleFees(tokenIds[])` to harvest fees
5. Collected fees are sent directly to the treasury address

### Treasury Governance

The treasury address is updatable by the factory owner via `updateTreasury(newTreasury)`. This allows the ecosystem to evolve its fee distribution strategy over time — from a single wallet to a multisig, DAO, or revenue-sharing contract.

---

## Upgradeable Architecture

The Sentry Launch Factory is deployed behind a `TransparentUpgradeableProxy` with a `ProxyAdmin`. This means:

- The factory logic can be upgraded without changing the contract address
- All state (creator mappings, NFT custody, configuration) is preserved across upgrades
- The `initialize()` function replaces the constructor and can only be called once
- A `__gap` of 49 storage slots is reserved for future state variables

### V2 Upgrade: Citadel Integration

The most significant upgrade added the `citadel` state variable and the automatic LP-to-Citadel flow. This upgrade:

- Consumed one slot from the `__gap` array
- Added `setCitadel(address)` for the owner to configure the Citadel address
- Added `retryLockInCitadel(tokenId)` to manually retry failed Citadel locks
- Modified `_handleSuccessfulMint` to attempt auto-locking in Citadel with a try/catch fallback

---

## ERC-2771 Meta-Transactions

Both the factory and the deployed tokens support the ERC-2771 meta-transaction standard via Gelato's 1Balance relay. This enables:

- **Gasless token launches** — a relayer pays the gas, the creator signs a meta-transaction
- **Gasless token transfers** — holders can send tokens without holding ETH
- **Sponsored transactions** — ecosystem sponsors can subsidize user activity

The trusted forwarder address is stored in the factory and passed to each deployed token at construction time. It can be updated by the factory owner via `setTrustedForwarder(address)`.

---

## Multi-Base Token Support

The factory is not limited to WETH-paired launches. Any ERC-20 token can be registered as a base token with its own pool manager:

```
addBaseToken(baseToken, poolManager)    — register a new base token
updatePoolManager(baseToken, manager)   — swap the pool manager for a base token
removeBaseToken(baseToken)              — unregister a base token
getSupportedBaseTokens()                — list all registered base tokens
```

This architecture allows the ecosystem to expand to stablecoin-paired launches (e.g., USDC base), native token launches (e.g., a protocol's governance token as the base), or any other pairing strategy.

---

## Events

The factory emits a comprehensive set of events for indexing and frontend consumption:

| Event | Description |
|---|---|
| `TokenDeployed(token, name, symbol, creator, tokenId)` | New token launched |
| `PoolInitialized(pool, token)` | Tsunami V3 pool created and initialized |
| `LiquidityMinted(tokenId, pool, token)` | LP position minted |
| `LPLocked(tokenId, pool, token)` | LP NFT permanently locked |
| `FeesCollected(tokenId, amount0, amount1)` | Trading fees harvested |
| `BaseTokenAdded(baseToken, manager)` | New base token registered |
| `BaseTokenRemoved(baseToken)` | Base token unregistered |
| `PoolManagerUpdated(baseToken, oldManager, newManager)` | Pool manager changed |
| `TreasuryUpdated(oldTreasury, newTreasury)` | Treasury address changed |
| `CitadelUpdated(oldCitadel, newCitadel)` | Citadel locker address changed |
| `CitadelLockFailed(tokenId, reason)` | Auto-lock to Citadel failed (factory retains NFT) |

---

## View Functions

| Function | Returns |
|---|---|
| `getPoolManager(baseToken)` | Pool manager address for a base token |
| `getSupportedBaseTokens()` | Array of all registered base token addresses |
| `getCreator(tokenId)` | Creator address for an LP NFT |
| `getCreatorNFTs(creator)` | Array of all LP NFT IDs created by an address |
| `getCreatorNFTCount(creator)` | Number of tokens launched by an address |
| `getTokenByNFT(tokenId)` | Token contract address for an LP NFT |
| `getTotalTokensDeployed()` | Total number of tokens ever launched |
| `getTrustedForwarder()` | Current Gelato ERC-2771 forwarder address |

---

## Contract Address

| Contract | Address |
|---|---|
| **SentryLaunchFactory (Proxy)** | `0xDc37e11B68052d1539fa23386eE58Ac444bf5BE1` |

Deployed on Ink (Chain ID 57073). Verified on the Ink Explorer.
