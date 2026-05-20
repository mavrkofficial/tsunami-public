# Tsunami Protocol Fee Switch

Tsunami's fee switch routes protocol fees through an immutable receiver that
splits each collected token in-kind:

| Recipient | Share |
|---|---:|
| Ink Foundation | 80% |
| SENTRY revenue distributor | 15% |
| Tsunami operational treasury | 5% |

The receiver addresses are constructor immutables. There is no admin setter,
pause, proxy, or fee-redirect path.

## Protocol Fee Mapping

Tsunami uses the native V3 protocol-fee mechanism. The pool stores a denominator
`N`; protocol fees equal `LP fee / N`. `0` means off; valid enabled values are
`4` through `10`.

| LP fee tier | Tick spacing | Protocol fee | Denominator |
|---|---:|---:|---:|
| 0.01% (`100`) | 1 | 10% | `10` |
| 0.05% (`500`) | 10 | 10% | `10` |
| 0.25% (`2500`) | 50 | 10% | `10` |
| 0.30% (`3000`) | 60 | 10% | `10` |
| 0.50% (`5000`) | 100 | 10% | `10` |
| 1.00% (`10000`) | 200 | 25% | `4` |
| 2.00% (`20000`) | 400 | 25% | `4` |
| 5.00% (`50000`) | 1000 | 25% | `4` |

The controller applies the same denominator to both pool sides:
`setFeeProtocol(N, N)`.

## Contracts

### `ProtocolFeeReceiver`

`contracts/governance/ProtocolFeeReceiver.sol`

- Immutable recipient addresses.
- `distribute(token)` splits the receiver's full ERC20 balance.
- `distributeMany(tokens)` batches ERC20 distribution.
- `distributeETH()` splits native ETH.
- Rounding dust goes to Ink Foundation by assigning the largest share last:
  `ink = total - sentry - treasury`.

### `ProtocolFeeController`

`contracts/governance/ProtocolFeeController.sol`

- Holds the Tsunami V3 factory owner role.
- `setProtocolFeeForPool(pool)` maps the pool fee tier to a denominator.
- Callable by the controller owner or by the configured Sentry factory.
- `batchSetProtocolFee(pools)` activates the switch on existing pools.
- `collectAndDistribute(pools, amount0s, amount1s)` permissionlessly collects
  protocol fees to the immutable receiver. Distribution is intentionally a
  separate step so a collection issue on one pool does not block distribution
  for other tokens.

## Collection Flow

1. Fetch the pool list from the Goldsky subgraph.
2. Read `protocolFees()` for each pool.
3. Call `ProtocolFeeController.collectAndDistribute(...)` in batches.
4. Deduplicate the collected token addresses.
5. Call `ProtocolFeeReceiver.distributeMany(tokens)`.
6. Call `ProtocolFeeReceiver.distributeETH()` if native ETH is present.

Suggested cadence: monthly keeper or GitHub Actions cron.

## Sentry Interaction

Sentry launch economics are separate from protocol fees:

| Pair type | Side | Creator | Treasury |
|---|---|---:|---:|
| WETH pair | WETH-side LP fees | 50% | 50% |
| WETH pair | Token-side LP fees | 0% | 100% |
| Non-WETH pair | Both sides | 0% | 100% |

The Sentry treasury share continues flowing to the SENTRY revenue-share path.
The protocol-fee receiver adds a second SENTRY revenue stream: 15% of Tsunami
protocol fees from every pool, including non-Sentry pools.

## Example: 1% Sentry Pool, $100 Swap

For a 1% Sentry pool with protocol fee denominator `4`, the protocol receives
25% of LP fees.

| Recipient | Amount | Source |
|---|---:|---|
| Ink Foundation | $0.20 | Protocol fee × 80% |
| SENTRY holders | $0.0375 | Protocol fee × 15% |
| Tsunami treasury | $0.0125 | Protocol fee × 5% |
| Token creator | $0.1875 | WETH-side LP fee × 50% creator |
| SENTRY holders | $0.1875 | WETH-side LP fee × 50% treasury |
| Sentry operations | $0.375 | Token-side LP fee treasury |

## Deployment

1. Confirm recipient addresses:
   - `INK_FOUNDATION_ADDRESS`
   - `SENTRY_REVENUE_DISTRIBUTOR_ADDRESS`
   - `TSUNAMI_TREASURY_ADDRESS`
2. Deploy with `script/governance/DeployFeeSwitch.s.sol` and
   `TRANSFER_FACTORY_OWNERSHIP=false`.
3. Verify contract source and immutable constructor args.
4. Re-run deployment flow with `TRANSFER_FACTORY_OWNERSHIP=true` to move the
   factory owner role to the controller.
5. Generate pools:

```bash
cd script/governance
npx tsx fetch-pools.ts
```

This writes `pools.json` using the Foundry script struct format:
`[{ "address_": "0x...", "fee": 10000, "tickSpacing": 200 }, ...]`.

6. Activate existing pools:

```bash
forge script script/governance/SetExistingPoolFees.s.sol \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify
```

7. Configure the Sentry hook:

```solidity
controller.setSentryFactory(SENTRY_LAUNCH_FACTORY_ADDRESS);
```

8. Run collection/distribution monthly:

```bash
forge script script/governance/CollectAndDistribute.s.sol \
  --rpc-url "$RPC_URL" \
  --broadcast
```

## Gas Notes

The unit test target for `batchSetProtocolFee(50 pools)` is under `5M` gas
using mock pools. Real gas should be verified on an Ink fork before ownership
transfer.

## Subgraph

Pool list source:

`https://api.goldsky.com/api/public/project_cmm7vh5xwsa8m01qmdr7w7u62/subgraphs/tsunami-v3/2.4.0/gn`
