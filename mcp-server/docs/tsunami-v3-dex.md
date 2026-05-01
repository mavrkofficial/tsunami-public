# Tsunami V3 DEX

## Overview

Tsunami V3 is a concentrated liquidity decentralized exchange (DEX) deployed on **Ink** (Chain ID 57073), an Optimism-based L2. It is a direct fork of the Uniswap V3 protocol with a series of purpose-built upgrades designed to support the full spectrum of on-chain asset types — from tightly pegged stablecoins to freshly launched meme coins. Tsunami V3 retains complete compatibility with the Uniswap V3 callback interface while extending the protocol in ways that make it the native liquidity backbone of the Moltiverse ecosystem.

---

## Architecture

Tsunami V3 is composed of several interconnected smart contracts that mirror the Uniswap V3 architecture with Tsunami-specific naming and extensions:

| Contract | Address | Role |
|---|---|---|
| **TsunamiV3Factory** | `0xD8B0826150B7686D1F56d6F10E31E58e1BCF1193` | Deploys pools, manages fee tiers, governs protocol fees |
| **TsunamiV3PositionManager** | `0x98b6267DA27c5A21Bd6e3edfBC2DA6b0428Fa9F7` | Manages LP positions as ERC-721 NFTs, handles minting, burning, and fee collection |
| **TsunamiSwapRouter02** | `0x4415F2360bfD9B1bF55500Cb28fA41dF95CB2d2b` | Unified swap router with multicall, deadline enforcement, and native ETH wrapping/unwrapping |
| **TsunamiQuoterV2** | `0x547D43a6F83A28720908537Aa25179ff8c6A6411` | Gas-efficient off-chain price quoting without state changes |
| **TsunamiTickLens** | Deployed | On-chain tick state inspection for frontends and analytics |
| **WETH9** | `0x4200000000000000000000000000000000000006` | Wrapped ETH (standard OP Stack address) |

All contracts are deployed on Ink and verified on the Ink Explorer at `https://explorer.inkonchain.com`.

---

## Concentrated Liquidity

Tsunami V3, like Uniswap V3, replaces the constant-product (`x * y = k`) model with **concentrated liquidity**. Liquidity providers choose a specific price range in which their capital is active, represented by two tick boundaries. This allows LPs to achieve significantly higher capital efficiency compared to full-range liquidity models.

### How It Works

1. **Ticks**: The price space is divided into discrete ticks. Each tick represents a 0.01% (1 basis point) price movement. Tick spacing determines which ticks are usable, based on the pool's fee tier.

2. **Positions**: An LP position is defined by a token pair, a fee tier, a lower tick, and an upper tick. Capital is only active (earning fees) when the pool's current price is within the position's range.

3. **NFT Representation**: Each LP position is minted as an ERC-721 NFT by the TsunamiV3PositionManager. The NFT encodes the position's parameters and is required for all subsequent operations (adding/removing liquidity, collecting fees).

4. **Single-Sided Liquidity**: If the current price is entirely above or below a position's range, only one token is required to open the position. This is used extensively by the Sentry Launch Factory for single-sided token launches.

---

## Fee Tier System

Tsunami V3 ships with **eight fee tiers** — the original three from Uniswap V3, plus five additional tiers designed for the broader volatility spectrum encountered on an L2 with active token launches.

| Fee Tier | Fee % | Tick Spacing | Intended Use | Origin |
|---|---|---|---|---|
| 100 | 0.01% | 1 | Pegged stablecoins (USDC/USDT, NAMI/USDT0) | **Tsunami** |
| 500 | 0.05% | 10 | Stable and correlated pairs | Uniswap V3 |
| 2500 | 0.25% | 50 | Liquid mid-volatility altcoins | **Tsunami** |
| 3000 | 0.30% | 60 | Standard trading pairs | Uniswap V3 |
| 5000 | 0.50% | 100 | Higher-volatility assets | **Tsunami** |
| 10000 | 1.00% | 200 | Exotic and high-volatility pairs | Uniswap V3 |
| 20000 | 2.00% | 400 | Meme coins and new launches | **Tsunami** |
| 50000 | 5.00% | 1000 | Extreme volatility and launchpad tokens | **Tsunami** |

### Why Extended Fee Tiers Matter

Uniswap V3's three fee tiers were designed for mature, high-liquidity markets on Ethereum mainnet. On an L2 like Ink — where tokens are frequently launched at micro-cap valuations and experience extreme early-stage volatility — wider fee tiers protect LPs from impermanent loss while still providing tradability. The 2% and 5% tiers are specifically engineered for tokens deployed through the Sentry Launch Factory, where initial trading activity is concentrated and volatile.

