// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SentryLaunchFactory
 * @dev Unified token launch factory for the Sentry launchpad on Tsunami DEX.
 * Deploys tokens, creates Tsunami V3 pools, mints LP positions, self-custodies
 * LP NFTs, and routes collected trading fees to creators + treasury.
 *
 * Key features:
 * - Multi-base token support (WETH, etc.) each with its own pool manager
 * - WETH-side LP fees split: 25% to creator (nftCreators[tokenId]), 75% to treasury
 * - Token-side LP fees: 100% to treasury
 * - Non-WETH paired pools: both sides 100% to treasury (legacy fallback)
 * - LP NFTs permanently held in factory (LPLocked event for indexers)
 * - ERC-2771 meta-transaction support via Gelato 1Balance relay (inline)
 * - Upgradeable via TransparentUpgradeableProxy + ProxyAdmin (already in repo)
 *   initialize() replaces the constructor; a simple _initialized guard prevents
 *   double-initialization on the implementation contract.
 *
 * Note on storage layout: this contract retains __deprecated_* slots for
 * citadel / feesWalletRegular / feesWalletAgent from prior versions to
 * preserve proxy storage compatibility. They are unused in this version.
 */

import "./interfaces/ISentryInterfaces.sol";
import "./SentryTokenStandard.sol";

interface IIdentityRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/* ─────────────────────────── Structs ─────────────────────────── */

struct MintingDetails {
    uint160 sqrtPriceX96;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
}

/* ─────────────────────────── SentryLaunchFactory ─────────────────────────── */

