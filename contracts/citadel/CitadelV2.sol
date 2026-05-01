// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Citadel (V2)
 * @dev  Standalone LP Locker + optional Tydro position manager for Tsunami V3 on Ink.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CHANGES vs V1
 * ─────────────────────────────────────────────────────────────────────────────
 *  • Fee collection is now 100% to the LP owner. No platform fee split.
 *  • Fees are sent directly to the locker's EOA by the PositionManager
 *    (no Citadel-custody intermediate step).
 *  • Tydro integration is now user-facing:
 *      - supplyToTydro:   user pulls from their own EOA → supplies on their own behalf.
 *      - withdrawFromTydro: user approves aTokens to Citadel → Citadel forwards withdraw to user.
 *      - borrowFromTydro / repayToTydro: user-initiated, user is the debtor.
 *    No more owner-only / auto-supply. Tydro is opt-in per user.
 *  • lockFromFactory is disabled — Citadel is a 100% external locker. New
 *    Sentry launches manage their own fees inside SentryLaunchFactory.
 *  • Storage layout preserved exactly for safe proxy upgrade from V1.
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * Upgradeable via TransparentUpgradeableProxy + ProxyAdmin.
 * ERC-2771 meta-transaction support for Gelato relay retained.
 */

import "../sentry/interfaces/ISentryInterfaces.sol";
import "./interfaces/ICitadelInterfaces.sol";

/* ─────────────────────────── Structs ─────────────────────────── */

struct LockInfo {
    address locker;           // Who locked the LP NFT — receives 100% of collected fees
    address projectTreasury;  // V1 legacy field (Sentry locks). Unused in V2 collection flow.
    uint256 lockTimestamp;    // When the lock was created
    uint256 unlockTime;       // When the NFT becomes unlockable (type(uint256).max = permanent)
    bool isSentryLaunch;      // V1 legacy flag. Kept in storage; doesn't affect V2 behavior.
    bool exists;              // Guard against double-lock
}

/* ─────────────────────────── Citadel ─────────────────────────── */