The factory owner can enable additional fee tiers at any time via `enableFeeAmount(fee, tickSpacing)`, making the system fully extensible without redeployment.

---

## Tsunami V3 vs. Uniswap V3 Comparison

Tsunami V3 is a literal fork of the Uniswap V3 codebase. Every core AMM mechanism — concentrated liquidity, tick math, oracle observations, NFT positions, flash loans — is inherited directly. The table below highlights what both protocols share and where Tsunami extends beyond the original.

| Feature | Uniswap V3 | Tsunami V3 |
|---|---|---|
| Concentrated liquidity (tick-based) | ✅ | ✅ |
| ERC-721 NFT LP positions | ✅ | ✅ |
| Multi-fee-tier pools per pair | ✅ | ✅ |
| Oracle observations (TWAP) | ✅ | ✅ |
| Flash loans | ✅ | ✅ |
| Multicall swap router | ✅ | ✅ |
| Permit2 integration | ✅ | ✅ |
| Gas-efficient QuoterV2 | ✅ | ✅ |
| TickLens for on-chain inspection | ✅ | ✅ |
| Callback compatibility (`uniswapV3SwapCallback`) | ✅ | ✅ |
| Factory-level protocol fee switch | ✅ | ✅ |
| NoDelegateCall security | ✅ | ✅ |
| 0.05% fee tier (stable pairs) | ✅ | ✅ |
| 0.30% fee tier (standard pairs) | ✅ | ✅ |
| 1.00% fee tier (exotic pairs) | ✅ | ✅ |
| 0.01% fee tier (pegged stables) | ❌ | ✅ |
| 0.25% fee tier (mid-vol altcoins) | ❌ | ✅ |
| 0.50% fee tier (higher volatility) | ❌ | ✅ |
| 2.00% fee tier (meme coins) | ❌ | ✅ |
| 5.00% fee tier (extreme volatility) | ❌ | ✅ |
| Native token launch integration (Sentry) | ❌ | ✅ |
| Factory-managed LP custody (locked liquidity) | ❌ | ✅ |
| LP locker with yield optimization (Citadel) | ❌ | ✅ |
| Single-sided launch pool creation | ❌ | ✅ |
| ERC-2771 meta-transaction relay (Gelato) | ❌ | ✅ |
| Configurable pool managers per base token | ❌ | ✅ |
| Subgraph analytics (Goldsky) | ❌ | ✅ |
| AI agent MCP server integration | ❌ | ✅ |
| Tydro lending yield on idle LP fees | ❌ | ✅ |
| Deployed on Ink L2 (low gas, fast finality) | ❌ | ✅ |

---

## Swap Operations

### Exact Input Swap

A swap where the user specifies the exact amount of the input token. The router calculates and returns the output amount minus the pool fee and any slippage.

**Flow:**
1. Quote the expected output via QuoterV2's `quoteExactInputSingle`
2. Calculate minimum acceptable output based on slippage tolerance
3. If input token is an ERC-20, ensure the router has sufficient allowance
4. If input is native ETH, the router wraps it to WETH via multicall
5. Execute `exactInputSingle` via the SwapRouter02
6. If output is WETH and user wants native ETH, `unwrapWETH9` is appended to the multicall

### Exact Output Swap

A swap where the user specifies the exact amount of the output token they want to receive. The router determines how much input is required.

**Flow:**
1. Quote the required input via QuoterV2's `quoteExactOutputSingle`
2. Calculate maximum acceptable input based on slippage tolerance
3. Approve the router for the maximum input amount
4. Execute `exactOutputSingle` via the SwapRouter02
5. If input was native ETH and excess was sent, `refundETH` is appended to the multicall

### Multicall and Deadline

All swap operations are wrapped in the router's `multicall(deadline, data[])` function. This provides:
- **Atomicity**: All sub-operations (swap + unwrap, swap + refund) execute or revert together
- **Deadline enforcement**: The transaction reverts if not mined before the specified timestamp, protecting users from stale quotes

---

## Pool Operations

### Creating a Pool

Any address can create a new pool by calling `createAndInitializePoolIfNecessary` on the PositionManager with:
- `token0` (the lower address)
- `token1` (the higher address)
- `fee` (one of the eight supported fee tiers)
- `sqrtPriceX96` (the initial price as a Q64.96 fixed-point value)

If the pool already exists, the call is a no-op. If it exists but is uninitialized, it initializes at the given price.

### Querying Pool State

