import { BigDecimal, BigInt, ethereum } from '@graphprotocol/graph-ts';
import {
  TsunamiDayData,
  PoolDayData,
  PoolHourData,
  TokenDayData,
  TokenHourData,
  Pool,
  Token,
  Bundle,
  Factory,
} from '../../generated/schema';
import { FACTORY_ADDRESS, ONE_BI, ZERO_BD, ZERO_BI } from './constants';

/**
 * Update or create daily aggregates for the entire protocol.
 */
export function updateTsunamiDayData(event: ethereum.Event): TsunamiDayData {
  let factory = Factory.load(FACTORY_ADDRESS)!;
  let timestamp = event.block.timestamp.toI32();
  let dayID = timestamp / 86400;
  let dayStartTimestamp = dayID * 86400;
  let dayData = TsunamiDayData.load(dayID.toString());

  if (dayData === null) {
    dayData = new TsunamiDayData(dayID.toString());
    dayData.date = dayStartTimestamp;
    dayData.volumeETH = ZERO_BD;
    dayData.volumeUSD = ZERO_BD;
    dayData.volumeUSDUntracked = ZERO_BD;
    dayData.feesUSD = ZERO_BD;
    dayData.txCount = ZERO_BI;
  }

  dayData.tvlUSD = factory.totalValueLockedUSD;
  dayData.txCount = dayData.txCount.plus(ONE_BI);
  dayData.save();

  return dayData;
}

/**
 * Update or create hourly aggregates for a pool.
 */
export function updatePoolHourData(event: ethereum.Event, pool: Pool): PoolHourData {
  let timestamp = event.block.timestamp.toI32();
  let hourIndex = timestamp / 3600;
  let hourStartUnix = hourIndex * 3600;
  let hourPoolID = pool.id.concat('-').concat(hourIndex.toString());
  let hourData = PoolHourData.load(hourPoolID);

  if (hourData === null) {
    hourData = new PoolHourData(hourPoolID);
    hourData.periodStartUnix = hourStartUnix;
    hourData.pool = pool.id;
    hourData.volumeToken0 = ZERO_BD;
    hourData.volumeToken1 = ZERO_BD;
    hourData.volumeUSD = ZERO_BD;
    hourData.feesUSD = ZERO_BD;
    hourData.txCount = ZERO_BI;
    hourData.open = pool.token0Price;
    hourData.high = pool.token0Price;
    hourData.low = pool.token0Price;
    hourData.close = pool.token0Price;
  }

  if (pool.token0Price.gt(hourData.high)) {
    hourData.high = pool.token0Price;
  }
  if (pool.token0Price.lt(hourData.low)) {
    hourData.low = pool.token0Price;
  }

  hourData.liquidity = pool.liquidity;
  hourData.sqrtPrice = pool.sqrtPrice;
  hourData.token0Price = pool.token0Price;
  hourData.token1Price = pool.token1Price;
  hourData.tick = pool.tick;
  hourData.tvlUSD = pool.totalValueLockedUSD;
  hourData.close = pool.token0Price;
  hourData.txCount = hourData.txCount.plus(ONE_BI);
  hourData.save();

  return hourData;
}

/**
 * Update or create daily aggregates for a pool.
 */
export function updatePoolDayData(event: ethereum.Event, pool: Pool): PoolDayData {
  let timestamp = event.block.timestamp.toI32();
  let dayID = timestamp / 86400;
  let dayStartTimestamp = dayID * 86400;
  let dayPoolID = pool.id.concat('-').concat(dayID.toString());
  let dayData = PoolDayData.load(dayPoolID);

  if (dayData === null) {
    dayData = new PoolDayData(dayPoolID);
    dayData.date = dayStartTimestamp;
    dayData.pool = pool.id;
    dayData.volumeToken0 = ZERO_BD;
    dayData.volumeToken1 = ZERO_BD;
    dayData.volumeUSD = ZERO_BD;
    dayData.feesUSD = ZERO_BD;
    dayData.txCount = ZERO_BI;
    dayData.open = pool.token0Price;
    dayData.high = pool.token0Price;
    dayData.low = pool.token0Price;
    dayData.close = pool.token0Price;
  }

  if (pool.token0Price.gt(dayData.high)) {
    dayData.high = pool.token0Price;
  }
  if (pool.token0Price.lt(dayData.low)) {
    dayData.low = pool.token0Price;
  }

  dayData.liquidity = pool.liquidity;
  dayData.sqrtPrice = pool.sqrtPrice;
  dayData.token0Price = pool.token0Price;
  dayData.token1Price = pool.token1Price;
  dayData.tick = pool.tick;
  dayData.tvlUSD = pool.totalValueLockedUSD;
  dayData.close = pool.token0Price;
  dayData.txCount = dayData.txCount.plus(ONE_BI);
  dayData.save();

  return dayData;
}

