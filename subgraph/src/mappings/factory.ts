import { BigInt, Address } from '@graphprotocol/graph-ts';
import { PoolCreated } from '../../generated/Factory/Factory';
import { Pool as PoolTemplate } from '../../generated/templates';
import { Factory, Pool, Token, Bundle } from '../../generated/schema';
import {
  FACTORY_ADDRESS,
  ZERO_BI,
  ZERO_BD,
  ONE_BI,
  WETH_ADDRESS,
  WHITELIST_TOKENS,
} from '../utils/constants';
import {
  fetchTokenSymbol,
  fetchTokenName,
  fetchTokenDecimals,
  fetchTokenTotalSupply,
} from '../utils/token';

export function handlePoolCreated(event: PoolCreated): void {
  // 1. Load or create Factory entity
  let factory = Factory.load(FACTORY_ADDRESS);
  if (factory === null) {
    factory = new Factory(FACTORY_ADDRESS);
    factory.poolCount = ZERO_BI;
    factory.totalVolumeETH = ZERO_BD;
    factory.totalVolumeUSD = ZERO_BD;
    factory.totalFeesUSD = ZERO_BD;
    factory.totalFeesETH = ZERO_BD;
    factory.totalValueLockedETH = ZERO_BD;
    factory.totalValueLockedUSD = ZERO_BD;
    factory.txCount = ZERO_BI;
    factory.owner = FACTORY_ADDRESS;

    // Create the ETH price bundle
    let bundle = new Bundle('1');
    bundle.ethPriceUSD = ZERO_BD;
    bundle.save();
  }

  factory.poolCount = factory.poolCount.plus(ONE_BI);

  // 2. Load or create Token entities
  let token0 = Token.load(event.params.token0.toHexString());
  let token1 = Token.load(event.params.token1.toHexString());

  if (token0 === null) {
    token0 = new Token(event.params.token0.toHexString());
    token0.symbol = fetchTokenSymbol(event.params.token0);
    token0.name = fetchTokenName(event.params.token0);
    token0.totalSupply = fetchTokenTotalSupply(event.params.token0);
    token0.decimals = fetchTokenDecimals(event.params.token0);
    token0.derivedETH = ZERO_BD;
    token0.volume = ZERO_BD;
    token0.volumeUSD = ZERO_BD;
    token0.untrackedVolumeUSD = ZERO_BD;
    token0.feesUSD = ZERO_BD;
    token0.txCount = ZERO_BI;
    token0.poolCount = ZERO_BI;
    token0.totalValueLocked = ZERO_BD;
    token0.totalValueLockedUSD = ZERO_BD;
    token0.totalValueLockedUSDUntracked = ZERO_BD;
    token0.whitelistPools = [];
  }

  if (token1 === null) {
    token1 = new Token(event.params.token1.toHexString());
    token1.symbol = fetchTokenSymbol(event.params.token1);
    token1.name = fetchTokenName(event.params.token1);
    token1.totalSupply = fetchTokenTotalSupply(event.params.token1);
    token1.decimals = fetchTokenDecimals(event.params.token1);
    token1.derivedETH = ZERO_BD;
    token1.volume = ZERO_BD;
    token1.volumeUSD = ZERO_BD;
    token1.untrackedVolumeUSD = ZERO_BD;
    token1.feesUSD = ZERO_BD;
    token1.txCount = ZERO_BI;
    token1.poolCount = ZERO_BI;
    token1.totalValueLocked = ZERO_BD;
    token1.totalValueLockedUSD = ZERO_BD;
    token1.totalValueLockedUSDUntracked = ZERO_BD;
    token1.whitelistPools = [];
  }

  // 3. Create Pool entity
  let pool = new Pool(event.params.pool.toHexString());
  pool.token0 = token0.id;
  pool.token1 = token1.id;
  pool.feeTier = BigInt.fromI32(event.params.fee);
  pool.createdAtTimestamp = event.block.timestamp;
  pool.createdAtBlockNumber = event.block.number;
  pool.liquidity = ZERO_BI;
  pool.sqrtPrice = ZERO_BI;
  pool.token0Price = ZERO_BD;
  pool.token1Price = ZERO_BD;
  pool.observationIndex = ZERO_BI;
  pool.tick = BigInt.fromI32(0);
  pool.volumeToken0 = ZERO_BD;
  pool.volumeToken1 = ZERO_BD;
  pool.volumeUSD = ZERO_BD;
  pool.untrackedVolumeUSD = ZERO_BD;
  pool.feesUSD = ZERO_BD;
  pool.txCount = ZERO_BI;
  pool.collectedFeesToken0 = ZERO_BD;
  pool.collectedFeesToken1 = ZERO_BD;
  pool.collectedFeesUSD = ZERO_BD;
  pool.totalValueLockedToken0 = ZERO_BD;
  pool.totalValueLockedToken1 = ZERO_BD;
  pool.totalValueLockedETH = ZERO_BD;
  pool.totalValueLockedUSD = ZERO_BD;
  pool.totalValueLockedUSDUntracked = ZERO_BD;
  pool.liquidityProviderCount = ZERO_BI;
  // Sentry attribution defaults to false. Flipped to true by
  // SentryLaunchFactory.handleSentryPoolInitialized when this pool is
  // seeded by the launchpad in the same tx.
  pool.isSentry = false;

  // 4. Update whitelist pools for ETH price derivation
  let poolAddress = event.params.pool.toHexString();

  // If either token is in WHITELIST_TOKENS, add this pool to the other token's whitelist
  let whitelistCheck0 = WHITELIST_TOKENS.indexOf(token0.id) !== -1;
  let whitelistCheck1 = WHITELIST_TOKENS.indexOf(token1.id) !== -1;

  if (whitelistCheck0) {
    let newPools = token1.whitelistPools;
    newPools.push(poolAddress);
    token1.whitelistPools = newPools;
  }
  if (whitelistCheck1) {
    let newPools = token0.whitelistPools;
    newPools.push(poolAddress);
    token0.whitelistPools = newPools;
  }

  // Increment pool count for each token
  token0.poolCount = token0.poolCount.plus(ONE_BI);
  token1.poolCount = token1.poolCount.plus(ONE_BI);

  // 5. Save everything
  pool.save();
  token0.save();
  token1.save();
  factory.save();

  // 6. Create dynamic data source to track pool events
  PoolTemplate.create(event.params.pool);
}
