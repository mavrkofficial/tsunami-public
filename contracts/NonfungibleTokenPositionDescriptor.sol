// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/ITsunamiV3Pool.sol';
import '@uniswap/lib/contracts/libraries/SafeERC20Namer.sol';

import './libraries/ChainId.sol';
import './interfaces/ITsunamiV3PositionManager.sol';
import './interfaces/ITsunamiV3TokenPositionDescriptor.sol';
import './interfaces/IERC20Metadata.sol';
import './libraries/PoolAddress.sol';
import './libraries/TsunamiV3NFTDescriptor.sol';
import './libraries/TokenRatioSortOrder.sol';

/// @title Describes NFT token positions
/// @notice Produces a string containing the data URI for a JSON metadata string
contract TsunamiV3TokenPositionDescriptor is ITsunamiV3TokenPositionDescriptor {
    // --- Ethereum Mainnet (chainId 1) stablecoin / BTC addresses ---
    address private constant ETH_DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant ETH_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant ETH_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant ETH_TBTC = 0x8dAEBADE922dF735c38C80C7eBD708Af50815fAa;
    address private constant ETH_WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // --- Ink Mainnet (chainId 57073) token addresses ---
    address private constant INK_USDC = 0x2D270e6886d130D724215A266106e6832161EAEd;

    address public immutable WETH9;
    /// @dev A null-terminated string
    bytes32 public immutable nativeCurrencyLabelBytes;

    constructor(address _WETH9, bytes32 _nativeCurrencyLabelBytes) {
        WETH9 = _WETH9;
        nativeCurrencyLabelBytes = _nativeCurrencyLabelBytes;
    }

    /// @notice Returns the native currency label as a string
    function nativeCurrencyLabel() public view returns (string memory) {
        uint256 len = 0;
        while (len < 32 && nativeCurrencyLabelBytes[len] != 0) {
            len++;
        }
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            b[i] = nativeCurrencyLabelBytes[i];
        }
        return string(b);
    }

    /// @inheritdoc ITsunamiV3TokenPositionDescriptor
    function tokenURI(ITsunamiV3PositionManager positionManager, uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        (, , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, , , , , ) =
            positionManager.positions(tokenId);

        ITsunamiV3Pool pool =
            ITsunamiV3Pool(
                PoolAddress.computeAddress(
                    positionManager.factory(),
                    PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})
                )
            );

        bool _flipRatio = flipRatio(token0, token1, ChainId.get());
        address quoteTokenAddress = !_flipRatio ? token1 : token0;
        address baseTokenAddress = !_flipRatio ? token0 : token1;
        (, int24 tick, , , , , ) = pool.slot0();

        return
            TsunamiV3NFTDescriptor.constructTokenURI(
                TsunamiV3NFTDescriptor.ConstructTokenURIParams({
                    tokenId: tokenId,
                    quoteTokenAddress: quoteTokenAddress,
                    baseTokenAddress: baseTokenAddress,
                    quoteTokenSymbol: quoteTokenAddress == WETH9
                        ? nativeCurrencyLabel()
                        : SafeERC20Namer.tokenSymbol(quoteTokenAddress),
                    baseTokenSymbol: baseTokenAddress == WETH9
                        ? nativeCurrencyLabel()
                        : SafeERC20Namer.tokenSymbol(baseTokenAddress),
                    quoteTokenDecimals: IERC20Metadata(quoteTokenAddress).decimals(),
                    baseTokenDecimals: IERC20Metadata(baseTokenAddress).decimals(),
                    flipRatio: _flipRatio,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    tickCurrent: tick,
                    tickSpacing: pool.tickSpacing(),
                    fee: fee,
                    poolAddress: address(pool)
                })
            );
    }

    function flipRatio(
        address token0,
        address token1,
        uint256 chainId
    ) public view returns (bool) {
        return tokenRatioPriority(token0, chainId) > tokenRatioPriority(token1, chainId);
    }

    function tokenRatioPriority(address token, uint256 chainId) public view returns (int256) {
        if (token == WETH9) {
            return TokenRatioSortOrder.DENOMINATOR;
        }
        if (chainId == 57073) {
            // Ink Mainnet
            if (token == INK_USDC) {
                return TokenRatioSortOrder.NUMERATOR_MOST;
            } else {
                return 0;
            }
        }
        if (chainId == 1) {
            // Ethereum Mainnet (kept for reference / multi-chain support)
            if (token == ETH_USDC) {
                return TokenRatioSortOrder.NUMERATOR_MOST;
            } else if (token == ETH_USDT) {
                return TokenRatioSortOrder.NUMERATOR_MORE;
            } else if (token == ETH_DAI) {
                return TokenRatioSortOrder.NUMERATOR;
            } else if (token == ETH_TBTC) {
                return TokenRatioSortOrder.DENOMINATOR_MORE;
            } else if (token == ETH_WBTC) {
                return TokenRatioSortOrder.DENOMINATOR_MOST;
            } else {
                return 0;
            }
        }
        return 0;
    }
}