Pool state can be read directly from the pool contract:
- `slot0` → current sqrtPriceX96, tick, observation index, protocol fee
- `liquidity` → total active liquidity at current tick
- `fee` → the pool's fee tier
- `tickSpacing` → tick granularity for the fee tier
- `token0` / `token1` → the sorted pair addresses

---

## Liquidity Position Management

### Minting a Position

To provide liquidity:
1. Choose token pair, fee tier, and tick range (lower/upper)
2. Approve the PositionManager to spend both tokens
3. Call `mint` with desired amounts and slippage minimums
4. Receive an ERC-721 NFT representing the position

### Adding Liquidity

To add more liquidity to an existing position:
1. Approve the PositionManager for the additional amounts
2. Call `increaseLiquidity` with the position's tokenId and desired amounts

### Removing Liquidity

To remove liquidity:
1. Call `decreaseLiquidity` with the tokenId and the amount of liquidity to remove
2. Call `collect` to withdraw the tokens
3. If removing 100%, call `burn` to destroy the NFT

### Collecting Fees

Trading fees accrue in the position's token0 and token1 automatically. Call `collect` on the PositionManager with `amount0Max` and `amount1Max` set to `type(uint128).max` to harvest all accrued fees.

---

## Subgraph Analytics

Tsunami V3 is indexed by a Goldsky-hosted subgraph providing real-time protocol analytics:

**Endpoint**: `https://api.goldsky.com/api/public/project_cmm7vh5xwsa8m01qmdr7w7u62/subgraphs/tsunami-v3/1.0.0/gn`

### Available Queries

| Query | Description |
|---|---|
| **Protocol Stats** | Total value locked (TVL), cumulative volume, total fees generated, transaction count |
| **Pools** | Paginated pool list with TVL, volume, fee APR, token metadata |
| **Recent Swaps** | Latest swap events with amounts, prices, timestamps |
| **User Positions** | All LP positions for a given wallet with tick ranges, liquidity, and owed fees |
| **User Transactions** | Complete mint/burn/swap history for a wallet |
| **Daily Data** | Historical daily TVL, volume, and fee snapshots |

---

## Native ETH Handling

Since Tsunami V3 pools operate on ERC-20 tokens internally, native ETH must be wrapped to WETH for swaps and liquidity operations. The SwapRouter02 handles this transparently:

- **Sending ETH**: Attach ETH as `msg.value`; the router wraps it to WETH before the swap
- **Receiving ETH**: The router calls `unwrapWETH9` to convert WETH back to native ETH and send it to the user
- **Refunds**: For exact output swaps with ETH input, excess ETH is refunded via `refundETH`

All of this is orchestrated through the router's multicall, so users interact with native ETH seamlessly.

---

## Contract Addresses (Ink Chain — 57073)

```
TsunamiV3Factory:          0xD8B0826150B7686D1F56d6F10E31E58e1BCF1193
TsunamiV3PositionManager:  0x98b6267DA27c5A21Bd6e3edfBC2DA6b0428Fa9F7
TsunamiQuoterV2:           0x547D43a6F83A28720908537Aa25179ff8c6A6411
TsunamiSwapRouter02:       0x4415F2360bfD9B1bF55500Cb28fA41dF95CB2d2b
SentryLaunchFactory:       0xDc37e11B68052d1539fa23386eE58Ac444bf5BE1
Citadel LP Locker:         0x111474f3062E9B8B7B9d568675c5bb1262d6F862
WETH9:                     0x4200000000000000000000000000000000000006
```

---

## Security

Tsunami V3 inherits Uniswap V3's battle-tested security properties:

- **NoDelegateCall**: Core pool functions cannot be called via `delegatecall`, preventing proxy-based exploits
- **Reentrancy Protection**: The SentryLaunchFactory and Citadel use explicit reentrancy guards on all state-changing operations
- **Tick Spacing Caps**: Maximum tick spacing of 16,384 prevents overflow in tick bitmap operations
- **Factory Ownership**: Fee tier additions and protocol fee changes are restricted to the factory owner
- **Callback Verification**: Swap and mint callbacks verify the caller is the expected pool contract

---

## Frontend

The Tsunami V3 frontend is deployed at **nami.ink** and provides:

- **Swap Page** — Token swaps with real-time quoting, slippage configuration, and native ETH support
- **Pools Page** — Pool discovery with TVL, volume, and fee metrics; searchable and sortable
- **Liquidity Page** — Full position management: mint, add, remove, collect fees, with tick range visualization
- **Portfolio Page** — Wallet-level view of all LP positions, accrued fees, and transaction history
- **Bridge Page** — Cross-chain bridging for moving assets to and from Ink
