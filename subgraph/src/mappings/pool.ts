import { BigDecimal, BigInt, ethereum } from '@graphprotocol/graph-ts';
import {
  Initialize,
  Swap as SwapEvent,
  Mint as MintEvent,
  Burn as BurnEvent,
  Collect as CollectEvent,
} from '../../generated/templates/Pool/Pool';
import {
  Pool,
  Factory,
  Token,
  Bundle,
  Swap,
  Mint,
  Burn,
  Collect,
  Tick,
  Transaction,
  User,
} from '../../generated/schema';
import {
  FACTORY_ADDRESS,
  ZERO_BI,
  ZERO_BD,
  ONE_BI,
} from '../utils/constants';
import {
  getEthPriceInUSD,
  findEthPerToken,
  sqrtPriceX96ToTokenPrices,
  convertTokenToDecimal,
  getTrackedAmountUSD,
} from '../utils/pricing';
import {
  updateTsunamiDayData,
  updatePoolDayData,
  updatePoolHourData,
  updateTokenDayData,
  updateTokenHourData,
} from '../utils/intervals';
import { createTick } from '../utils/tick';

/* ── Initialize ────────────────────────────────────── */
export function handleInitialize(event: Initialize): void {
  let pool = Pool.load(event.address.toHexString());
  if (pool === null) return;

  pool.sqrtPrice = event.params.sqrtPriceX96;
  pool.tick = BigInt.fromI32(event.params.tick);

  let token0 = Token.load(pool.token0);
  let token1 = Token.load(pool.token1);
  if (token0 === null || token1 === null) return;

  // Update token prices from sqrtPriceX96
  let prices = sqrtPriceX96ToTokenPrices(pool.sqrtPrice, token0, token1);
  pool.token0Price = prices[0];
  pool.token1Price = prices[1];
  pool.save();

  // Update ETH price
  let bundle = Bundle.load('1')!;
  bundle.ethPriceUSD = getEthPriceInUSD();
  bundle.save();

  // Update derived ETH for tokens
  token0.derivedETH = findEthPerToken(token0);
  token1.derivedETH = findEthPerToken(token1);
  token0.save();
  token1.save();
}