contract CitadelV2 {
    /* ─────────────────────────── State Variables ─────────────────────────── */
    // Storage layout identical to V1 — do not reorder, rename-in-place only.

    // Initializer guard
    bool private _initialized;

    /// @dev Disables initialize() on the implementation contract itself.
    constructor() {
        _initialized = true;
    }

    // Core addresses
    address public npm;         // Tsunami V3 NonfungiblePositionManager
    address public weth;        // WETH9 (0x4200...0006)
    address public tydroPool;   // Tydro (Aave V3) Pool on Ink
    address public treasury;    // V1 legacy — unused in V2 (no platform fee). Kept for layout.

    // Owner
    address public owner;

    // ERC-2771 trusted forwarder (Gelato relay)
    address private _trustedForwarder;

    // Reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    // V1 legacy — unused in V2 (100% to locker, no platform fee). Kept for layout.
    uint256 public platformFeeBps;
    uint256 public constant MAX_PLATFORM_FEE_BPS = 2500;

    // V1 legacy — unused in V2. Kept for layout.
    address public sentryLaunchFactory;

    // Lock state
    mapping(uint256 => LockInfo) public locks;
    uint256[] public lockedTokenIds;
    mapping(address => uint256[]) public lockerNFTs;

    // V1 legacy per-token counter (was owner-supplied balance). Repurposed in V2 as cumulative
    // per-asset supply counter for analytics across all users. Strictly increments; does not
    // reflect outstanding balance.
    mapping(address => uint256) public tydroSupplied;

    // Analytics
    uint256 public totalLockedCount;
    uint256 public totalSentryLocks;

    /* ──────────────────────────────── Events ──────────────────────────────── */

    event Initialized(address indexed npm, address indexed treasury);
    event LPLocked(
        uint256 indexed tokenId,
        address indexed locker,
        uint256 unlockTime
    );
    event LPUnlocked(uint256 indexed tokenId, address indexed locker);
    event FeesCollected(
        uint256 indexed tokenId,
        address indexed locker,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    );

    // Tydro events — user-scoped
    event SuppliedToTydro(address indexed user, address indexed asset, uint256 amount);
    event WithdrawnFromTydro(address indexed user, address indexed asset, uint256 amount);
    event BorrowedFromTydro(address indexed user, address indexed asset, uint256 amount);
    event RepaidToTydro(address indexed user, address indexed asset, uint256 amount);

    // Admin events
    event NPMUpdated(address oldNPM, address newNPM);
    event TydroPoolUpdated(address oldPool, address newPool);
    event TrustedForwarderUpdated(address oldForwarder, address newForwarder);
    event OwnershipTransferred(address oldOwner, address newOwner);

    /* ─────────────────────────────── Modifiers ─────────────────────────────── */

    modifier onlyOwner() {
        require(_msgSender() == owner, "Only owner");
        _;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    modifier initializer() {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _;
    }

    /* ───────────────── ERC-2771 (inline, no OZ dependency) ─────────────────── */

    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder == _trustedForwarder;
    }

    function _msgSender() internal view returns (address sender) {
        if (msg.data.length >= 24 && isTrustedForwarder(msg.sender)) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }

    /* ──────────────────────────── Initializer ──────────────────────────────── */

    /// @dev Only used on fresh proxy deployments. Not called on upgrades.
    function initialize(
        address _npm,
        address _weth,
        address _tydroPool,
        address _treasury,
        address trustedForwarder_
    ) external initializer {
        require(_npm != address(0), "Invalid NPM");
        require(_weth != address(0), "Invalid WETH");
        require(_tydroPool != address(0), "Invalid Tydro pool");

        npm = _npm;
        weth = _weth;
        tydroPool = _tydroPool;
        treasury = _treasury; // Kept for layout even if unused
        _trustedForwarder = trustedForwarder_;
        owner = _msgSender();
        _status = _NOT_ENTERED;

        emit Initialized(_npm, _treasury);
    }

    /* ──────────────────────── Versioning ───────────────────────── */

    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    /* ──────────────────────── LP Locking ───────────────────────── */

    /**
     * @notice Lock a Tsunami V3 LP NFT in Citadel.
     * @dev Caller must have approved Citadel for the NFT first.
     * @param tokenId    The LP NFT token ID
     * @param unlockTime Unix timestamp after which the NFT is unlockable.
     *                   Pass type(uint256).max for a permanent lock.
     */
    function lockLP(uint256 tokenId, uint256 unlockTime) external nonReentrant {
        require(!locks[tokenId].exists, "Already locked");

        INonfungiblePositionManager(npm).safeTransferFrom(_msgSender(), address(this), tokenId);
        require(
            INonfungiblePositionManager(npm).ownerOf(tokenId) == address(this),
            "Transfer failed"
        );

        locks[tokenId] = LockInfo({
            locker: _msgSender(),
            projectTreasury: address(0),
            lockTimestamp: block.timestamp,
            unlockTime: unlockTime,
            isSentryLaunch: false,
            exists: true
        });

        lockedTokenIds.push(tokenId);
        lockerNFTs[_msgSender()].push(tokenId);
        totalLockedCount++;

        emit LPLocked(tokenId, _msgSender(), unlockTime);
    }

    /**
     * @notice DISABLED in V2.
     * @dev Citadel no longer accepts factory-initiated locks. Sentry launches
     *      now manage their own fee collection inside SentryLaunchFactory.
     *      Retained in the ABI for V1 surface compatibility — always reverts.
     */
    function lockFromFactory(
        uint256 /* tokenId */,
        address /* creator */,
        address /* projectTreasury */
    ) external pure {
        revert("Citadel V2: factory locks disabled");
    }

    /**
     * @notice Unlock and withdraw an LP NFT after the lock period.
     * @dev Legacy V1 Sentry locks (isSentryLaunch=true) cannot be unlocked —
     *      they were designed to be permanent and this behavior is preserved.
     */
    function unlock(uint256 tokenId) external nonReentrant {
        LockInfo storage lock = locks[tokenId];
        require(lock.exists, "Not locked");
        require(_msgSender() == lock.locker, "Not locker");
        require(block.timestamp >= lock.unlockTime, "Still locked");
        require(!lock.isSentryLaunch, "Sentry locks are permanent");

        INonfungiblePositionManager(npm).safeTransferFrom(address(this), lock.locker, tokenId);

        address locker = lock.locker;
        lock.exists = false;
        totalLockedCount--;

        _removeFromArray(lockedTokenIds, tokenId);
        _removeFromArray(lockerNFTs[locker], tokenId);

        emit LPUnlocked(tokenId, locker);
    }

    /* ──────────────────────── Fee Collection ───────────────────── */

    /**
     * @notice Collect LP trading fees from a locked position. 100% of fees
     *         flow directly to the locker's EOA — Citadel is just a trigger.
     *         Works across all Tsunami fee tiers (0.01% → 5%).
     */
    function collectFees(uint256 tokenId) public nonReentrant {
        LockInfo storage lock = locks[tokenId];
        require(lock.exists, "Not locked");
        require(_msgSender() == lock.locker, "Only locker");

        // Collect all accrued fees directly to the locker's EOA (bypasses Citadel custody).
        (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(npm).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: lock.locker,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        if (amount0 == 0 && amount1 == 0) return;

        (, , address token0, address token1, , , , , , , , ) =
            INonfungiblePositionManager(npm).positions(tokenId);

        emit FeesCollected(tokenId, lock.locker, token0, amount0, token1, amount1);
    }

    /**
     * @notice Batch collect fees from multiple locked positions you own.
     */
    function collectBatchFees(uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            collectFees(tokenIds[i]);
        }
    }

    /* ──────────────────── Tydro Position Management (user-facing) ──────────────────── */

    /**
     * @notice Supply an asset into Tydro on your own behalf.
     * @dev    Pulls the asset from the caller's wallet (requires prior ERC-20
     *         approval of Citadel on the underlying asset). The resulting aTokens
     *         are sent directly to the caller — Citadel never custodies them.
     *         The caller can thereafter interact with the position via Tydro's
     *         frontend, tydro-mcp, or Citadel's withdraw wrapper below.
     */
    function supplyToTydro(address asset, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        address user = _msgSender();

        _safeTransferFrom(asset, user, address(this), amount);
        _safeApprove(asset, tydroPool, amount);
        ITydroPool(tydroPool).supply(asset, amount, user, 0);

        tydroSupplied[asset] += amount; // Analytics (cumulative, not outstanding)
        emit SuppliedToTydro(user, asset, amount);
    }

    /**
     * @notice Withdraw an asset from Tydro. The caller's aTokens are pulled into
     *         Citadel and burned by Tydro; the underlying asset is sent to the caller.
     * @dev    Caller must have approved Citadel to transfer the asset's aToken.
     * @param  asset  The underlying asset to withdraw (e.g. WETH, USDT0).
     * @param  amount Amount to withdraw. Pass type(uint256).max for full balance.
     * @return The actual amount of underlying returned to the caller.
     */
    function withdrawFromTydro(address asset, uint256 amount)
        external
        nonReentrant
        returns (uint256)
    {
        address user = _msgSender();
        address aToken = _getATokenAddress(asset);

        // Resolve "max" to the user's current aToken balance (which includes interest).
        uint256 pull = amount == type(uint256).max
            ? IERC20Minimal(aToken).balanceOf(user)
            : amount;
        require(pull > 0, "Nothing to withdraw");

        _safeTransferFrom(aToken, user, address(this), pull);

        // Tydro burns Citadel's aTokens, sends asset to user directly.
        uint256 withdrawn = ITydroPool(tydroPool).withdraw(asset, pull, user);
        emit WithdrawnFromTydro(user, asset, withdrawn);
        return withdrawn;
    }

    /**
     * @notice Borrow against your Tydro collateral, routed through Citadel.
     * @dev    Uses Aave V3 variable-rate (stable rate is deprecated). Requires
     *         the caller to have supplied collateral to Tydro in advance.
     *         The borrowed asset is sent to the caller directly.
     */
    function borrowFromTydro(address asset, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        address user = _msgSender();
        ITydroPool(tydroPool).borrow(asset, amount, 2 /* variable */, 0, user);
        // Tydro sends the borrowed asset to the debtor (user) directly.
        emit BorrowedFromTydro(user, asset, amount);
    }

    /**
     * @notice Repay debt on Tydro on your own behalf.
     * @dev    Pulls `asset` from the caller and calls repay. Requires prior
     *         approval on the underlying asset.
     * @param  amount Pass type(uint256).max to repay the full outstanding debt.
     */
    function repayToTydro(address asset, uint256 amount) external nonReentrant returns (uint256) {
        require(amount > 0, "Amount must be > 0");
        address user = _msgSender();

        // When paying max, pull an explicit amount — max+allowance patterns don't work
        // well across wallets. Users should pass the actual debt amount + a buffer.
        _safeTransferFrom(asset, user, address(this), amount);
        _safeApprove(asset, tydroPool, amount);

        uint256 repaid = ITydroPool(tydroPool).repay(asset, amount, 2 /* variable */, user);

        // Refund any dust that wasn't needed for repayment.
        if (repaid < amount) {
            _safeTransfer(asset, user, amount - repaid);
        }

        emit RepaidToTydro(user, asset, repaid);
        return repaid;
    }

    /* ──────────────────── Tydro Read Helpers ─────────────────────── */

    function getATokenAddress(address asset) external view returns (address) {
        return _getATokenAddress(asset);
    }

    function getUserTydroAccount(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return ITydroPool(tydroPool).getUserAccountData(user);
    }

    function getUserSuppliedBalance(address user, address asset) external view returns (uint256) {
        address aToken = _getATokenAddress(asset);
        return IERC20Minimal(aToken).balanceOf(user);
    }

    function _getATokenAddress(address asset) internal view returns (address) {
        ITydroPool.ReserveData memory r = ITydroPool(tydroPool).getReserveData(asset);
        require(r.aTokenAddress != address(0), "Reserve not listed");
        return r.aTokenAddress;
    }

    /* ───────────────────────── Admin Functions ────────────────────────────── */

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    function updateNPM(address newNPM) external onlyOwner {
        require(newNPM != address(0), "Invalid NPM");
        address old = npm;
        npm = newNPM;
        emit NPMUpdated(old, newNPM);
    }

    function updateTydroPool(address newPool) external onlyOwner {
        require(newPool != address(0), "Invalid pool");
        address old = tydroPool;
        tydroPool = newPool;
        emit TydroPoolUpdated(old, newPool);
    }

    function setTrustedForwarder(address forwarder) external onlyOwner {
        address old = _trustedForwarder;
        _trustedForwarder = forwarder;
        emit TrustedForwarderUpdated(old, forwarder);
    }

    /// @notice Rescue any ERC-20 stuck in Citadel (shouldn't happen — supplied tokens
    ///         go onBehalfOf the user, fees bypass Citadel entirely. Kept as a safety valve.)
    function rescueToken(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        _safeTransfer(token, to, amount);
    }

    /* ──────────────────────────── View Functions ───────────────────────────── */

    function getLockInfo(uint256 tokenId) external view returns (LockInfo memory) {
        return locks[tokenId];
    }

    function isLocked(uint256 tokenId) external view returns (bool) {
        return locks[tokenId].exists;
    }

    function isUnlockable(uint256 tokenId) external view returns (bool) {
        LockInfo storage lock = locks[tokenId];
        return lock.exists && !lock.isSentryLaunch && block.timestamp >= lock.unlockTime;
    }

    function getLockedTokenIds() external view returns (uint256[] memory) {
        return lockedTokenIds;
    }

    function getLockerNFTs(address locker) external view returns (uint256[] memory) {
        return lockerNFTs[locker];
    }

    function getTotalLockedCount() external view returns (uint256) {
        return totalLockedCount;
    }

    function getTotalSentryLocks() external view returns (uint256) {
        return totalSentryLocks;
    }

    function getTydroSupplied(address asset) external view returns (uint256) {
        return tydroSupplied[asset];
    }

    function getTrustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }

    /* ──────────── Safe ERC-20 Helpers ─────────── */

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Approve failed");
    }

    /* ──────────── Array Cleanup ─────────── */

    function _removeFromArray(uint256[] storage arr, uint256 tokenId) internal {
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; i++) {
            if (arr[i] == tokenId) {
                arr[i] = arr[len - 1];
                arr.pop();
                return;
            }
        }
    }

    /* ──────────────── ERC-721 Receiver ──────────────────────── */

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /* ─────────────────── Upgrade Storage Gap ─────────────────────────────── */

    uint256[40] private __gap;
}
