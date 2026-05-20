import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const SUBGRAPH_URL =
  process.env.TSUNAMI_SUBGRAPH_URL ||
  'https://api.goldsky.com/api/public/project_cmm7vh5xwsa8m01qmdr7w7u62/subgraphs/tsunami-v3/2.4.0/gn';

const OUT = process.env.POOLS_JSON_PATH || 'script/governance/pools.json';

const QUERY = `
  query Pools($first: Int!, $skip: Int!) {
    pools(first: $first, skip: $skip, orderBy: createdAtTimestamp, orderDirection: asc) {
      id
      feeTier
      tickSpacing
    }
  }
`;

async function fetchPage(skip: number) {
  const res = await fetch(SUBGRAPH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: QUERY, variables: { first: 1000, skip } }),
  });
  if (!res.ok) throw new Error(`subgraph ${res.status}`);
  const json: any = await res.json();
  if (json.errors?.length) throw new Error(json.errors[0].message);
  return json.data?.pools ?? [];
}

async function main() {
  const out: Array<{ address_: string; fee: number; tickSpacing: number }> = [];
  for (let skip = 0; ; skip += 1000) {
    const rows = await fetchPage(skip);
    out.push(...rows.map((p: any) => ({
      address_: p.id,
      fee: Number(p.feeTier),
      tickSpacing: Number(p.tickSpacing),
    })));
    if (rows.length < 1000) break;
  }

  const target = resolve(OUT);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, JSON.stringify(out, null, 2));
  console.log(`wrote ${out.length} pools to ${target}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
