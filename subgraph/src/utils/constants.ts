import { Address, BigDecimal, BigInt } from '@graphprotocol/graph-ts';

// ── Contract Addresses (Ink Chain 57073) — Tsunami V3 ──
export const FACTORY_ADDRESS = '0xD8B0826150B7686D1F56d6F10E31E58e1BCF1193';
export const POSITION_MANAGER_ADDRESS = '0x98b6267DA27c5A21Bd6e3edfBC2DA6b0428Fa9F7';

// WETH on Ink (OP Stack canonical WETH)
export const WETH_ADDRESS = '0x4200000000000000000000000000000000000006';

// ── Numeric Constants ────────────────────────────────
export const ZERO_BI = BigInt.fromI32(0);
export const ONE_BI = BigInt.fromI32(1);
export const ZERO_BD = BigDecimal.fromString('0');
export const ONE_BD = BigDecimal.fromString('1');
export const BI_18 = BigInt.fromI32(18);

export const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000';

// ── Stablecoins on Ink (chain 57073) ─────────────────
// USDC (bridged, proxy): 0x2d270e6886d130d724215a266106e6832161eaed
// USDT0:                 0x0200c29006150606b650577bbe7b6248f58470c1
// USDG:                  0xe343167631d89b6ffc58b88d6b7fb0228795491d
export const USDC_ADDRESS = '0x2d270e6886d130d724215a266106e6832161eaed';
export const USDT0_ADDRESS = '0x0200c29006150606b650577bbe7b6248f58470c1';
export const USDG_ADDRESS = '0xe343167631d89b6ffc58b88d6b7fb0228795491d';

// ── Stable coins for USD derivation ─────────────────
// Used by getEthPriceInUSD() to find a WETH/stablecoin pool.
export const STABLECOIN_ADDRESSES: string[] = [
  USDC_ADDRESS,
  USDT0_ADDRESS,
  USDG_ADDRESS,
];

// ── Whitelist tokens for ETH price tracking ─────────
// Any token in this list causes counterpart pools to be tracked
// for price derivation. Stablecoins must be here so WETH/stable
// pools get added to WETH's whitelistPools.
export const WHITELIST_TOKENS: string[] = [
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDT0_ADDRESS,
  USDG_ADDRESS,
];

// Minimum ETH locked in a pool to be considered for price tracking
export const MINIMUM_ETH_LOCKED = BigDecimal.fromString('0');
