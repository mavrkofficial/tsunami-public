import { type Address, formatUnits, maxUint256 } from 'viem';
import { publicClient, getAccount, getWalletClient, serializeBigInts } from '../client.js';
import { ERC20ABI } from '../abis/ERC20.js';

export const erc20Tools = [
  {
    name: 'erc20_balance',
    description: 'Get ERC20 token balance for an address. Returns balance, decimals, symbol, and formatted amount.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        token: { type: 'string', description: 'Token contract address' },
        owner: { type: 'string', description: 'Address to check balance for (defaults to wallet)' },
      },
      required: ['token'],
    },
  },
  {
    name: 'erc20_allowance',
    description: 'Get current ERC20 allowance for a spender.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        token: { type: 'string', description: 'Token contract address' },
        spender: { type: 'string', description: 'Spender address to check allowance for' },
        owner: { type: 'string', description: 'Owner address (defaults to wallet)' },
      },
      required: ['token', 'spender'],
    },
  },
  {
    name: 'erc20_approve',
    description: 'Approve a spender to use ERC20 tokens. Use amount "max" for unlimited approval.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        token: { type: 'string', description: 'Token contract address' },
        spender: { type: 'string', description: 'Spender address to approve' },
        amount: { type: 'string', description: 'Amount in wei, or "max" for unlimited' },
      },
      required: ['token', 'spender', 'amount'],
    },
  },
  {
    name: 'erc20_transfer',
    description: 'Transfer ERC20 tokens to an address.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        token: { type: 'string', description: 'Token contract address' },
        to: { type: 'string', description: 'Recipient address' },
        amount: { type: 'string', description: 'Amount in wei' },
      },
      required: ['token', 'to', 'amount'],
    },
  },
];

export async function handleErc20Tool(name: string, args: Record<string, unknown>) {
  switch (name) {
    case 'erc20_balance': {
      const token = args.token as Address;
      const owner = (args.owner as Address) ?? getAccount();
      const [balance, decimals, symbol] = await Promise.all([
        publicClient.readContract({ address: token, abi: ERC20ABI, functionName: 'balanceOf', args: [owner] }),
        publicClient.readContract({ address: token, abi: ERC20ABI, functionName: 'decimals' }),
        publicClient.readContract({ address: token, abi: ERC20ABI, functionName: 'symbol' }),
      ]);
      return { balance: balance.toString(), decimals, symbol, formatted: formatUnits(balance, decimals), owner };
    }

    case 'erc20_allowance': {
      const token = args.token as Address;
      const owner = (args.owner as Address) ?? getAccount();
      const spender = args.spender as Address;
      const [allowance, decimals] = await Promise.all([
        publicClient.readContract({ address: token, abi: ERC20ABI, functionName: 'allowance', args: [owner, spender] }),
        publicClient.readContract({ address: token, abi: ERC20ABI, functionName: 'decimals' }),
      ]);
      return { allowance: allowance.toString(), formatted: formatUnits(allowance, decimals), owner, spender };
    }

    case 'erc20_approve': {
      const token = args.token as Address;
      const spender = args.spender as Address;
      const amount = args.amount === 'max' ? maxUint256 : BigInt(args.amount as string);
      const walletClient = getWalletClient();
      const hash = await walletClient.writeContract({
        address: token, abi: ERC20ABI, functionName: 'approve', args: [spender, amount],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      return { hash, status: receipt.status, spender, amount: amount.toString() };
    }

    case 'erc20_transfer': {
      const token = args.token as Address;
      const to = args.to as Address;
      const amount = BigInt(args.amount as string);
      const walletClient = getWalletClient();
      const hash = await walletClient.writeContract({
        address: token, abi: ERC20ABI, functionName: 'transfer', args: [to, amount],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      return { hash, status: receipt.status, to, amount: amount.toString() };
    }

    default:
      throw new Error(`Unknown erc20 tool: ${name}`);
  }
}
