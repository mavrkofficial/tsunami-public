import { BigDecimal, BigInt } from '@graphprotocol/graph-ts';
import { Bundle, Pool, Token } from '../../generated/schema';
import {
  ZERO_BD,
  ZERO_BI,
  ONE_BD,
  WETH_ADDRESS,
  STABLECOIN_ADDRESSES,
  MINIMUM_ETH_LOCKED,
} from './constants';

/**
 * Derives the ETH price in USD by finding the most liquid WETH/stablecoin
 * pool and reading its current price.
 */
export function getEthPriceInUSD(): BigDecimal {
  if (STABLECOIN_ADDRESSES.length == 0) {
    return ZERO_BD;
  }

  let wethToken = Token.load(WETH_ADDRESS);
  if (wethToken === null) return ZERO_BD;

  let largestLiquidity = ZERO_BD;
  let ethPriceUSD = ZERO_BD;

  let pools = wethToken.whitelistPools;
  for (let i = 0; i < pools.length; i++) {
    let pool = Pool.load(pools[i]);
    if (pool === null) continue;
    if (pool.liquidity.equals(ZERO_BI)) continue;

    if (pool.token0 == WETH_ADDRESS) {
      // stablecoin is token1 — token1Price = stablecoin per WETH = ETH/USD
      if (STABLECOIN_ADDRESSES.indexOf(pool.token1) !== -1) {
        let wethLocked = pool.totalValueLockedToken0;
        if (wethLocked.gt(largestLiquidity)) {
          largestLiquidity = wethLocked;
          ethPriceUSD = pool.token1Price;
        }
      }
    } else {
      // WETH is token1, stablecoin is token0 — token0Price = stablecoin per WETH = ETH/USD
      if (STABLECOIN_ADDRESSES.indexOf(pool.token0) !== -1) {
        let wethLocked = pool.totalValueLockedToken1;
        if (wethLocked.gt(largestLiquidity)) {
          largestLiquidity = wethLocked;
          ethPriceUSD = pool.token0Price;
        }
      }
    }
  }

  return ethPriceUSD;
}

/**
 * Returns the price of a token in ETH by walking through its whitelist pools.
 */
export function findEthPerToken(token: Token): BigDecimal {
  if (token.id == WETH_ADDRESS) {
    return ONE_BD;
  }

  let whitelistPools = token.whitelistPools;
  let largestLiquidityETH = ZERO_BD;
  let priceSoFar = ZERO_BD;

  let bundle = Bundle.load('1');
  let ethPriceUSD = bundle ? bundle.ethPriceUSD : ZERO_BD;

  for (let i = 0; i < whitelistPools.length; i++) {
    let pool = Pool.load(whitelistPools[i]);
    if (pool === null) continue;

    if (pool.liquidity.gt(BigInt.fromI32(0))) {
      if (pool.token0 == token.id) {
        // token is token0 in this pool
        let token1 = Token.load(pool.token1);
        if (token1 === null) continue;
        let ethLocked = pool.totalValueLockedToken1.times(token1.derivedETH);
        if (ethLocked.gt(largestLiquidityETH) && ethLocked.gt(MINIMUM_ETH_LOCKED)) {
          largestLiquidityETH = ethLocked;
          priceSoFar = pool.token0Price.gt(ZERO_BD)
            ? pool.token1Price.times(token1.derivedETH)
            : ZERO_BD;
        }
      }
      if (pool.token1 == token.id) {
        let token0 = Token.load(pool.token0);
        if (token0 === null) continue;
        let ethLocked = pool.totalValueLockedToken0.times(token0.derivedETH);
        if (ethLocked.gt(largestLiquidityETH) && ethLocked.gt(MINIMUM_ETH_LOCKED)) {
          largestLiquidityETH = ethLocked;
          priceSoFar = pool.token1Price.gt(ZERO_BD)
            ? pool.token0Price.times(token0.derivedETH)
            : ZERO_BD;
        }
      }
    }
  }

  return priceSoFar;
}

/**
 * Compute the USD amount for a swap given the token amounts and their ETH prices.
 */
export function getTrackedAmountUSD(
  tokenAmount0: BigDecimal,
  token0: Token,
  tokenAmount1: BigDecimal,
  token1: Token
): BigDecimal {
  let bundle = Bundle.load('1');
  if (bundle === null) return ZERO_BD;

  let price0USD = token0.derivedETH.times(bundle.ethPriceUSD);
  let price1USD = token1.derivedETH.times(bundle.ethPriceUSD);

  // Both tokens have derived prices — take the average
  if (price0USD.gt(ZERO_BD) && price1USD.gt(ZERO_BD)) {
    return tokenAmount0
      .times(price0USD)
      .plus(tokenAmount1.times(price1USD))
      .div(BigDecimal.fromString('2'));
  }

  // One token has a price
  if (price0USD.gt(ZERO_BD)) {
    return tokenAmount0.times(price0USD);
  }
  if (price1USD.gt(ZERO_BD)) {
    return tokenAmount1.times(price1USD);
  }

  return ZERO_BD;
}

/**
 * sqrt price X96 → token prices
 */
export function sqrtPriceX96ToTokenPrices(
  sqrtPriceX96: BigInt,
  token0: Token,
  token1: Token
): BigDecimal[] {
  let num = sqrtPriceX96.times(sqrtPriceX96).toBigDecimal();
  let Q192 = BigInt.fromI32(2).pow(192).toBigDecimal();

  let decimals0 = token0.decimals.toI32();
  let decimals1 = token1.decimals.toI32();

  let decimalAdjust = BigInt.fromI32(10)
    .pow(u8(decimals0))
    .toBigDecimal()
    .div(BigInt.fromI32(10).pow(u8(decimals1)).toBigDecimal());

  let price1 = num.div(Q192).times(decimalAdjust);
  let price0 = price1.gt(ZERO_BD) ? ONE_BD.div(price1) : ZERO_BD;

  return [price0, price1];
}

/**
 * Convert a raw token amount to a BigDecimal adjusted for decimals.
 */
export function convertTokenToDecimal(tokenAmount: BigInt, exchangeDecimals: BigInt): BigDecimal {
  if (exchangeDecimals == BigInt.fromI32(0)) {
    return tokenAmount.toBigDecimal();
  }
  return tokenAmount.toBigDecimal().div(exponentToBigDecimal(exchangeDecimals));
}

export function exponentToBigDecimal(decimals: BigInt): BigDecimal {
  let result = BigDecimal.fromString('1');
  for (let i = BigInt.fromI32(0); i.lt(decimals); i = i.plus(BigInt.fromI32(1))) {
    result = result.times(BigDecimal.fromString('10'));
  }
  return result;
}
