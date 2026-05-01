export const CitadelABI = [
  // ── Write Functions ──
  { type: "function", name: "lockLP", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }, { name: "unlockTime", type: "uint256" }], outputs: [] },
  { type: "function", name: "unlock", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [] },
  { type: "function", name: "collectFees", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [] },
  { type: "function", name: "collectBatchFees", stateMutability: "nonpayable", inputs: [{ name: "tokenIds", type: "uint256[]" }], outputs: [] },
  { type: "function", name: "lockFromFactory", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }, { name: "creator", type: "address" }, { name: "projectTreasury", type: "address" }], outputs: [] },
  { type: "function", name: "supplyToTydro", stateMutability: "nonpayable", inputs: [{ name: "token", type: "address" }, { name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "withdrawFromTydro", stateMutability: "nonpayable", inputs: [{ name: "token", type: "address" }, { name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "updateProjectTreasury", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }, { name: "newTreasury", type: "address" }], outputs: [] },
  // ── View Functions ──
  {
    type: "function", name: "getLockInfo", stateMutability: "view",
    inputs: [{ name: "tokenId", type: "uint256" }],
    outputs: [{ name: "", type: "tuple", components: [
      { name: "locker", type: "address" }, { name: "projectTreasury", type: "address" },
      { name: "lockTimestamp", type: "uint256" }, { name: "unlockTime", type: "uint256" },
      { name: "isSentryLaunch", type: "bool" }, { name: "exists", type: "bool" },
    ]}],
  },
  { type: "function", name: "getLockerNFTs", stateMutability: "view", inputs: [{ name: "locker", type: "address" }], outputs: [{ name: "", type: "uint256[]" }] },
  { type: "function", name: "isLocked", stateMutability: "view", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ name: "", type: "bool" }] },
  { type: "function", name: "isUnlockable", stateMutability: "view", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ name: "", type: "bool" }] },
  { type: "function", name: "getLockedTokenIds", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256[]" }] },
  { type: "function", name: "getTotalLockedCount", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "getTotalSentryLocks", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "getTydroSupplied", stateMutability: "view", inputs: [{ name: "token", type: "address" }], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "platformFeeBps", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "treasury", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "address" }] },
  { type: "function", name: "npm", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "address" }] },
  { type: "function", name: "owner", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "address" }] },
] as const;