/**
 * Update or create daily aggregates for a token.
 */
export function updateTokenDayData(token: Token, event: ethereum.Event): TokenDayData {
  let bundle = Bundle.load('1')!;
  let timestamp = event.block.timestamp.toI32();
  let dayID = timestamp / 86400;
  let dayStartTimestamp = dayID * 86400;
  let tokenDayID = token.id.concat('-').concat(dayID.toString());
  let dayData = TokenDayData.load(tokenDayID);
  let tokenPriceUSD = token.derivedETH.times(bundle.ethPriceUSD);

  if (dayData === null) {
    dayData = new TokenDayData(tokenDayID);
    dayData.date = dayStartTimestamp;
    dayData.token = token.id;
    dayData.volume = ZERO_BD;
    dayData.volumeUSD = ZERO_BD;
    dayData.untrackedVolumeUSD = ZERO_BD;
    dayData.feesUSD = ZERO_BD;
    dayData.open = tokenPriceUSD;
    dayData.high = tokenPriceUSD;
    dayData.low = tokenPriceUSD;
    dayData.close = tokenPriceUSD;
  }

  if (tokenPriceUSD.gt(dayData.high)) {
    dayData.high = tokenPriceUSD;
  }
  if (tokenPriceUSD.lt(dayData.low)) {
    dayData.low = tokenPriceUSD;
  }

  dayData.close = tokenPriceUSD;
  dayData.priceUSD = tokenPriceUSD;
  dayData.totalValueLocked = token.totalValueLocked;
  dayData.totalValueLockedUSD = token.totalValueLockedUSD;
  dayData.save();

  return dayData;
}

/**
 * Update or create hourly aggregates for a token.
 */
export function updateTokenHourData(token: Token, event: ethereum.Event): TokenHourData {
  let bundle = Bundle.load('1')!;
  let timestamp = event.block.timestamp.toI32();
  let hourIndex = timestamp / 3600;
  let hourStartUnix = hourIndex * 3600;
  let tokenHourID = token.id.concat('-').concat(hourIndex.toString());
  let hourData = TokenHourData.load(tokenHourID);
  let tokenPriceUSD = token.derivedETH.times(bundle.ethPriceUSD);

  if (hourData === null) {
    hourData = new TokenHourData(tokenHourID);
    hourData.periodStartUnix = hourStartUnix;
    hourData.token = token.id;
    hourData.volume = ZERO_BD;
    hourData.volumeUSD = ZERO_BD;
    hourData.untrackedVolumeUSD = ZERO_BD;
    hourData.feesUSD = ZERO_BD;
    hourData.open = tokenPriceUSD;
    hourData.high = tokenPriceUSD;
    hourData.low = tokenPriceUSD;
    hourData.close = tokenPriceUSD;
  }

  if (tokenPriceUSD.gt(hourData.high)) {
    hourData.high = tokenPriceUSD;
  }
  if (tokenPriceUSD.lt(hourData.low)) {
    hourData.low = tokenPriceUSD;
  }

  hourData.close = tokenPriceUSD;
  hourData.priceUSD = tokenPriceUSD;
  hourData.totalValueLocked = token.totalValueLocked;
  hourData.totalValueLockedUSD = token.totalValueLockedUSD;
  hourData.save();

  return hourData;
}