/* ── Swap ──────────────────────────────────────────── */
export function handleSwap(event: SwapEvent): void {
  let pool = Pool.load(event.address.toHexString());
  if (pool === null) return;

  let factory = Factory.load(FACTORY_ADDRESS)!;
  let token0 = Token.load(pool.token0)!;
  let token1 = Token.load(pool.token1)!;

  let bundle = Bundle.load('1')!;

  // Amounts
  let amount0 = convertTokenToDecimal(event.params.amount0, token0.decimals);
  let amount1 = convertTokenToDecimal(event.params.amount1, token1.decimals);
  let amount0Abs = amount0.lt(ZERO_BD) ? amount0.neg() : amount0;
  let amount1Abs = amount1.lt(ZERO_BD) ? amount1.neg() : amount1;

  let amountTotalUSD = getTrackedAmountUSD(amount0Abs, token0, amount1Abs, token1);

  // Fee calculation
  let feeTier = pool.feeTier.toI32();
  let feesUSD = amountTotalUSD.times(BigDecimal.fromString(feeTier.toString()).div(BigDecimal.fromString('1000000')));

  // Update pool
  pool.volumeToken0 = pool.volumeToken0.plus(amount0Abs);
  pool.volumeToken1 = pool.volumeToken1.plus(amount1Abs);
  pool.volumeUSD = pool.volumeUSD.plus(amountTotalUSD);
  pool.feesUSD = pool.feesUSD.plus(feesUSD);
  pool.txCount = pool.txCount.plus(ONE_BI);
  pool.liquidity = event.params.liquidity;
  pool.tick = BigInt.fromI32(event.params.tick);
  pool.sqrtPrice = event.params.sqrtPriceX96;

  // Update prices
  let prices = sqrtPriceX96ToTokenPrices(pool.sqrtPrice, token0, token1);
  pool.token0Price = prices[0];
  pool.token1Price = prices[1];

  // Update TVL for pool — swap amounts are signed (negative = out, positive = in)
  let oldPoolTVLETH = pool.totalValueLockedETH;
  pool.totalValueLockedToken0 = pool.totalValueLockedToken0.plus(amount0);
  pool.totalValueLockedToken1 = pool.totalValueLockedToken1.plus(amount1);
  let totalValueLockedETH = pool.totalValueLockedToken0
    .times(token0.derivedETH)
    .plus(pool.totalValueLockedToken1.times(token1.derivedETH));
  pool.totalValueLockedETH = totalValueLockedETH;
  pool.totalValueLockedUSD = totalValueLockedETH.times(bundle.ethPriceUSD);
  pool.save();

  // Update tokens
  token0.volume = token0.volume.plus(amount0Abs);
  token0.volumeUSD = token0.volumeUSD.plus(amountTotalUSD);
  token0.txCount = token0.txCount.plus(ONE_BI);
  token0.totalValueLocked = token0.totalValueLocked.plus(amount0);
  token0.totalValueLockedUSD = token0.totalValueLocked.times(token0.derivedETH).times(bundle.ethPriceUSD);

  token1.volume = token1.volume.plus(amount1Abs);
  token1.volumeUSD = token1.volumeUSD.plus(amountTotalUSD);
  token1.txCount = token1.txCount.plus(ONE_BI);
  token1.totalValueLocked = token1.totalValueLocked.plus(amount1);
  token1.totalValueLockedUSD = token1.totalValueLocked.times(token1.derivedETH).times(bundle.ethPriceUSD);

  // Update ETH price and derived token prices
  bundle.ethPriceUSD = getEthPriceInUSD();
  bundle.save();
  token0.derivedETH = findEthPerToken(token0);
  token1.derivedETH = findEthPerToken(token1);
  token0.save();
  token1.save();

  // Update factory — use delta to avoid TVL accumulation bug
  factory.txCount = factory.txCount.plus(ONE_BI);
  factory.totalVolumeUSD = factory.totalVolumeUSD.plus(amountTotalUSD);
  factory.totalFeesUSD = factory.totalFeesUSD.plus(feesUSD);
  factory.totalValueLockedETH = factory.totalValueLockedETH.plus(totalValueLockedETH.minus(oldPoolTVLETH));
  factory.totalValueLockedUSD = factory.totalValueLockedETH.times(bundle.ethPriceUSD);
  factory.save();

  // Create transaction
  let transaction = loadOrCreateTransaction(event);

  // Create swap entity
  let swap = new Swap(event.transaction.hash.toHexString().concat('#').concat(pool.txCount.toString()));
  swap.transaction = transaction.id;
  swap.timestamp = event.block.timestamp;
  swap.pool = pool.id;
  swap.token0 = token0.id;
  swap.token1 = token1.id;
  swap.sender = event.params.sender;
  swap.recipient = event.params.recipient;
  swap.origin = event.transaction.from;
  swap.amount0 = amount0;
  swap.amount1 = amount1;
  swap.amountUSD = amountTotalUSD;
  swap.sqrtPriceX96 = event.params.sqrtPriceX96;
  swap.tick = BigInt.fromI32(event.params.tick);
  swap.logIndex = BigInt.fromI32(event.logIndex.toI32());
  swap.save();

  // ── Per-EOA aggregation (User entity) ────────────────────────────────────
  // Tracks lifetime swap volume + Sentry-pool-only volume + ecosystem fees
  // generated. fees-generated math mirrors SentryLaunchFactory.FEE_TIER
  // (1% = 0.01); if the factory's launch fee tier ever changes, update both.
  let userId = event.transaction.from.toHexString();
  let user = User.load(userId);
  if (user === null) {
    user = new User(userId);
    user.swapCount = ZERO_BI;
    user.swapCountOnSentryPools = ZERO_BI;
    user.volumeUSD = ZERO_BD;
    user.volumeUSDOnSentryPools = ZERO_BD;
    user.feesGeneratedUSD = ZERO_BD;
    user.creatorFeesEarnedWei = ZERO_BI;
    user.creatorFeesEarnedUSD = ZERO_BD;
    user.firstSwapTimestamp = event.block.timestamp;
  }
  user.swapCount = user.swapCount.plus(ONE_BI);
  user.volumeUSD = user.volumeUSD.plus(amountTotalUSD);
  user.lastSwapTimestamp = event.block.timestamp;
  if (pool.isSentry) {
    user.swapCountOnSentryPools = user.swapCountOnSentryPools.plus(ONE_BI);
    user.volumeUSDOnSentryPools = user.volumeUSDOnSentryPools.plus(amountTotalUSD);
    let feesGenerated = amountTotalUSD.times(BigDecimal.fromString('0.01'));
    user.feesGeneratedUSD = user.feesGeneratedUSD.plus(feesGenerated);
  }
  user.save();

  // Update time-series data
  let tsunamiDayData = updateTsunamiDayData(event);
  let poolDayData = updatePoolDayData(event, pool);
  let poolHourData = updatePoolHourData(event, pool);
  let token0DayData = updateTokenDayData(token0, event);
  let token1DayData = updateTokenDayData(token1, event);
  let token0HourData = updateTokenHourData(token0, event);
  let token1HourData = updateTokenHourData(token1, event);

  tsunamiDayData.volumeUSD = tsunamiDayData.volumeUSD.plus(amountTotalUSD);
  tsunamiDayData.feesUSD = tsunamiDayData.feesUSD.plus(feesUSD);
  tsunamiDayData.save();

  poolDayData.volumeUSD = poolDayData.volumeUSD.plus(amountTotalUSD);
  poolDayData.volumeToken0 = poolDayData.volumeToken0.plus(amount0Abs);
  poolDayData.volumeToken1 = poolDayData.volumeToken1.plus(amount1Abs);
  poolDayData.feesUSD = poolDayData.feesUSD.plus(feesUSD);
  poolDayData.save();

  poolHourData.volumeUSD = poolHourData.volumeUSD.plus(amountTotalUSD);
  poolHourData.volumeToken0 = poolHourData.volumeToken0.plus(amount0Abs);
  poolHourData.volumeToken1 = poolHourData.volumeToken1.plus(amount1Abs);
  poolHourData.feesUSD = poolHourData.feesUSD.plus(feesUSD);
  poolHourData.save();

  token0DayData.volume = token0DayData.volume.plus(amount0Abs);
  token0DayData.volumeUSD = token0DayData.volumeUSD.plus(amountTotalUSD);
  token0DayData.feesUSD = token0DayData.feesUSD.plus(feesUSD);
  token0DayData.save();

  token1DayData.volume = token1DayData.volume.plus(amount1Abs);
  token1DayData.volumeUSD = token1DayData.volumeUSD.plus(amountTotalUSD);
  token1DayData.feesUSD = token1DayData.feesUSD.plus(feesUSD);
  token1DayData.save();

  token0HourData.volume = token0HourData.volume.plus(amount0Abs);
  token0HourData.volumeUSD = token0HourData.volumeUSD.plus(amountTotalUSD);
  token0HourData.feesUSD = token0HourData.feesUSD.plus(feesUSD);
  token0HourData.save();

  token1HourData.volume = token1HourData.volume.plus(amount1Abs);
  token1HourData.volumeUSD = token1HourData.volumeUSD.plus(amountTotalUSD);
  token1HourData.feesUSD = token1HourData.feesUSD.plus(feesUSD);
  token1HourData.save();
}

