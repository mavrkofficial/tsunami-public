import { Address, BigInt } from '@graphprotocol/graph-ts';
import { ERC20 } from '../../generated/Factory/ERC20';
import { ERC20SymbolBytes } from '../../generated/Factory/ERC20SymbolBytes';
import { ERC20NameBytes } from '../../generated/Factory/ERC20NameBytes';

export function fetchTokenSymbol(tokenAddress: Address): string {
  let contract = ERC20.bind(tokenAddress);
  let symbolResult = contract.try_symbol();
  if (!symbolResult.reverted) {
    return symbolResult.value;
  }

  // Fallback: some tokens return bytes32 for symbol
  let bytesContract = ERC20SymbolBytes.bind(tokenAddress);
  let bytesResult = bytesContract.try_symbol();
  if (!bytesResult.reverted) {
    return bytesResult.value.toString();
  }

  return 'unknown';
}

export function fetchTokenName(tokenAddress: Address): string {
  let contract = ERC20.bind(tokenAddress);
  let nameResult = contract.try_name();
  if (!nameResult.reverted) {
    return nameResult.value;
  }

  // Fallback: bytes32
  let bytesContract = ERC20NameBytes.bind(tokenAddress);
  let bytesResult = bytesContract.try_name();
  if (!bytesResult.reverted) {
    return bytesResult.value.toString();
  }

  return 'unknown';
}

export function fetchTokenTotalSupply(tokenAddress: Address): BigInt {
  let contract = ERC20.bind(tokenAddress);
  let result = contract.try_totalSupply();
  if (!result.reverted) {
    return result.value;
  }
  return BigInt.fromI32(0);
}

export function fetchTokenDecimals(tokenAddress: Address): BigInt {
  let contract = ERC20.bind(tokenAddress);
  let result = contract.try_decimals();
  if (!result.reverted) {
    return BigInt.fromI32(result.value);
  }
  return BigInt.fromI32(18); // default to 18
}
