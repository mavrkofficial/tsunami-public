# Sentry Launchpad

Atomic token launchpad on Tsunami DEX. Deploys an ERC-20, creates a Tsunami V3 pool, mints a single-sided LP position, and locks the LP NFT in the factory — all in one transaction.

## Contracts

| Component | Address (Ink mainnet) |
|---|---|
| `SentryLaunchFactory` (proxy, V4 implementation) | `0xDc37e11B68052d1539fa23386eE58Ac444bf5BE1` |
| Sources | [`contracts/sentry/`](../contracts/sentry/) |

The factory is upgradeable behind a `TransparentUpgradeableProxy`. The current implementation (V4) consolidates the regular `launch()` path with the agent-gated `launchAgent()` path.

## Token standard

Every token launched via the factory is a `SentryTokenStandard` ERC-20:

- **Fixed supply**: 1,000,000,000 (1 billion) tokens, 18 decimals
- **Owner**: hardcoded to `0x000…dEaD` at construction — no admin, no mint authority, no upgrade
- **Functions**: `transfer`, `transferFrom`, `approve` only (no `mint`, no `burn`, no `freeze`, no fee-on-transfer hooks)
- **ERC-2771 support**: trusted forwarder set at deploy for meta-transactions

Source: [`contracts/sentry/SentryTokenStandard.sol`](../contracts/sentry/SentryTokenStandard.sol)

## What `launch()` does atomically

A single call to `SentryLaunchFactory.launch(name, symbol, baseToken)` performs four on-chain operations inside one transaction:

1. **Deploys a new `SentryTokenStandard` token.** Constructor mints the entire 1B supply to the factory itself; `owner` is set to `0x…dEaD`.
2. **Creates a Tsunami V3 pool** at the 1% fee tier (`createAndInitializePoolIfNecessary`) for the new token paired with `baseToken` (typically WETH). Initial price + tick range are computed by the supported `ITsunamiPoolManager` implementation registered for that base token.
3. **Mints a single-sided LP position** via the Tsunami V3 Position Manager. All 1B tokens go into the pool; zero baseToken on the other side. The LP NFT is minted to the factory.
4. **Records creator metadata**: `nftCreators[tokenId] = msg.sender`, `creatorNFTs[msg.sender].push(tokenId)`, `tokenIdToToken[tokenId] = newToken`.

Four events fire on success: `TokenDeployed`, `PoolInitialized`, `LiquidityMinted`, `LPLocked`. The token is tradable from the next block.

## Agent-gated launches

`launchAgent(name, symbol, baseToken)` is a parallel entry point that requires the caller to hold an Ink ERC-8004 identity NFT:

```solidity
require(
    identityRegistry != address(0) &&
    IIdentityRegistry(identityRegistry).balanceOf(_msgSender()) > 0,
    "MoltiverseAgentRegistry: caller not a registered agent"
);
```

The token is otherwise identical to a regular launch, but its position is flagged via `isAgentPosition[tokenId] = true` for downstream fee-routing or analytics distinctions.

## LP custody

The LP NFT is held permanently by the factory contract. There is no `withdrawLP` function, and the factory's owner cannot extract it. The position is effectively locked for the life of the protocol.

(Earlier versions optionally forwarded the LP to a `Citadel` perma-locker contract. V4 retains the storage slot for backwards compatibility but does not use it — the factory self-custodies all LPs.)

## Fee routing

When `collectFees(tokenId)` (owner-only) is called, accrued LP fees are pulled from the position and routed:

| Side of pool | Destination |
|---|---|
| WETH (or other base token) | **25% to `nftCreators[tokenId]`** (the creator), **75% to `treasury`** |
| The launched token | 100% to `treasury` |
| Non-WETH paired pools (legacy) | 100% to `treasury` (both sides) |

Routing is implemented in `_routeFees` ([`contracts/sentry/SentryLaunchFactory.sol`](../contracts/sentry/SentryLaunchFactory.sol)). The 25% creator share is a constant (`CREATOR_FEE_BPS = 2500`); changing it requires a contract upgrade.

A `CreatorFeePaid(tokenId, creator, wethAmount)` event fires on every creator payout, indexable from V4 forward.

## Multi-base-token support

The factory supports launches against multiple base tokens via `addBaseToken(baseToken, manager)`. Each registered base token has its own `ITsunamiPoolManager` implementation (proprietary to the deployer — see note in main README) that determines initial price and tick range.

WETH is the canonical base token on Ink. Future base tokens (NAMI, USDC, etc.) can be added without redeploying the factory.

## Meta-transactions (ERC-2771)

The factory honors a single configurable trusted forwarder (`_trustedForwarder`). Calls relayed through that forwarder have `_msgSender()` resolve to the original user's address, so:

- `nftCreators[tokenId]` is set correctly even for sponsored / relayed launches
- The creator fee accrues to the actual launcher, not to the relayer

Set or update via `setTrustedForwarder(address)` (owner-only).

## Deploy

1. **Deploy a pool manager** that implements `ITsunamiPoolManager.getMintingParameters` for your chosen base token. (Pool managers are not part of this public repo — see the note in the main README.)
2. **Deploy the factory implementation** via [`script/deploy/DeploySentryLaunchpadImpl.s.sol`](../script/deploy/DeploySentryLaunchpadImpl.s.sol).
3. **Deploy a `TransparentUpgradeableProxy`** pointing at the implementation, with `initialize(npm, baseToken, manager, treasury, trustedForwarder)` called atomically. (See [`script/deploy/DeploySentryLaunchpad.s.sol`](../script/deploy/DeploySentryLaunchpad.s.sol) for the full flow — note that script depends on the proprietary pool manager source.)
4. **Optionally call `setIdentityRegistry(address)`** to enable `launchAgent()`.

## Verification

| Property | How to verify |
|---|---|
| Factory address | `cast call <PROXY> "owner()(address)"` (returns deployer at startup) |
| Treasury | `cast call <PROXY> "treasury()(address)"` |
| Identity registry | `cast call <PROXY> "identityRegistry()(address)"` (zero if `launchAgent` is disabled) |
| Total tokens deployed | `cast call <PROXY> "totalTokensDeployed()(uint256)"` |
| Creator fee constant | `cast call <PROXY> "CREATOR_FEE_BPS()(uint256)"` → `2500` |
| Pool fee tier constant | `cast call <PROXY> "FEE_TIER()(uint24)"` → `10000` (1%) |

## Subgraph integration

The Tsunami subgraph indexes the factory and tags pools as Sentry-launched. See [subgraph/README.md](../subgraph/README.md) for query examples specific to the launchpad.

## Indexed events

| Event | When | Indexed by |
|---|---|---|
| `TokenDeployed(token, name, symbol, creator, tokenId)` | Every successful launch | Subgraph + MCP `sentry_*` tools |
| `PoolInitialized(pool, token)` | Every successful launch | Subgraph (sets `Pool.isSentry = true`) |
| `LiquidityMinted(tokenId, pool, token)` | Every successful launch | Subgraph |
| `LPLocked(tokenId, pool, token)` | Every successful launch | Subgraph |
| `FeesCollected(tokenId, amount0, amount1)` | Every `collectFees` call | Subgraph |
| `CreatorFeePaid(tokenId, creator, wethAmount)` | Every WETH-side fee payout (V4+) | Subgraph (rolls up into `User.creatorFeesEarnedUSD`) |
