import { type Address } from 'viem';
import { publicClient, getAccount, getWalletClient, serializeBigInts } from '../client.js';
import { CONTRACTS } from '../config.js';
import { CitadelABI } from '../abis/Citadel.js';
import { TsunamiV3PositionManagerABI } from '../abis/TsunamiV3PositionManager.js';

const CITADEL = CONTRACTS.Citadel as Address;
const NPM = CONTRACTS.TsunamiV3PositionManager as Address;

export const citadelTools = [
  {
    name: 'citadel_lock_lp',
    description: 'Lock an LP NFT in the Citadel with a specified unlock time. Requires NFT approval first.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        tokenId: { type: 'string', description: 'LP NFT token ID' },
        unlockTime: { type: 'number', description: 'Unix timestamp when the lock expires' },
      },
      required: ['tokenId', 'unlockTime'],
    },
  },
  {
    name: 'citadel_unlock',
    description: 'Unlock an LP NFT from the Citadel (only works if unlock time has passed).',
    inputSchema: {
      type: 'object' as const,
      properties: {
        tokenId: { type: 'string', description: 'LP NFT token ID' },
      },
      required: ['tokenId'],
    },
  },
  {
    name: 'citadel_collect_fees',
    description: 'Collect accrued trading fees from locked LP positions. Supports batch collection.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        tokenIds: { type: 'array', items: { type: 'string' }, description: 'Array of LP NFT token IDs' },
      },
      required: ['tokenIds'],
    },
  },
  {
    name: 'citadel_get_lock_info',
    description: 'Get lock details for an LP NFT: locker, treasury, timestamps, isSentryLaunch.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        tokenId: { type: 'string', description: 'LP NFT token ID' },
      },
      required: ['tokenId'],
    },
  },
  {
    name: 'citadel_get_locker_nfts',
    description: 'Get all LP NFTs locked by a specific address.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        owner: { type: 'string', description: 'Address to query (defaults to wallet)' },
      },
    },
  },
  {
    name: 'citadel_is_locked',
    description: 'Check if an LP NFT is currently locked in the Citadel.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        tokenId: { type: 'string', description: 'LP NFT token ID' },
      },
      required: ['tokenId'],
    },
  },
  {
    name: 'citadel_is_unlockable',
    description: 'Check if a locked LP NFT can be unlocked (unlock time passed).',
    inputSchema: {
      type: 'object' as const,
      properties: {
        tokenId: { type: 'string', description: 'LP NFT token ID' },
      },
      required: ['tokenId'],
    },
  },
  {
    name: 'citadel_get_stats',
    description: 'Get Citadel aggregate stats: total locked count and total Sentry locks.',
    inputSchema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'citadel_supply_tydro',
    description: 'Supply tokens to the Tydro pool via Citadel. Admin only.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        token: { type: 'string', description: 'Token address to supply' },
        amount: { type: 'string', description: 'Amount in wei' },
      },
      required: ['token', 'amount'],
    },
  },
];

export async function handleCitadelTool(name: string, args: Record<string, unknown>) {
  switch (name) {
    case 'citadel_lock_lp': {
      const tokenId = BigInt(args.tokenId as string);
      const unlockTime = BigInt(args.unlockTime as number);
      const walletClient = getWalletClient();

      // Approve Citadel to transfer the NFT
      const approveHash = await walletClient.writeContract({
        address: NPM, abi: TsunamiV3PositionManagerABI, functionName: 'approve',
        args: [CITADEL, tokenId],
      });
      await publicClient.waitForTransactionReceipt({ hash: approveHash });

      // Transfer NFT to Citadel then lock
      const account = getAccount();
      const transferHash = await walletClient.writeContract({
        address: NPM, abi: TsunamiV3PositionManagerABI, functionName: 'safeTransferFrom',
        args: [account, CITADEL, tokenId],
      });
      await publicClient.waitForTransactionReceipt({ hash: transferHash });

      const lockHash = await walletClient.writeContract({
        address: CITADEL, abi: CitadelABI, functionName: 'lockLP',
        args: [tokenId, unlockTime],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash: lockHash });
      return { hash: lockHash, status: receipt.status, tokenId: tokenId.toString(), unlockTime: unlockTime.toString() };
    }

    case 'citadel_unlock': {
      const tokenId = BigInt(args.tokenId as string);
      const walletClient = getWalletClient();
      const hash = await walletClient.writeContract({
        address: CITADEL, abi: CitadelABI, functionName: 'unlock', args: [tokenId],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      return { hash, status: receipt.status, tokenId: tokenId.toString() };
    }

    case 'citadel_collect_fees': {
      const tokenIds = (args.tokenIds as string[]).map(BigInt);
      const walletClient = getWalletClient();
      let hash;
      if (tokenIds.length === 1) {
        hash = await walletClient.writeContract({
          address: CITADEL, abi: CitadelABI, functionName: 'collectFees', args: [tokenIds[0]],
        });
      } else {
        hash = await walletClient.writeContract({
          address: CITADEL, abi: CitadelABI, functionName: 'collectBatchFees', args: [tokenIds],
        });
      }
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      return { hash, status: receipt.status, tokenIds: tokenIds.map(String) };
    }

    case 'citadel_get_lock_info': {
      const tokenId = BigInt(args.tokenId as string);
      const info = await publicClient.readContract({
        address: CITADEL, abi: CitadelABI, functionName: 'getLockInfo', args: [tokenId],
      });
      return serializeBigInts(info);
    }

    case 'citadel_get_locker_nfts': {
      const owner = (args.owner as Address) ?? getAccount();
      const nfts = await publicClient.readContract({
        address: CITADEL, abi: CitadelABI, functionName: 'getLockerNFTs', args: [owner],
      });
      return { owner, nfts: (nfts as bigint[]).map(String) };
    }

    case 'citadel_is_locked': {
      const tokenId = BigInt(args.tokenId as string);
      const locked = await publicClient.readContract({
        address: CITADEL, abi: CitadelABI, functionName: 'isLocked', args: [tokenId],
      });
      return { tokenId: tokenId.toString(), isLocked: locked };
    }

    case 'citadel_is_unlockable': {
      const tokenId = BigInt(args.tokenId as string);
      const unlockable = await publicClient.readContract({
        address: CITADEL, abi: CitadelABI, functionName: 'isUnlockable', args: [tokenId],
      });
      return { tokenId: tokenId.toString(), isUnlockable: unlockable };
    }

    case 'citadel_get_stats': {
      const [totalLocked, totalSentry] = await Promise.all([
        publicClient.readContract({ address: CITADEL, abi: CitadelABI, functionName: 'getTotalLockedCount' }),
        publicClient.readContract({ address: CITADEL, abi: CitadelABI, functionName: 'getTotalSentryLocks' }),
      ]);
      return { totalLockedCount: totalLocked.toString(), totalSentryLocks: totalSentry.toString() };
    }

    case 'citadel_supply_tydro': {
      const token = args.token as Address;
      const amount = BigInt(args.amount as string);
      const walletClient = getWalletClient();
      const hash = await walletClient.writeContract({
        address: CITADEL, abi: CitadelABI, functionName: 'supplyToTydro', args: [token, amount],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      return { hash, status: receipt.status };
    }

    default:
      throw new Error(`Unknown citadel tool: ${name}`);
  }
}