/* ── Mint ──────────────────────────────────────────── */
export function handleMint(event: MintEvent): void {
  let pool = Pool.load(event.address.toHexString());
  if (pool === null) return;

  let factory = Factory.load(FACTORY_ADDRESS)!;
  let token0 = Token.load(pool.token0)!;
  let token1 = Token.load(pool.token1)!;
  let bundle = Bundle.load('1')!;

  let amount0 = convertTokenToDecimal(event.params.amount0, token0.decimals);
  let amount1 = convertTokenToDecimal(event.params.amount1, token1.decimals);
  let amountUSD = getTrackedAmountUSD(amount0, token0, amount1, token1);

  // Update pool TVL
  pool.totalValueLockedToken0 = pool.totalValueLockedToken0.plus(amount0);
  pool.totalValueLockedToken1 = pool.totalValueLockedToken1.plus(amount1);
  pool.liquidity = pool.liquidity.plus(event.params.amount);
  pool.txCount = pool.txCount.plus(ONE_BI);

  let totalValueLockedETH = pool.totalValueLockedToken0
    .times(token0.derivedETH)
    .plus(pool.totalValueLockedToken1.times(token1.derivedETH));
  pool.totalValueLockedETH = totalValueLockedETH;
  pool.totalValueLockedUSD = totalValueLockedETH.times(bundle.ethPriceUSD);
  pool.save();

  // Update tokens
  token0.totalValueLocked = token0.totalValueLocked.plus(amount0);
  token0.totalValueLockedUSD = token0.totalValueLocked.times(token0.derivedETH).times(bundle.ethPriceUSD);
  token0.txCount = token0.txCount.plus(ONE_BI);
  token0.save();

  token1.totalValueLocked = token1.totalValueLocked.plus(amount1);
  token1.totalValueLockedUSD = token1.totalValueLocked.times(token1.derivedETH).times(bundle.ethPriceUSD);
  token1.txCount = token1.txCount.plus(ONE_BI);
  token1.save();

  // Update factory
  factory.txCount = factory.txCount.plus(ONE_BI);
  factory.save();

  // Create ticks if needed
  let lowerTickId = pool.id.concat('#').concat(event.params.tickLower.toString());
  let upperTickId = pool.id.concat('#').concat(event.params.tickUpper.toString());

  let lowerTick = Tick.load(lowerTickId);
  if (lowerTick === null) {
    lowerTick = createTick(lowerTickId, event.params.tickLower, pool.id, event.block.timestamp, event.block.number);
  }
  lowerTick.liquidityGross = lowerTick.liquidityGross.plus(event.params.amount);
  lowerTick.liquidityNet = lowerTick.liquidityNet.plus(event.params.amount);
  lowerTick.save();

  let upperTick = Tick.load(upperTickId);
  if (upperTick === null) {
    upperTick = createTick(upperTickId, event.params.tickUpper, pool.id, event.block.timestamp, event.block.number);
  }
  upperTick.liquidityGross = upperTick.liquidityGross.plus(event.params.amount);
  upperTick.liquidityNet = upperTick.liquidityNet.minus(event.params.amount);
  upperTick.save();

  // Create transaction + mint entity
  let transaction = loadOrCreateTransaction(event);
  let mint = new Mint(event.transaction.hash.toHexString().concat('#').concat(pool.txCount.toString()));
  mint.transaction = transaction.id;
  mint.timestamp = event.block.timestamp;
  mint.pool = pool.id;
  mint.token0 = token0.id;
  mint.token1 = token1.id;
  mint.owner = event.params.owner;
  mint.sender = event.params.sender;
  mint.origin = event.transaction.from;
  mint.amount = event.params.amount;
  mint.amount0 = amount0;
  mint.amount1 = amount1;
  mint.amountUSD = amountUSD;
  mint.tickLower = BigInt.fromI32(event.params.tickLower);
  mint.tickUpper = BigInt.fromI32(event.params.tickUpper);
  mint.logIndex = BigInt.fromI32(event.logIndex.toI32());
  mint.save();

  // Time-series
  updateTsunamiDayData(event);
  updatePoolDayData(event, pool);
  updatePoolHourData(event, pool);
  updateTokenDayData(token0, event);
  updateTokenDayData(token1, event);
  updateTokenHourData(token0, event);
  updateTokenHourData(token1, event);
}

