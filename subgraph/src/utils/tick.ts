import { BigDecimal, BigInt } from '@graphprotocol/graph-ts';
import { Tick } from '../../generated/schema';
import { ZERO_BI, ZERO_BD, ONE_BD } from './constants';

export function createTick(tickId: string, tickIdx: i32, poolId: string, event_timestamp: BigInt, event_blockNumber: BigInt): Tick {
  let tick = new Tick(tickId);
  tick.tickIdx = BigInt.fromI32(tickIdx);
  tick.pool = poolId;
  tick.poolAddress = poolId;
  tick.liquidityGross = ZERO_BI;
  tick.liquidityNet = ZERO_BI;

  // Price derivation from tick
  // price = 1.0001 ^ tick
  tick.price0 = tickToPrice(tickIdx);
  tick.price1 = tick.price0.gt(ZERO_BD) ? ONE_BD.div(tick.price0) : ZERO_BD;

  tick.createdAtTimestamp = event_timestamp;
  tick.createdAtBlockNumber = event_blockNumber;

  return tick;
}

/**
 * Derive price from tick index: price = 1.0001 ^ tick
 * Using BigDecimal math for precision.
 */
function tickToPrice(tick: i32): BigDecimal {
  // For reasonable tick ranges, compute 1.0001^tick
  // tick can be negative (meaning price < 1)
  let absTick = tick < 0 ? -tick : tick;
  let price = ONE_BD;

  // 1.0001 as BigDecimal
  let base = BigDecimal.fromString('1.0001');

  // Multiply iteratively (subgraph AS doesn't have pow for BigDecimal)
  // For large ticks this is slow but ticks are bounded by ~887272
  // Optimization: use binary exponentiation with known constants
  // For now, use a simpler approach for reasonable tick values
  if (absTick <= 1000) {
    for (let i = 0; i < absTick; i++) {
      price = price.times(base);
    }
  } else {
    // For larger ticks, use the formula: price = exp(tick * ln(1.0001))
    // Approximate using: 1.0001^tick ≈ exp(tick * 0.00009999500033)
    let ln10001 = BigDecimal.fromString('0.00009999500033');
    let exponent = BigDecimal.fromString(tick.toString()).times(ln10001);
    // Convert to f64 for exp computation, then back
    let expValue = Math.exp(parseFloat(exponent.toString()));
    price = BigDecimal.fromString(expValue.toString());
  }

  if (tick < 0) {
    price = ONE_BD.div(price);
  }

  return price;
}

export function feeTierToTickSpacing(feeTier: i32): i32 {
  if (feeTier == 100) return 1;
  if (feeTier == 500) return 10;
  if (feeTier == 2500) return 50;
  if (feeTier == 3000) return 60;
  if (feeTier == 5000) return 100;
  if (feeTier == 10000) return 200;
  if (feeTier == 20000) return 400;
  if (feeTier == 50000) return 1000;
  return 60; // default
}
