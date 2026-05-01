# Tsunami

[![Chain: Ink 57073](https://img.shields.io/badge/chain-Ink%2057073-2563eb)](https://explorer.inkonchain.com)
[![Solidity ^0.8.20](https://img.shields.io/badge/solidity-%5E0.8.20-363636)](https://soliditylang.org)
[![Built with Foundry](https://img.shields.io/badge/built%20with-Foundry-fe5d26)](https://book.getfoundry.sh)
[![Subgraph: Goldsky](https://img.shields.io/badge/subgraph-Goldsky-7d56f3)](https://api.goldsky.com/api/public/project_cmm7vh5xwsa8m01qmdr7w7u62/subgraphs/tsunami-v3/2.4.0/gn)
[![Status: Unaudited](https://img.shields.io/badge/status-unaudited-eab308)](#)

> Open-source contracts, deploy scripts, subgraph, and MCP server for the **Tsunami DEX** on Ink. The frontend is a separate (private) repo. **Unaudited — use at your own risk.**

A concentrated-liquidity decentralized exchange on **Ink** (chain ID `57073`). Direct fork of Uniswap V3 with extensions tuned for the full volatility spectrum on an L2 — stable pegs, mid-vol alts, correlated vol pairs, and freshly-launched memes.

This repo contains the open-source components: contracts, deploy scripts, the Goldsky-hosted subgraph, and the MCP server that exposes the protocol as agent-callable tools.

## Repo layout

| Path | Contents |
|---|---|
| `contracts/` | Solidity sources — V3 core, V3 periphery, Universal Router + Permit2, Sentry launchpad, Citadel LP locker, vendored proxies |
| `script/` | Foundry deploy + upgrade scripts |
| `subgraph/` | Tsunami V3 subgraph — pools, swaps, mints/burns, positions, plus per-EOA `User` aggregates and Sentry-pool tagging |
| `mcp-server/` | Model Context Protocol server — wraps Tsunami / Citadel / Sentry / subgraph as named tool calls for AI agents |
| `lib/`, `src/` | Foundry deps + vendored Uniswap V3 sources (kept under their original SPDX licenses) |
| `@openzeppelin/`, `@uniswap/`, `base64-sol/` | Vendored package deps |

The frontend that runs at [nami.ink](https://nami.ink) and [sentry.trading](https://sentry.trading) is not part of this repository.

## Deployed contracts (Ink mainnet, chain 57073)

| Contract | Address |
|---|---|
| TsunamiV3Factory | `0xD8B0826150B7686D1F56d6F10E31E58e1BCF1193` |
| TsunamiV3PositionManager | `0x98b6267DA27c5A21Bd6e3edfBC2DA6b0428Fa9F7` |
| TsunamiSwapRouter02 | `0x4415F2360bfD9B1bF55500Cb28fA41dF95CB2d2b` |
| TsunamiQuoterV2 | `0x547D43a6F83A28720908537Aa25179ff8c6A6411` |
| TsunamiV3TickLens | `0x674BD1FFA511A11d1E4048b52D75b855e42Ff746` |
| TsunamiV3TokenPositionDescriptor | `0x8e02ef249A570094fE300b22Df0b5a5F5fbd17eB` |
| UniversalRouter | `0xAB51d808c8A2B0BbD698218D917dD1A738aCc43D` |
| Permit2 | `0xfA2C78ABbF97183972B6AcA1459E6a9d6374FbA5` |
| SentryLaunchFactory (proxy) | `0xDc37e11B68052d1539fa23386eE58Ac444bf5BE1` |
| Citadel (LP locker) | `0x111474f3062E9B8B7B9d568675c5bb1262d6F862` |
| WETH9 | `0x4200000000000000000000000000000000000006` |

Pool init code hash: `0x91725bfc6562eac11d55fba701002c9dd177fec2cf604f83d09038a082ae50da`

## Network

| Property | Value |
|---|---|
| Chain ID | `57073` |
| RPC | `https://rpc-gel.inkonchain.com` |
| Explorer | `https://explorer.inkonchain.com` |
| Native token | ETH |

## Fee tiers

Tsunami ships eight fee tiers — three Uniswap originals plus five Tsunami-added:

| Fee | Tick spacing | Typical use |
|---|---|---|
| 0.01% (100) | 1 | Stable pegs (USDC/USDT, NAMI/USDT0) |
| 0.05% (500) | 10 | Stable + correlated pairs |
| 0.25% (2500) | 50 | Liquid mid-volatility altcoins |
| 0.3% (3000) | 60 | Standard altcoin pair |
| 0.5% (5000) | 100 | Correlated but volatile pairs |
| 1% (10000) | 200 | Exotic / illiquid tokens |
| 2% (20000) | 400 | High-volatility launches |
| 5% (50000) | 1000 | Launchpads, memes, extreme vol |

## Build

```bash
forge build
```

## Deploy

Deploy scripts live in `script/deploy/`. Copy `.env.example` to `.env` and fill in your deployer key + RPC, then run via Foundry. Example:

```bash
forge script script/deploy/DeployTsunamiV3Core.s.sol \
  --rpc-url $RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --chain ink \
  --verify
```

> **Note**: `script/deploy/DeploySentryLaunchpad.s.sol` references a `SentryLowCapPoolManagerETH` contract that is not part of this public repo — pool managers are the proprietary part of the launchpad. To deploy your own launchpad, provide your own implementation of `ITsunamiPoolManager` (interface in `contracts/sentry/interfaces/ISentryInterfaces.sol`) before running that script. The other deploy scripts (V3 core, periphery, Universal Router, Citadel) work standalone.

## Subgraph

```bash
cd subgraph
npm install
npm run codegen
npm run build
npm run deploy:goldsky
```

Live endpoint: `https://api.goldsky.com/api/public/project_cmm7vh5xwsa8m01qmdr7w7u62/subgraphs/tsunami-v3/2.4.0/gn`

Schema highlights beyond the standard V3 subgraph:
- `User` — per-EOA aggregates: `swapCount`, `swapCountOnSentryPools`, `volumeUSD`, `volumeUSDOnSentryPools`, `feesGeneratedUSD`, `creatorFeesEarnedUSD`, first/last swap timestamps. Powers leaderboards.
- `Pool.isSentry` (+ `sentryCreator`, `sentryTokenId`, `sentryToken`) — flagged true when the pool was seeded by `SentryLaunchFactory` (V4 or the legacy proxy at `0x733733E8eAbB94832847AbF0E0EeD6031c3EB2E4`).
- `CreatorFeePayment` — per-event log of `CreatorFeePaid` emissions (V4-only).

## MCP Server

Exposes the DEX, launchpad, locker, and subgraph as MCP tools (callable from Claude Desktop, ChatGPT with MCP, custom LLM agents).

```bash
cd mcp-server
npm install
npm run build

export PRIVATE_KEY=0x...
export RPC_URL=https://rpc-gel.inkonchain.com
npm start
```

Tool families: `tsunami_*`, `subgraph_*`, `citadel_*`, `sentry_*`, `erc20_*`. See `mcp-server/README.md` for the full tool catalog and JSON-RPC examples.

## Notes on the fork

- All Solidity sources retain their original SPDX licenses.
- Branding changes affect contract names and user-facing strings only. Protocol callback names (e.g. `uniswapV3SwapCallback`) are preserved so V3 integrations work unchanged.
- The NFT position descriptor is pre-configured with Ink USDC for ratio ordering.

## Resources

- Live DEX: [nami.ink](https://nami.ink)
- Sentry launchpad PWA: [sentry.trading](https://sentry.trading)
- Uniswap V3 reference: [docs.uniswap.org/contracts/v3/overview](https://docs.uniswap.org/contracts/v3/overview)
