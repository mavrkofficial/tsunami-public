# Citadel LP Locker

## Overview

Citadel is a non-custodial LP locker and yield optimization contract deployed on Ink. It accepts Tsunami V3 LP position NFTs, locks them for a specified duration (or permanently), and enables the locked position's accrued trading fees to be collected and optionally routed into the Tydro lending protocol for additional yield.

Citadel serves two primary roles:

1. **LP Locking** — Provides verifiable, on-chain proof that liquidity cannot be removed. This is critical for trust in newly launched tokens where rug pulls (removing LP) are the most common attack vector.

2. **Yield Optimization** — Collected trading fees from locked positions can be supplied to Tydro's lending pools, earning lending yield on top of swap fees. This creates a compounding return loop for locked liquidity.

---

## Architecture

Citadel interacts with two external systems:

- **Tsunami V3 PositionManager** — The ERC-721 NFT contract that represents LP positions. Citadel receives these NFTs via `safeTransferFrom` and holds them until the unlock time.
- **Tydro Lending Protocol** — An Aave V3-based lending market on Ink. Citadel supplies collected fee tokens to Tydro to earn lending interest.

### Contract Address

| Contract | Address |
|---|---|
| **Citadel** | `0x111474f3062E9B8B7B9d568675c5bb1262d6F862` |

Deployed on Ink (Chain ID 57073).

---

## LP Locking

### How Locking Works

