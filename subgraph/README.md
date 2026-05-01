# Tsunami Subgraph

Goldsky-hosted V3 subgraph for Tsunami DEX, with extensions for Sentry launchpad attribution and per-EOA aggregates.

**Live endpoint** (V2.4.0): `https://api.goldsky.com/api/public/project_cmm7vh5xwsa8m01qmdr7w7u62/subgraphs/tsunami-v3/2.4.0/gn`

## Develop

```bash
npm install
npm run codegen
npm run build
```

## Deploy

```bash
# Bump the version in package.json's deploy:goldsky script first
npm run deploy:goldsky
```

## Schema additions vs canonical Uniswap V3 subgraph

Standard V3 entities (`Factory`, `Pool`, `Token`, `Position`, `Swap`, `Mint`, `Burn`, `Collect`, `Tick`, `*DayData`, `*HourData`, `Bundle`) are present and behave identically. On top of those:

### `Pool` — Sentry attribution fields

| Field | Type | Meaning |
|---|---|---|
| `isSentry` | `Boolean!` | `true` if the pool was seeded by `SentryLaunchFactory` (V4 proxy or the legacy proxy). Defaults `false`. |
| `sentryCreator` | `Bytes` | The `_msgSender()` that called `launch()` (or `launchAgent()`). Set by the `TokenDeployed` handler. |
| `sentryTokenId` | `BigInt` | The factory's NFT token ID for this pool's LP position. |
| `sentryToken` | `Token` | Convenience reference to the token deployed by the launch (the non-base side of the pair). |

### `User` — per-EOA aggregates

One entity per EOA that has ever swapped on Tsunami. Updated on every `Swap` event (origin = `event.transaction.from`) and every `CreatorFeePaid` event. Powers leaderboards.

| Field | Type | Meaning |
|---|---|---|
| `id` | `ID!` | EOA address (lowercased) |
| `swapCount` | `BigInt!` | Lifetime swap count across all Tsunami pools |
| `swapCountOnSentryPools` | `BigInt!` | Subset of swapCount where `pool.isSentry = true` |
| `volumeUSD` | `BigDecimal!` | Cumulative swap volume across all Tsunami pools |
| `volumeUSDOnSentryPools` | `BigDecimal!` | Cumulative swap volume on Sentry-launched pools only |
| `feesGeneratedUSD` | `BigDecimal!` | `volumeUSDOnSentryPools × 0.01` — LP fees this EOA's swaps generated for the Sentry ecosystem |
| `creatorFeesEarnedWei` | `BigInt!` | Cumulative WETH-denominated creator fees received for tokens this EOA launched (V4 only) |
| `creatorFeesEarnedUSD` | `BigDecimal!` | Same in USD at receipt time |
| `firstSwapTimestamp` | `BigInt!` | Unix seconds of first swap |
| `lastSwapTimestamp` | `BigInt!` | Unix seconds of latest swap |

### `CreatorFeePayment` — per-event log

One entity per `CreatorFeePaid` emission from `SentryLaunchFactory.collectFees`. Useful for tx-history views; aggregates roll up into `User.creatorFeesEarnedWei` and `User.creatorFeesEarnedUSD`.

| Field | Type |
|---|---|
| `id` | `ID!` (txHash + logIndex) |
| `tokenId` | `BigInt!` |
| `creator` | `Bytes!` |
| `wethAmount` | `BigInt!` |
| `amountUSD` | `BigDecimal!` |
| `timestamp` | `BigInt!` |
| `blockNumber` | `BigInt!` |
| `transaction` | `Transaction!` |

## Recipes

### All Sentry-launched pools, ordered by volume

```graphql
query SentryPools {
  pools(
    where: { isSentry: true }
    orderBy: volumeUSD
    orderDirection: desc
    first: 100
  ) {
    id
    feeTier
    volumeUSD
    totalValueLockedUSD
    txCount
    sentryCreator
    sentryTokenId
    token0 { id symbol }
    token1 { id symbol }
  }
}
```

### Pools launched by a specific creator

```graphql
query CreatorLaunches($creator: Bytes!) {
  pools(
    where: { isSentry: true, sentryCreator: $creator }
    orderBy: createdAtTimestamp
    orderDirection: desc
  ) {
    id
    sentryTokenId
    volumeUSD
    createdAtTimestamp
    token0 { symbol }
    token1 { symbol }
  }
}
```

Variables: `{ "creator": "0xabc...123" }` (lowercase).

### Top traders by Tsunami volume

```graphql
query TopTraders {
  users(orderBy: volumeUSD orderDirection: desc first: 100) {
    id
    swapCount
    swapCountOnSentryPools
    volumeUSD
    volumeUSDOnSentryPools
    feesGeneratedUSD
  }
}
```

### Top traders by ecosystem fees generated

Sums up the LP fees each EOA contributed via swaps on Sentry-launched pools (each EOA's `volumeUSDOnSentryPools × 0.01`).

```graphql
query TopFeeContributors {
  users(orderBy: feesGeneratedUSD orderDirection: desc first: 100) {
    id
    feesGeneratedUSD
    volumeUSDOnSentryPools
    swapCountOnSentryPools
  }
}
```

### Top creators by fees earned

Only populated post-V4 deploy (block 44126438+) — earlier launches don't emit `CreatorFeePaid`.

```graphql
query TopCreators {
  users(
    where: { creatorFeesEarnedUSD_gt: "0" }
    orderBy: creatorFeesEarnedUSD
    orderDirection: desc
    first: 100
  ) {
    id
    creatorFeesEarnedUSD
    creatorFeesEarnedWei
  }
}
```

### Recent creator-fee payouts

```graphql
query RecentCreatorPayouts {
  creatorFeePayments(first: 50 orderBy: timestamp orderDirection: desc) {
    tokenId
    creator
    wethAmount
    amountUSD
    timestamp
    transaction { id }
  }
}
```

### One user's full stats

```graphql
query UserStats($id: ID!) {
  user(id: $id) {
    swapCount
    swapCountOnSentryPools
    volumeUSD
    volumeUSDOnSentryPools
    feesGeneratedUSD
    creatorFeesEarnedUSD
    creatorFeesEarnedWei
    firstSwapTimestamp
    lastSwapTimestamp
  }
}
```

## Notes

- Addresses must be lowercased in subgraph filters and IDs.
- Numeric fields return strings (`BigInt` / `BigDecimal`); parse client-side with your bigint/decimal library of choice.
- Both the V4 `SentryLaunchFactory` proxy (`0xDc37…5BE1`, startBlock `42008767`) and the legacy proxy (`0x7337…E2E4`, startBlock `40126112`) are indexed. They share `PoolInitialized` and `TokenDeployed` event signatures, so pools launched on either factory get `isSentry = true`. Only the V4 proxy emits `CreatorFeePaid`.
- See [`docs/sentry.md`](../docs/sentry.md) for the launchpad's contract-level mechanics.
