import { SUBGRAPH_URL } from '../config.js';

async function querySubgraph(query: string, variables?: Record<string, unknown>) {
  const res = await fetch(SUBGRAPH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) throw new Error(`Subgraph request failed: ${res.status}`);
  const json = await res.json();
  if (json.errors) throw new Error(json.errors[0]?.message || 'Subgraph query error');
  return json.data;
}

export const subgraphTools = [
  {
    name: 'subgraph_protocol_stats',
    description: 'Get Tsunami protocol-level stats: pool count, total volume, TVL, fees, tx count.',
    inputSchema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'subgraph_pools',
    description: 'Get list of pools with TVL, volume, fees, token info. Supports pagination and sorting.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        first: { type: 'number', description: 'Number of pools to return (default 20)' },
        skip: { type: 'number', description: 'Number of pools to skip (default 0)' },
        orderBy: { type: 'string', description: 'Field to sort by (default totalValueLockedUSD)' },
        orderDirection: { type: 'string', description: 'asc or desc (default desc)' },
      },
    },
  },
  {
    name: 'subgraph_recent_swaps',
    description: 'Get recent swaps across all pools.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        first: { type: 'number', description: 'Number of swaps (default 20)' },
      },
    },
  },
  {
    name: 'subgraph_user_positions',
    description: 'Get LP positions for a specific wallet address from the subgraph.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        owner: { type: 'string', description: 'Wallet address to query positions for' },
      },
      required: ['owner'],
    },
  },
  {
    name: 'subgraph_user_transactions',
    description: 'Get recent swaps, mints, and burns for a specific wallet address.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        origin: { type: 'string', description: 'Wallet address' },
        first: { type: 'number', description: 'Number of results per type (default 20)' },
      },
      required: ['origin'],
    },
  },
  {
    name: 'subgraph_daily_data',
    description: 'Get historical daily protocol data (volume, fees, TVL, tx count).',
    inputSchema: {
      type: 'object' as const,
      properties: {
        first: { type: 'number', description: 'Number of days (default 30)' },
      },
    },
  },
];

export async function handleSubgraphTool(name: string, args: Record<string, unknown>) {
  switch (name) {
    case 'subgraph_protocol_stats': {
      const data = await querySubgraph(`
        query { factories(first: 1) {
          poolCount txCount totalVolumeUSD totalFeesUSD totalValueLockedUSD totalValueLockedETH
        }}
      `);
      return data.factories[0] ?? {};
    }

    case 'subgraph_pools': {
      const first = (args.first as number) ?? 20;
      const skip = (args.skip as number) ?? 0;
      const orderBy = (args.orderBy as string) ?? 'totalValueLockedUSD';
      const orderDirection = (args.orderDirection as string) ?? 'desc';
      return await querySubgraph(`
        query($first: Int!, $skip: Int!, $orderBy: Pool_orderBy, $orderDirection: OrderDirection) {
          pools(first: $first, skip: $skip, orderBy: $orderBy, orderDirection: $orderDirection) {
            id token0 { id symbol name decimals } token1 { id symbol name decimals }
            feeTier liquidity sqrtPrice tick token0Price token1Price
            volumeUSD feesUSD totalValueLockedUSD txCount
          }
        }
      `, { first, skip, orderBy, orderDirection });
    }

    case 'subgraph_recent_swaps': {
      const first = (args.first as number) ?? 20;
      return await querySubgraph(`
        query($first: Int!) {
          swaps(first: $first, orderBy: timestamp, orderDirection: desc) {
            id timestamp pool { token0 { symbol } token1 { symbol } }
            sender recipient origin amount0 amount1 amountUSD
            transaction { id }
          }
        }
      `, { first });
    }

    case 'subgraph_user_positions': {
      const owner = (args.owner as string).toLowerCase();
      return await querySubgraph(`
        query($owner: Bytes!) {
          positions(where: { owner: $owner, liquidity_gt: "0" }) {
            id owner liquidity depositedToken0 depositedToken1
            withdrawnToken0 withdrawnToken1 collectedFeesToken0 collectedFeesToken1
            pool { id token0 { id symbol decimals } token1 { id symbol decimals } feeTier tick sqrtPrice }
            tickLower { tickIdx } tickUpper { tickIdx }
          }
        }
      `, { owner });
    }

    case 'subgraph_user_transactions': {
      const origin = (args.origin as string).toLowerCase();
      const first = (args.first as number) ?? 20;
      return await querySubgraph(`
        query($origin: Bytes!, $first: Int!) {
          swaps(first: $first, orderBy: timestamp, orderDirection: desc, where: { origin: $origin }) {
            id timestamp amount0 amount1 amountUSD pool { token0 { symbol } token1 { symbol } } transaction { id }
          }
          mints(first: $first, orderBy: timestamp, orderDirection: desc, where: { origin: $origin }) {
            id timestamp amount0 amount1 amountUSD pool { token0 { symbol } token1 { symbol } } transaction { id }
          }
          burns(first: $first, orderBy: timestamp, orderDirection: desc, where: { origin: $origin }) {
            id timestamp amount0 amount1 amountUSD pool { token0 { symbol } token1 { symbol } } transaction { id }
          }
        }
      `, { origin, first });
    }

    case 'subgraph_daily_data': {
      const first = (args.first as number) ?? 30;
      return await querySubgraph(`
        query($first: Int!) {
          tsunamiDayDatas(first: $first, orderBy: date, orderDirection: desc) {
            date volumeUSD feesUSD tvlUSD txCount
          }
        }
      `, { first });
    }

    default:
      throw new Error(`Unknown subgraph tool: ${name}`);
  }
}
