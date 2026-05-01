import { BigInt, Address, Bytes, ethereum } from '@graphprotocol/graph-ts';
import {
  IncreaseLiquidity,
  DecreaseLiquidity,
  Collect,
  Transfer,
} from '../../generated/NonfungiblePositionManager/NonfungiblePositionManager';
import { NonfungiblePositionManager as PositionManagerContract } from '../../generated/NonfungiblePositionManager/NonfungiblePositionManager';
import { Position, Pool, Token, Transaction } from '../../generated/schema';
import { Factory as FactoryContract } from '../../generated/Factory/Factory';
import {
  FACTORY_ADDRESS,
  POSITION_MANAGER_ADDRESS,
  ZERO_BI,
  ZERO_BD,
  ADDRESS_ZERO,
} from '../utils/constants';
import { convertTokenToDecimal } from '../utils/pricing';

/* ── Helpers ──────────────────────────────────────── */

function getPositionManagerContract(): PositionManagerContract {
  return PositionManagerContract.bind(Address.fromString(POSITION_MANAGER_ADDRESS));
}

function getFactoryContract(): FactoryContract {
  return FactoryContract.bind(Address.fromString(FACTORY_ADDRESS));
}

function getPositionPool(token0: string, token1: string, fee: i32): string | null {
  let factory = getFactoryContract();
  let poolResult = factory.try_getPool(
    Address.fromString(token0),
    Address.fromString(token1),
    fee
  );
  if (poolResult.reverted) return null;
  let poolAddress = poolResult.value.toHexString();
  if (poolAddress == ADDRESS_ZERO) return null;
  return poolAddress;
}

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

/* ── Transfer (NFT ownership change, including mint) ─ */
export function handleTransfer(event: Transfer): void {
  let tokenId = event.params.tokenId;
  let from = event.params.from;
  let to = event.params.to;

  // Check if this is a new mint (from == address(0))
  let position = Position.load(tokenId.toString());

  if (from.toHexString() == ADDRESS_ZERO) {
    // New position minted — read on-chain data
    let positionManager = getPositionManagerContract();
    let posResult = positionManager.try_positions(tokenId);
    if (posResult.reverted) return;

    let posData = posResult.value;
    let token0Address = posData.getToken0().toHexString();
    let token1Address = posData.getToken1().toHexString();
    let fee = posData.getFee();

    let poolAddress = getPositionPool(token0Address, token1Address, fee);
    if (poolAddress === null) return;

    let pool = Pool.load(poolAddress);
    if (pool === null) return;

    // Create tick IDs
    let tickLower = posData.getTickLower();
    let tickUpper = posData.getTickUpper();
    let lowerTickId = poolAddress.concat('#').concat(tickLower.toString());
    let upperTickId = poolAddress.concat('#').concat(tickUpper.toString());

    let transaction = loadOrCreateTransaction(event);

    position = new Position(tokenId.toString());
    position.owner = to;
    position.pool = poolAddress;
    position.token0 = token0Address;
    position.token1 = token1Address;
    position.tickLower = lowerTickId;
    position.tickUpper = upperTickId;
    position.liquidity = ZERO_BI;
    position.depositedToken0 = ZERO_BD;
    position.depositedToken1 = ZERO_BD;
    position.withdrawnToken0 = ZERO_BD;
    position.withdrawnToken1 = ZERO_BD;
    position.collectedFeesToken0 = ZERO_BD;
    position.collectedFeesToken1 = ZERO_BD;
    position.feeGrowthInside0LastX128 = posData.getFeeGrowthInside0LastX128();
    position.feeGrowthInside1LastX128 = posData.getFeeGrowthInside1LastX128();
    position.transaction = transaction.id;
  }

  if (position !== null) {
    position.owner = to;
    position.save();
  }
}

/* ── IncreaseLiquidity ───────────────────────────── */
export function handleIncreaseLiquidity(event: IncreaseLiquidity): void {
  let position = Position.load(event.params.tokenId.toString());
  if (position === null) return;

  let token0 = Token.load(position.token0);
  let token1 = Token.load(position.token1);
  if (token0 === null || token1 === null) return;

  let amount0 = convertTokenToDecimal(event.params.amount0, token0.decimals);
  let amount1 = convertTokenToDecimal(event.params.amount1, token1.decimals);

  position.liquidity = position.liquidity.plus(event.params.liquidity);
  position.depositedToken0 = position.depositedToken0.plus(amount0);
  position.depositedToken1 = position.depositedToken1.plus(amount1);

  // Re-read fee growth from chain
  let positionManager = getPositionManagerContract();
  let posResult = positionManager.try_positions(event.params.tokenId);
  if (!posResult.reverted) {
    let posData = posResult.value;
    position.feeGrowthInside0LastX128 = posData.getFeeGrowthInside0LastX128();
    position.feeGrowthInside1LastX128 = posData.getFeeGrowthInside1LastX128();
  }

  position.save();
}

/* ── DecreaseLiquidity ───────────────────────────── */
export function handleDecreaseLiquidity(event: DecreaseLiquidity): void {
  let position = Position.load(event.params.tokenId.toString());
  if (position === null) return;

  let token0 = Token.load(position.token0);
  let token1 = Token.load(position.token1);
  if (token0 === null || token1 === null) return;

  let amount0 = convertTokenToDecimal(event.params.amount0, token0.decimals);
  let amount1 = convertTokenToDecimal(event.params.amount1, token1.decimals);

  position.liquidity = position.liquidity.minus(event.params.liquidity);
  position.withdrawnToken0 = position.withdrawnToken0.plus(amount0);
  position.withdrawnToken1 = position.withdrawnToken1.plus(amount1);

  let positionManager = getPositionManagerContract();
  let posResult = positionManager.try_positions(event.params.tokenId);
  if (!posResult.reverted) {
    let posData = posResult.value;
    position.feeGrowthInside0LastX128 = posData.getFeeGrowthInside0LastX128();
    position.feeGrowthInside1LastX128 = posData.getFeeGrowthInside1LastX128();
  }

  position.save();
}

/* ── Collect (fees from position manager) ──────────── */
export function handleCollect(event: Collect): void {
  let position = Position.load(event.params.tokenId.toString());
  if (position === null) return;

  let token0 = Token.load(position.token0);
  let token1 = Token.load(position.token1);
  if (token0 === null || token1 === null) return;

  let amount0 = convertTokenToDecimal(event.params.amount0, token0.decimals);
  let amount1 = convertTokenToDecimal(event.params.amount1, token1.decimals);

  position.collectedFeesToken0 = position.collectedFeesToken0.plus(amount0);
  position.collectedFeesToken1 = position.collectedFeesToken1.plus(amount1);

  let positionManager = getPositionManagerContract();
  let posResult = positionManager.try_positions(event.params.tokenId);
  if (!posResult.reverted) {
    let posData = posResult.value;
    position.feeGrowthInside0LastX128 = posData.getFeeGrowthInside0LastX128();
    position.feeGrowthInside1LastX128 = posData.getFeeGrowthInside1LastX128();
  }

  position.save();
}