contract SentryLaunchFactory {
    address public constant WETH9 = 0x4200000000000000000000000000000000000006;

    /* ─────────────────────────── State Variables ─────────────────────────── */

    // Initializer guard (proxy pattern — prevents double-initialization)
    bool private _initialized;

    /// @dev Disables initialize() on the implementation contract itself.
    ///      Only the proxy (via delegatecall) can be initialized.
    constructor() {
        _initialized = true;
    }

    // Core DEX addresses
    address public npm;         // Tsunami V3 NonfungiblePositionManager

    // Multi-Base Token Support
    mapping(address => address) public baseTokenToPoolManager;
    address[] public baseTokens;

    // Constants
    uint24 public constant FEE_TIER = 10000; // 1% fee tier for launches
    uint256 public constant CREATOR_FEE_BPS = 2500; // 25% of WETH-side LP fees → creator
    uint256 private constant BPS_DENOMINATOR = 10_000;

    // ERC-2771 trusted forwarder (Gelato relay) — stored in regular storage
    // so it can be updated via setTrustedForwarder after upgrades
    address private _trustedForwarder;

    // Treasury — receives ALL collected fees
    address public treasury;

    // Creator tracking
    mapping(uint256 => address) public nftCreators;
    mapping(address => uint256[]) public creatorNFTs;
    mapping(uint256 => address) public tokenIdToToken;

    // Token deployment counter
    uint256 public totalTokensDeployed;

    // Temporary storage for stack optimization
    address private _tempCreator;
    address private _tempToken0;
    address private _tempToken1;
    address private _tempPool;

    // Owner
    address public owner;

    // Reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    // ─── Deprecated slots (kept for proxy storage compat — DO NOT REMOVE) ───
    // Was: Citadel LP locker (V2). Removed in V4: factory self-custodies all LPs.
    address private __deprecated_citadel;

    // V3 additions: launch typing + fee routing + agent identity gate.
    // isAgentPosition is still populated for indexer/historical use, but no
    // longer drives fee routing.
    mapping(uint256 => bool) public isAgentPosition;
    // Was: separate WETH-fee recipients for regular vs agent launches (V3).
    // Removed in V4: all WETH fees split 25/75 between creator/treasury.
    address private __deprecated_feesWalletRegular;
    address private __deprecated_feesWalletAgent;
    address public identityRegistry;

    /* ──────────────────────────────── Events ──────────────────────────────── */

    event Initialized(address indexed npm, address indexed treasury);
    event TokenDeployed(
        address indexed token,
        string name,
        string symbol,
        address indexed creator,
        uint256 tokenId
    );
    event PoolInitialized(address indexed pool, address indexed token);
    event LiquidityMinted(uint256 indexed tokenId, address indexed pool, address indexed token);
    event LPLocked(uint256 indexed tokenId, address indexed pool, address indexed token);
    event FeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event CreatorFeePaid(uint256 indexed tokenId, address indexed creator, uint256 wethAmount);
    event BaseTokenAdded(address indexed baseToken, address indexed manager);
    event BaseTokenRemoved(address indexed baseToken);
    event PoolManagerUpdated(address indexed baseToken, address oldManager, address newManager);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event NPMUpdated(address oldNPM, address newNPM);
    event TrustedForwarderUpdated(address oldForwarder, address newForwarder);
    event IdentityRegistryUpdated(address oldRegistry, address newRegistry);

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

    /// @notice Returns true if `forwarder` is the Gelato trusted forwarder.
    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder == _trustedForwarder;
    }

    /// @dev Recovers the original sender from ERC-2771 calldata when relayed.
    function _msgSender() internal view returns (address sender) {
        if (msg.data.length >= 24 && isTrustedForwarder(msg.sender)) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }

    function _msgData() internal view returns (bytes calldata) {
        if (msg.data.length >= 24 && isTrustedForwarder(msg.sender)) {
            return msg.data[:msg.data.length - 20];
        } else {
            return msg.data;
        }
    }

    /* ──────────────────────────── Initializer ──────────────────────────────── */

    /**
     * @notice Replaces the constructor for proxy compatibility.
     *         Called once by the TransparentUpgradeableProxy on deployment.
     * @param _npm                Tsunami V3 NonfungiblePositionManager address
     * @param _initialBaseToken   First supported base token (e.g. WETH on Ink)
     * @param _initialPoolManager Pool manager contract for the initial base token
     * @param _treasury           Address that receives all collected LP fees
     * @param trustedForwarder_   Gelato ERC-2771 trusted forwarder address
     */
    function initialize(
        address _npm,
        address _initialBaseToken,
        address _initialPoolManager,
        address _treasury,
        address trustedForwarder_
    ) external initializer {
        require(_npm != address(0), "Invalid NPM");
        require(_initialBaseToken != address(0), "Invalid base token");
        require(_initialPoolManager != address(0), "Invalid pool manager");
        require(_treasury != address(0), "Invalid treasury");

        npm = _npm;
        treasury = _treasury;
        _trustedForwarder = trustedForwarder_;
        owner = _msgSender();       // proxy deployer becomes owner
        _status = _NOT_ENTERED;

        baseTokenToPoolManager[_initialBaseToken] = _initialPoolManager;
        baseTokens.push(_initialBaseToken);

        emit BaseTokenAdded(_initialBaseToken, _initialPoolManager);
        emit Initialized(_npm, _treasury);
    }

    /* ────────────────────── Base Token Management ───────────────────────── */

    function addBaseToken(address baseToken, address manager) external onlyOwner {
        require(baseToken != address(0) && manager != address(0), "Invalid addresses");
        require(baseTokenToPoolManager[baseToken] == address(0), "Base token already exists");
        baseTokenToPoolManager[baseToken] = manager;
        baseTokens.push(baseToken);
        emit BaseTokenAdded(baseToken, manager);
    }

    function updatePoolManager(address baseToken, address newManager) external onlyOwner {
        require(baseTokenToPoolManager[baseToken] != address(0), "Base token does not exist");
        require(newManager != address(0), "Invalid manager");
        address oldManager = baseTokenToPoolManager[baseToken];
        baseTokenToPoolManager[baseToken] = newManager;
        emit PoolManagerUpdated(baseToken, oldManager, newManager);
    }

    function removeBaseToken(address baseToken) external onlyOwner {
        require(baseTokenToPoolManager[baseToken] != address(0), "Base token does not exist");
        delete baseTokenToPoolManager[baseToken];
        for (uint256 i = 0; i < baseTokens.length; i++) {
            if (baseTokens[i] == baseToken) {
                baseTokens[i] = baseTokens[baseTokens.length - 1];
                baseTokens.pop();
                break;
            }
        }
        emit BaseTokenRemoved(baseToken);
    }

    /* ────────────────────── Token Launch ───────────────────── */

    /**
     * @notice Launch a new token, create a Tsunami V3 pool, and lock single-sided LP.
     * @param _name     Token name
     * @param _symbol   Token symbol
     * @param baseToken The base pair token (e.g. WETH)
     * @return tokenAddress The deployed token contract address
     * @return tokenId      LP NFT token ID (held permanently by this factory)
     */
    function launch(
        string memory _name,
        string memory _symbol,
        address baseToken
    ) external nonReentrant returns (address tokenAddress, uint256 tokenId) {
        return _launchInternal(_name, _symbol, baseToken, false);
    }

    /**
     * @notice Launch path for agents only (requires identity registry membership).
     */
    function launchAgent(
        string memory _name,
        string memory _symbol,
        address baseToken
    ) external nonReentrant returns (address tokenAddress, uint256 tokenId) {
        require(
            identityRegistry != address(0) &&
            IIdentityRegistry(identityRegistry).balanceOf(_msgSender()) > 0,
            "MoltiverseAgentRegistry: caller not a registered agent"
        );
        return _launchInternal(_name, _symbol, baseToken, true);
    }

    function _launchInternal(
        string memory _name,
        string memory _symbol,
        address baseToken,
        bool isAgent
    ) internal returns (address tokenAddress, uint256 tokenId) {
        require(baseTokenToPoolManager[baseToken] != address(0), "Base token not supported");

        SentryTokenStandard token = new SentryTokenStandard(_name, _symbol, address(this), _trustedForwarder);
        tokenAddress = address(token);
        totalTokensDeployed++;

        require(token.approve(npm, type(uint256).max), "Approval failed");

        // V3 requires token0 < token1 (sorted by address)
        address token0 = tokenAddress < baseToken ? tokenAddress : baseToken;
        address token1 = tokenAddress < baseToken ? baseToken : tokenAddress;

        require(
            _tryPoolAndMint(tokenAddress, token0, token1, baseToken, _msgSender(), isAgent),
            "Pool creation and mint failed"
        );

        uint256[] storage creatorNFTList = creatorNFTs[_msgSender()];
        tokenId = creatorNFTList[creatorNFTList.length - 1];

        emit TokenDeployed(tokenAddress, _name, _symbol, _msgSender(), tokenId);
    }

    /* ──────────────────────── Internal Pool & Mint Logic ───────────────────── */

    function _tryPoolAndMint(
        address tokenAddress,
        address token0,
        address token1,
        address baseToken,
        address creator,
        bool isAgent
    ) internal returns (bool) {
        _tempCreator = creator;
        _tempToken0 = token0;
        _tempToken1 = token1;

        MintingDetails memory details;
        (
            details.sqrtPriceX96,
            details.tickLower,
            details.tickUpper,
            details.amount0Desired,
            details.amount1Desired,
            details.amount0Min,
            details.amount1Min
        ) = ITsunamiPoolManager(baseTokenToPoolManager[baseToken]).getMintingParameters(tokenAddress, token0, token1);

        if (!_createAndInitializePool(details.sqrtPriceX96)) return false;
        return _mintPosition(details, tokenAddress, isAgent);
    }

    function _createAndInitializePool(uint160 sqrtPriceX96) internal returns (bool) {
        try INonfungiblePositionManager(npm).createAndInitializePoolIfNecessary(
            _tempToken0, _tempToken1, FEE_TIER, sqrtPriceX96
        ) returns (address pool) {
            _tempPool = pool;
            return true;
        } catch {
            return false;
        }
    }

    function _mintPosition(MintingDetails memory details, address tokenAddress, bool isAgent) internal returns (bool) {
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: _tempToken0,
            token1: _tempToken1,
            fee: FEE_TIER,
            tickLower: details.tickLower,
            tickUpper: details.tickUpper,
            amount0Desired: details.amount0Desired,
            amount1Desired: details.amount1Desired,
            amount0Min: details.amount0Min,
            amount1Min: details.amount1Min,
            recipient: address(this),
            deadline: block.timestamp + 600
        });

        try INonfungiblePositionManager(npm).mint(params) returns (uint256 tokenId, uint128, uint256, uint256) {
            return _handleSuccessfulMint(tokenId, INonfungiblePositionManager(npm), tokenAddress, isAgent);
        } catch {
            return false;
        }
    }

    function _handleSuccessfulMint(
        uint256 tokenId,
        INonfungiblePositionManager npmContract,
        address tokenAddress,
        bool isAgent
    ) internal returns (bool) {
        nftCreators[tokenId] = _tempCreator;
        creatorNFTs[_tempCreator].push(tokenId);
        tokenIdToToken[tokenId] = tokenAddress;
        isAgentPosition[tokenId] = isAgent;

        require(npmContract.ownerOf(tokenId) == address(this), "Factory does not own LP NFT");

        emit PoolInitialized(_tempPool, tokenAddress);
        emit LiquidityMinted(tokenId, _tempPool, tokenAddress);
        // Factory permanently self-custodies the LP NFT.
        emit LPLocked(tokenId, _tempPool, tokenAddress);

        return true;
    }

    /* ──────────────────────────── Fee Collection ───────────────────────────── */

    /// @notice Collect accrued trading fees from one LP position and route by launch type.
    function collectFees(uint256 tokenId) external onlyOwner nonReentrant {
        (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(npm).positions(tokenId);
        (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(npm).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        emit FeesCollected(tokenId, amount0, amount1);
        _routeFees(token0, token1, amount0, amount1, tokenId);
    }

    /// @notice Batch collect fees from multiple LP positions and route by launch type.
    function collectMultipleFees(uint256[] calldata tokenIds) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(npm).positions(tokenIds[i]);
            (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(npm).collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenIds[i],
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
            emit FeesCollected(tokenIds[i], amount0, amount1);
            _routeFees(token0, token1, amount0, amount1, tokenIds[i]);
        }
    }

    /// @dev Routes accrued fees:
    ///        - WETH side  → 25% creator (CREATOR_FEE_BPS), 75% treasury
    ///        - Token side → 100% treasury
    ///        - Non-WETH paired pools (legacy fallback) → both sides to treasury
    ///      If nftCreators[tokenId] is unset (shouldn't happen), the full
    ///      WETH side falls through to treasury — defensive, never reverts.
    function _routeFees(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 tokenId
    ) internal {
        // Non-WETH paired pools (rare/legacy): both sides go to treasury.
        if (token0 != WETH9 && token1 != WETH9) {
            if (amount0 > 0) require(IERC20(token0).transfer(treasury, amount0), "token0 transfer failed");
            if (amount1 > 0) require(IERC20(token1).transfer(treasury, amount1), "token1 transfer failed");
            return;
        }

        // Identify WETH side vs meme side for the WETH-paired pool.
        (uint256 wethAmount, address memeToken, uint256 memeAmount) = token0 == WETH9
            ? (amount0, token1, amount1)
            : (amount1, token0, amount0);

        // ─── WETH side: 25% creator, 75% treasury ────────────────────────────
        if (wethAmount > 0) {
            address creator = nftCreators[tokenId];
            uint256 creatorCut = (wethAmount * CREATOR_FEE_BPS) / BPS_DENOMINATOR;
            uint256 treasuryCut = wethAmount - creatorCut;

            // Defensive: if the creator slot is somehow unset, redirect the
            // creator cut to treasury rather than burning it or reverting.
            if (creator == address(0)) {
                treasuryCut = wethAmount;
                creatorCut = 0;
            }

            if (creatorCut > 0) {
                require(IERC20(WETH9).transfer(creator, creatorCut), "creator weth transfer failed");
                emit CreatorFeePaid(tokenId, creator, creatorCut);
            }
            if (treasuryCut > 0) {
                require(IERC20(WETH9).transfer(treasury, treasuryCut), "treasury weth transfer failed");
            }
        }

        // ─── Token side: 100% treasury ───────────────────────────────────────
        if (memeAmount > 0) {
            require(IERC20(memeToken).transfer(treasury, memeAmount), "token transfer failed");
        }
    }

    /* ───────────────────────── Admin Functions ────────────────────────────── */

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        owner = newOwner;
    }

    function updateTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury");
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    function updateNPM(address newNPM) external onlyOwner {
        require(newNPM != address(0), "Invalid NPM");
        address oldNPM = npm;
        npm = newNPM;
        emit NPMUpdated(oldNPM, newNPM);
    }

    function setTrustedForwarder(address forwarder) external onlyOwner {
        address old = _trustedForwarder;
        _trustedForwarder = forwarder;
        emit TrustedForwarderUpdated(old, forwarder);
    }

    function setIdentityRegistry(address _registry) external onlyOwner {
        require(_registry != address(0), "Invalid registry");
        address old = identityRegistry;
        identityRegistry = _registry;
        emit IdentityRegistryUpdated(old, _registry);
    }

    /* ──────────────────────────── View Functions ───────────────────────────── */

    function getPoolManager(address baseToken) external view returns (address) {
        return baseTokenToPoolManager[baseToken];
    }

    function getSupportedBaseTokens() external view returns (address[] memory) {
        return baseTokens;
    }

    function getCreator(uint256 tokenId) external view returns (address) {
        return nftCreators[tokenId];
    }

    function getCreatorNFTs(address creator) external view returns (uint256[] memory) {
        return creatorNFTs[creator];
    }

    function getCreatorNFTCount(address creator) external view returns (uint256) {
        return creatorNFTs[creator].length;
    }

    function getTokenByNFT(uint256 tokenId) external view returns (address) {
        return tokenIdToToken[tokenId];
    }

    function getTotalTokensDeployed() external view returns (uint256) {
        return totalTokensDeployed;
    }

    function getTrustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }

    /* ──────────────── ERC-721 Receiver (defensive) ──────────────────────── */

    /// @dev Accept LP NFTs via safeTransferFrom (defensive — NPM uses _mint, but future-proofs).
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /* ─────────────────── Upgrade Storage Gap ─────────────────────────────── */

    /// @dev Slot history (do not reorder):
    ///      V2 consumed 1 slot: __deprecated_citadel.
    ///      V3 consumed 4 slots: isAgentPosition, __deprecated_feesWalletRegular,
    ///                           __deprecated_feesWalletAgent, identityRegistry.
    ///      V4 consumed 0 slots (CREATOR_FEE_BPS / BPS_DENOMINATOR are constants).
    uint256[45] private __gap;
}
