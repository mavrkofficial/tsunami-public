export const SentryLaunchFactoryABI = [
  // ── Launch ──
  {
    type: "function", name: "launch", stateMutability: "nonpayable",
    inputs: [{ name: "_name", type: "string" }, { name: "_symbol", type: "string" }, { name: "baseToken", type: "address" }],
    outputs: [{ name: "tokenAddress", type: "address" }, { name: "tokenId", type: "uint256" }],
  },
  // ── Fee Collection ──
  {
    type: "function", name: "collectFees", stateMutability: "nonpayable",
    inputs: [{ name: "tokenId", type: "uint256" }], outputs: [],
  },
  {
    type: "function", name: "collectMultipleFees", stateMutability: "nonpayable",
    inputs: [{ name: "tokenIds", type: "uint256[]" }], outputs: [],
  },
  // ── View Functions ──
  {
    type: "function", name: "getCreatorNFTs", stateMutability: "view",
    inputs: [{ name: "creator", type: "address" }], outputs: [{ name: "", type: "uint256[]" }],
  },
  {
    type: "function", name: "getTokenByNFT", stateMutability: "view",
    inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function", name: "getSupportedBaseTokens", stateMutability: "view",
    inputs: [], outputs: [{ name: "", type: "address[]" }],
  },
  {
    type: "function", name: "getTotalTokensDeployed", stateMutability: "view",
    inputs: [], outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function", name: "getCreator", stateMutability: "view",
    inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function", name: "getPoolManager", stateMutability: "view",
    inputs: [{ name: "baseToken", type: "address" }], outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function", name: "treasury", stateMutability: "view",
    inputs: [], outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function", name: "npm", stateMutability: "view",
    inputs: [], outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function", name: "owner", stateMutability: "view",
    inputs: [], outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function", name: "citadel", stateMutability: "view",
    inputs: [], outputs: [{ name: "", type: "address" }],
  },
  // ── Events ──
  {
    type: "event", name: "TokenDeployed", anonymous: false,
    inputs: [
      { name: "token", type: "address", indexed: true },
      { name: "name", type: "string", indexed: false },
      { name: "symbol", type: "string", indexed: false },
      { name: "creator", type: "address", indexed: true },
      { name: "tokenId", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event", name: "FeesCollected", anonymous: false,
    inputs: [
      { name: "tokenId", type: "uint256", indexed: true },
      { name: "amount0", type: "uint256", indexed: false },
      { name: "amount1", type: "uint256", indexed: false },
    ],
  },
] as const;