/* ── Burn ──────────────────────────────────────────── */
export function handleBurn(event: BurnEvent): void {
  let pool = Pool.load(event.address.toHexString());
  if (pool === null) return;

  let factory = Factory.load(FACTORY_ADDRESS)!;
  let token0 = Token.load(pool.token0)!;
  let token1 = Token.load(pool.token1)!;
  let bundle = Bundle.load('1')!;

  let amount0 = convertTokenToDecimal(event.params.amount0, token0.decimals);
  let amount1 = convertTokenToDecimal(event.params.amount1, token1.decimals);
  let amountUSD = getTrackedAmountUSD(amount0, token0, amount1, token1);

  // Update pool
  pool.totalValueLockedToken0 = pool.totalValueLockedToken0.minus(amount0);
  pool.totalValueLockedToken1 = pool.totalValueLockedToken1.minus(amount1);
  pool.liquidity = pool.liquidity.minus(event.params.amount);
  pool.txCount = pool.txCount.plus(ONE_BI);

  let totalValueLockedETH = pool.totalValueLockedToken0
    .times(token0.derivedETH)
    .plus(pool.totalValueLockedToken1.times(token1.derivedETH));
  pool.totalValueLockedETH = totalValueLockedETH;
  pool.totalValueLockedUSD = totalValueLockedETH.times(bundle.ethPriceUSD);
  pool.save();

  // Update tokens
  token0.totalValueLocked = token0.totalValueLocked.minus(amount0);
  token0.totalValueLockedUSD = token0.totalValueLocked.times(token0.derivedETH).times(bundle.ethPriceUSD);
  token0.txCount = token0.txCount.plus(ONE_BI);
  token0.save();

  token1.totalValueLocked = token1.totalValueLocked.minus(amount1);
  token1.totalValueLockedUSD = token1.totalValueLocked.times(token1.derivedETH).times(bundle.ethPriceUSD);
  token1.txCount = token1.txCount.plus(ONE_BI);
  token1.save();

  factory.txCount = factory.txCount.plus(ONE_BI);
  factory.save();

  // Update ticks
  let lowerTickId = pool.id.concat('#').concat(event.params.tickLower.toString());
  let upperTickId = pool.id.concat('#').concat(event.params.tickUpper.toString());

  let lowerTick = Tick.load(lowerTickId);
  if (lowerTick !== null) {
    lowerTick.liquidityGross = lowerTick.liquidityGross.minus(event.params.amount);
    lowerTick.liquidityNet = lowerTick.liquidityNet.minus(event.params.amount);
    lowerTick.save();
  }

  let upperTick = Tick.load(upperTickId);
  if (upperTick !== null) {
    upperTick.liquidityGross = upperTick.liquidityGross.minus(event.params.amount);
    upperTick.liquidityNet = upperTick.liquidityNet.plus(event.params.amount);
    upperTick.save();
  }

  // Create burn entity
  let transaction = loadOrCreateTransaction(event);
  let burn = new Burn(event.transaction.hash.toHexString().concat('#').concat(pool.txCount.toString()));
  burn.transaction = transaction.id;
  burn.timestamp = event.block.timestamp;
  burn.pool = pool.id;
  burn.token0 = token0.id;
  burn.token1 = token1.id;
  burn.owner = event.params.owner;
  burn.origin = event.transaction.from;
  burn.amount = event.params.amount;
  burn.amount0 = amount0;
  burn.amount1 = amount1;
  burn.amountUSD = amountUSD;
  burn.tickLower = BigInt.fromI32(event.params.tickLower);
  burn.tickUpper = BigInt.fromI32(event.params.tickUpper);
  burn.logIndex = BigInt.fromI32(event.logIndex.toI32());
  burn.save();

  // Time-series
  updateTsunamiDayData(event);
  updatePoolDayData(event, pool);
  updatePoolHourData(event, pool);
  updateTokenDayData(token0, event);
  updateTokenDayData(token1, event);
  updateTokenHourData(token0, event);
  updateTokenHourData(token1, event);
}

