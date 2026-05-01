import { BigDecimal, BigInt, Bytes, ethereum } from '@graphprotocol/graph-ts';
import {
  PoolInitialized,
  TokenDeployed,
  CreatorFeePaid,
} from '../../generated/SentryLaunchFactory/SentryLaunchFactory';
import {
  Pool,
  Token,
  User,
  Bundle,
  CreatorFeePayment,
  Transaction,
} from '../../generated/schema';
import { ZERO_BD, ZERO_BI, ONE_BI } from '../utils/constants';
import { getEthPriceInUSD } from '../utils/pricing';

// Mirror of the factory's CREATOR_FEE_BPS / FEE_TIER constants. If those
// ever change in a future contract version, update both places. Pool fee
// tier on Sentry pools is fixed at 1% (FEE_TIER = 10000 bps).
const SENTRY_FEE_RATE = BigDecimal.fromString('0.01');

// ── Helpers ───────────────────────────────────────────────────────────────

function loadOrCreateTransaction(event: ethereum.Event): Transaction {
  let txId = event.transaction.hash.toHexString();
  let tx = Transaction.load(txId);
  if (tx === null) {
    tx = new Transaction(txId);
    tx.blockNumber = event.block.number;
    tx.timestamp = event.block.timestamp;
    tx.gasUsed = event.transaction.gasLimit;
    tx.gasPrice = event.transaction.gasPrice;
    tx.save();
  }
  return tx;
}

function loadOrCreateUser(id: string, timestamp: BigInt): User {
  let user = User.load(id);
  if (user !== null) return user;

  user = new User(id);
  user.swapCount = ZERO_BI;
  user.swapCountOnSentryPools = ZERO_BI;
  user.volumeUSD = ZERO_BD;
  user.volumeUSDOnSentryPools = ZERO_BD;
  user.feesGeneratedUSD = ZERO_BD;
  user.creatorFeesEarnedWei = ZERO_BI;
  user.creatorFeesEarnedUSD = ZERO_BD;
  user.firstSwapTimestamp = timestamp;
  user.lastSwapTimestamp = timestamp;
  user.save();
  return user;
}

// Convert a WETH amount in wei to USD using the current ETH price bundle.
function wethWeiToUSD(amount: BigInt): BigDecimal {
  let bundle = Bundle.load('1');
  if (bundle === null) return ZERO_BD;
  let amountDecimal = amount.toBigDecimal().div(BigDecimal.fromString('1000000000000000000'));
  return amountDecimal.times(bundle.ethPriceUSD);
}

// Public so pool.ts can reuse for the swap-side User upsert.
export function getSentryFeeRate(): BigDecimal {
  return SENTRY_FEE_RATE;
}

// ── Event handlers ────────────────────────────────────────────────────────

// Mark a pool as Sentry-launched. The pool entity is created by the V3
// Factory's PoolCreated handler; the ordering of events within the launch()
// tx is: Factory.PoolCreated → SentryLaunchFactory.PoolInitialized, so the
// Pool entity exists by the time we reach this handler.
export function handleSentryPoolInitialized(event: PoolInitialized): void {
  let poolId = event.params.pool.toHexString();
  let pool = Pool.load(poolId);
  if (pool === null) return;
  pool.isSentry = true;
  pool.save();
}

// Record creator + tokenId on the (already-marked) Sentry pool. Emitted
// AFTER PoolInitialized in the same tx by the factory's launch flow, so
// pool.isSentry is already true at this point.
export function handleSentryTokenDeployed(event: TokenDeployed): void {
  let tokenAddr = event.params.token.toHexString();
  let token = Token.load(tokenAddr);

  // Locate the Sentry pool for this token. The factory always pairs against
  // a registered base token (WETH on Ink today), and only one Sentry pool
  // exists per (token, baseToken) combo because launch() is idempotent on
  // pool creation. We find it by scanning recent Pool entities — but the
  // simpler and equivalent approach is to set the metadata via the Token
  // entity's whitelistPools list, which mirror-tracks pool membership.
  if (token !== null) {
    let pools = token.whitelistPools;
    for (let i = 0; i < pools.length; i++) {
      let p = Pool.load(pools[i]);
      if (p === null) continue;
      // Only stamp Sentry-marked pools — there could be other pools for
      // this token (someone could spin up a parallel pool at a different
      // fee tier post-launch), and we only want creator metadata on the
      // one the factory actually owns.
      if (!p.isSentry) continue;
      p.sentryCreator = event.params.creator;
      p.sentryTokenId = event.params.tokenId;
      p.sentryToken = tokenAddr;
      p.save();
    }
  }

  // Ensure a User entity exists for the creator so they show up in
  // leaderboard queries even if they never swapped before launching.
  loadOrCreateUser(event.params.creator.toHexString(), event.block.timestamp);
}

// Aggregate creator fee payments by EOA + record per-event entity for
// individual tx history.
export function handleSentryCreatorFeePaid(event: CreatorFeePaid): void {
  let creatorId = event.params.creator.toHexString();
  let user = loadOrCreateUser(creatorId, event.block.timestamp);

  let usdAmount = wethWeiToUSD(event.params.wethAmount);
  user.creatorFeesEarnedWei = user.creatorFeesEarnedWei.plus(event.params.wethAmount);
  user.creatorFeesEarnedUSD = user.creatorFeesEarnedUSD.plus(usdAmount);
  user.save();

  let tx = loadOrCreateTransaction(event);
  let payment = new CreatorFeePayment(
    event.transaction.hash.toHexString().concat('-').concat(event.logIndex.toString())
  );
  payment.tokenId = event.params.tokenId;
  payment.creator = event.params.creator;
  payment.wethAmount = event.params.wethAmount;
  payment.amountUSD = usdAmount;
  payment.timestamp = event.block.timestamp;
  payment.blockNumber = event.block.number;
  payment.transaction = tx.id;
  payment.save();
}
