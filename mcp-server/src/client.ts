import {
  createPublicClient,
  createWalletClient,
  http,
  type Address,
  type TransactionReceipt,
  type Hash,
} from 'viem';
import { privateKeyToAccount, type PrivateKeyAccount } from 'viem/accounts';
import { ink } from './config.js';

// ── Public Client (always available) ──────────────────────────────────
export const publicClient = createPublicClient({
  chain: ink,
  transport: http(),
});

// ── Wallet Client (requires PRIVATE_KEY) ──────────────────────────────
let _walletClient: ReturnType<typeof createWalletClient> | null = null;
let _account: PrivateKeyAccount | null = null;

function ensureWallet() {
  if (_walletClient && _account) return { walletClient: _walletClient, account: _account };

  const pk = process.env.PRIVATE_KEY;
  if (!pk) throw new Error('PRIVATE_KEY env var is required for write operations');

  _account = privateKeyToAccount(pk as `0x${string}`);
  _walletClient = createWalletClient({
    account: _account,
    chain: ink,
    transport: http(),
  });

  return { walletClient: _walletClient, account: _account };
}

export function getAccount(): Address {
  return ensureWallet().account.address;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function getWalletClient(): any {
  return ensureWallet().walletClient;
}

// ── Send Transaction Helper ───────────────────────────────────────────
export async function sendTx(params: {
  to: Address;
  data: `0x${string}`;
  value?: bigint;
}): Promise<{ hash: Hash; receipt: TransactionReceipt }> {
  const { walletClient, account } = ensureWallet();

  const gas = await publicClient.estimateGas({
    account: account.address,
    to: params.to,
    data: params.data,
    value: params.value ?? 0n,
  });

  const hash = await walletClient.sendTransaction({
    to: params.to,
    data: params.data,
    value: params.value ?? 0n,
    gas: (gas * 120n) / 100n, // 20% buffer
  } as any);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return { hash, receipt };
}

// ── Stringify helper for BigInt values ─────────────────────────────────
export function serializeBigInts(obj: unknown): unknown {
  if (typeof obj === 'bigint') return obj.toString();
  if (Array.isArray(obj)) return obj.map(serializeBigInts);
  if (obj !== null && typeof obj === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
      result[key] = serializeBigInts(value);
    }
    return result;
  }
  return obj;
}