/* ── Pool Collect (fee collection from pool) ─────── */
export function handlePoolCollect(event: CollectEvent): void {
  let pool = Pool.load(event.address.toHexString());
  if (pool === null) return;

  let token0 = Token.load(pool.token0)!;
  let token1 = Token.load(pool.token1)!;
  let bundle = Bundle.load('1')!;

  let amount0 = convertTokenToDecimal(event.params.amount0, token0.decimals);
  let amount1 = convertTokenToDecimal(event.params.amount1, token1.decimals);

  pool.collectedFeesToken0 = pool.collectedFeesToken0.plus(amount0);
  pool.collectedFeesToken1 = pool.collectedFeesToken1.plus(amount1);
  pool.collectedFeesUSD = pool.collectedFeesToken0
    .times(token0.derivedETH)
    .times(bundle.ethPriceUSD)
    .plus(pool.collectedFeesToken1.times(token1.derivedETH).times(bundle.ethPriceUSD));
  pool.txCount = pool.txCount.plus(ONE_BI);
  pool.save();

  let transaction = loadOrCreateTransaction(event);
  let collect = new Collect(event.transaction.hash.toHexString().concat('#').concat(pool.txCount.toString()));
  collect.transaction = transaction.id;
  collect.timestamp = event.block.timestamp;
  collect.pool = pool.id;
  collect.owner = event.params.owner;
  collect.amount0 = amount0;
  collect.amount1 = amount1;
  collect.amountUSD = getTrackedAmountUSD(amount0, token0, amount1, token1);
  collect.tickLower = BigInt.fromI32(event.params.tickLower);
  collect.tickUpper = BigInt.fromI32(event.params.tickUpper);
  collect.logIndex = BigInt.fromI32(event.logIndex.toI32());
  collect.save();
}

/* ── Helper ───────────────────────────────────────── */
function loadOrCreateTransaction(event: ethereum.Event): Transaction {
  let tx = Transaction.load(event.transaction.hash.toHexString());
  if (tx === null) {
    tx = new Transaction(event.transaction.hash.toHexString());
    tx.blockNumber = event.block.number;
    tx.timestamp = event.block.timestamp;
    tx.gasUsed = event.transaction.gasLimit;
    tx.gasPrice = event.transaction.gasPrice;
    tx.save();
  }
  return tx;
}