1. **User approves Citadel** to transfer their LP NFT (via the PositionManager's `approve` function)
2. **User calls `lockLP(tokenId, unlockTime)`** — the NFT is transferred from the user to Citadel
3. **Citadel records the lock metadata**:
   - `locker` — the address that locked the NFT
   - `projectTreasury` — the address that receives collected fees (initially set to the locker)
   - `lockTimestamp` — when the lock was created
   - `unlockTime` — the earliest timestamp the NFT can be unlocked
   - `isSentryLaunch` — whether this lock was created by the Sentry Launch Factory
4. **The NFT is now held by Citadel** — it cannot be transferred, sold, or used to remove liquidity until the unlock time passes

### Factory-Initiated Locks

When the Sentry Launch Factory deploys a token with Citadel integration enabled, the factory calls `lockFromFactory(tokenId, creator, treasury)` directly. This creates a lock with:

- `isSentryLaunch = true` — flagged as a factory launch for analytics
- `locker` — set to the token creator
- `projectTreasury` — set to the creator (can be updated later)

Factory-initiated locks are permanent by design — the unlock time is set to the maximum, meaning the liquidity is locked forever. This is the strongest guarantee available: even the creator cannot remove the LP.

### Unlocking

Once the unlock time has passed:

1. **Call `isUnlockable(tokenId)`** to verify the lock period has expired
2. **Call `unlock(tokenId)`** — Citadel transfers the NFT back to the original locker
3. The locker now has full control of the LP position again

For Sentry Launch factory locks, the unlock time is set to maximum, making them effectively permanent.

---

## Fee Collection

Even while an LP position is locked in Citadel, trading fees continue to accrue in the underlying Tsunami V3 pool. Citadel provides functions to harvest these fees without unlocking the position:

### Single Position

```
collectFees(tokenId)
```

Collects all accrued token0 and token1 fees from the locked position and sends them to the designated recipient (the project treasury for the lock).

### Batch Collection

```
collectBatchFees(tokenIds[])
```

Collects fees from multiple locked positions in a single transaction. Useful for projects or creators with many locked positions.

### Fee Routing

Collected fees go to the `projectTreasury` address recorded in the lock metadata. The project treasury can be updated by the locker via `updateProjectTreasury(tokenId, newTreasury)`, allowing projects to evolve their fee distribution — from a creator wallet to a multisig, DAO treasury, or revenue-sharing contract.

---

## Tydro Yield Optimization

This is where Citadel goes beyond a standard LP locker. Instead of letting collected fee tokens sit idle, Citadel can supply them to the **Tydro lending protocol** to earn additional yield.

### What Is Tydro?

Tydro is an Aave V3-based lending and borrowing protocol deployed on Ink. It supports 12 live reserves (WETH, USDC, USDT, and other assets) and allows depositors to earn lending interest from borrowers. Tydro's lending rates are market-driven — when demand for borrowing an asset is high, the lending APY increases.

### How Yield Optimization Works

1. **Fees are collected** from a locked LP position via `collectFees`
2. **Fee tokens are supplied to Tydro** via `supplyToTydro(token, amount)`
   - Citadel deposits the tokens into the corresponding Tydro lending pool
   - Citadel receives aTokens (interest-bearing receipt tokens) in return
   - The deposited tokens immediately begin earning lending yield
3. **Yield accrues passively** — Tydro's aTokens are rebasing, meaning the balance grows automatically as interest is earned
4. **Withdraw when needed** via `withdrawFromTydro(token, amount)` — converts aTokens back to the underlying asset

### The Compounding Loop

This creates a two-layer yield stack:

```
Layer 1: Swap Fees
  └── Locked LP earns 1% fees on every trade through the pool
  └── Fees accrue in token0 and token1

Layer 2: Lending Yield
  └── Collected fee tokens are supplied to Tydro
  └── Tydro depositors earn lending APY from borrowers
  └── Yield compounds automatically via aToken rebasing
```

For example, if a Sentry-launched MOLTING/WETH pool generates 0.5 ETH in trading fees per week, and those fees are supplied to Tydro's WETH lending pool earning 3% APY, the project earns swap fees + lending yield on the swap fees. The LP is locked forever, so this yield generation is perpetual.

### Querying Supplied Balances

```
getTydroSupplied(token) → uint256
```

Returns the current amount of a given token that Citadel has supplied to Tydro across all its lending positions.

---

## Lock Metadata and Queries

Citadel provides comprehensive view functions for inspecting lock state:

### Lock Info

```
getLockInfo(tokenId) → {
  locker: address,          // who locked the NFT
  projectTreasury: address, // where fees are sent
  lockTimestamp: uint256,   // when the lock was created
  unlockTime: uint256,      // earliest unlock timestamp
  isSentryLaunch: bool,     // was this a factory launch?
  exists: bool              // does this lock exist?
}
```

### Position Queries

| Function | Returns | Description |
|---|---|---|
| `isLocked(tokenId)` | `bool` | Whether the NFT is currently locked in Citadel |
| `isUnlockable(tokenId)` | `bool` | Whether the lock period has expired |
| `getLockerNFTs(address)` | `uint256[]` | All NFT IDs locked by a specific address |
| `getLockedTokenIds()` | `uint256[]` | All NFT IDs currently locked in Citadel |

### Protocol Stats

| Function | Returns | Description |
|---|---|---|
| `getTotalLockedCount()` | `uint256` | Total number of LP positions currently locked |
| `getTotalSentryLocks()` | `uint256` | Number of locks created by the Sentry Launch Factory |
| `platformFeeBps()` | `uint256` | Platform fee in basis points (taken from collected fees) |
| `treasury()` | `address` | Citadel's own platform treasury address |

---

## Platform Fee

Citadel charges a platform fee (in basis points) on collected trading fees. When fees are collected from a locked position:

1. The platform fee percentage is deducted
2. The fee goes to Citadel's own `treasury` address
3. The remainder goes to the lock's `projectTreasury`

This fee funds Citadel's operations and the broader ecosystem. The fee rate is set by the Citadel owner.

---

## Admin Functions

| Function | Description |
|---|---|
| `updateProjectTreasury(tokenId, newTreasury)` | Locker updates where their fees go |
| `owner()` | Returns the current Citadel owner address |
| `npm()` | Returns the Tsunami V3 PositionManager address |
| `treasury()` | Returns Citadel's platform treasury |

---

## Security Properties

### Non-Custodial Design

While Citadel holds LP NFTs, it is a non-custodial system:

- Only the original `locker` can call `unlock` after the unlock time
- Only the `locker` can update the `projectTreasury`
- Fee collection can be triggered by anyone, but fees always go to the designated treasury
- The Citadel owner cannot steal or transfer locked NFTs

### Sentry Factory Integration Safety

The Sentry Launch Factory's Citadel integration is wrapped in a try/catch:

- If Citadel is down or reverts, the factory retains the NFT (original V1 behavior)
- The launch transaction never fails due to a Citadel issue
- A `CitadelLockFailed` event is emitted for monitoring
- The factory owner can retry the lock later via `retryLockInCitadel(tokenId)`

### Reentrancy Protection

All state-changing operations in Citadel use reentrancy guards to prevent callback-based attacks during NFT transfers and fee collection.

---

## Integration with the Moltiverse Ecosystem

Citadel is the connective tissue between three systems:

```
Sentry Launch Factory
  │
  ├── Deploys token
  ├── Creates Tsunami V3 pool
  ├── Mints LP position
  └── Locks LP NFT in Citadel
        │
        ├── Holds NFT permanently
        ├── Collects trading fees
        └── Supplies fees to Tydro
              │
              └── Earns lending yield
                  (WETH, USDC, etc.)
```

This creates a fully automated value chain:

1. **Token launch** → immediate tradability on Tsunami V3
2. **Locked LP** → provable rug-pull protection
3. **Fee collection** → passive income for the creator/treasury
4. **Tydro supply** → compound yield on collected fees

All of this is accessible programmatically through the Moltiverse Agent Economy MCP server, enabling AI agents to launch tokens, manage liquidity, collect fees, and optimize yield autonomously.
