// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IUniswapV2Pair} from '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import {UniswapV2Library} from './UniswapV2Library.sol';
import {TsunamiImmutables} from '../TsunamiImmutables.sol';
import {Payments} from '../../Payments.sol';
import {Permit2Payments} from '../../Permit2Payments.sol';
import {Constants} from '../../../libraries/Constants.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';

/// @title Router for Tsunami V2 Trades
abstract contract V2SwapRouter is TsunamiImmutables, Permit2Payments {
    error V2TooLittleReceived();
    error V2TooMuchRequested();
    error V2InvalidPath();

    function _v2Swap(address[] calldata path, address recipient, address pair) private {
        unchecked {
            if (path.length < 2) revert V2InvalidPath();

            // cached to save on duplicate operations
            (address token0,) = UniswapV2Library.sortTokens(path[0], path[1]);
            uint256 finalPairIndex = path.length - 1;
            for (uint256 i; i < finalPairIndex; i++) {
                address input = path[i];
                (uint256 amount0Out, uint256 amount1Out) = _getSwapAmounts(pair, input, token0);
                address nextPair;
                (nextPair, token0) = _getNextPair(path, i, finalPairIndex, recipient);
                IUniswapV2Pair(pair).swap(amount0Out, amount1Out, nextPair, new bytes(0));
                pair = nextPair;
            }
        }
    }

    function _getNextPair(address[] calldata path, uint256 i, uint256 finalPairIndex, address recipient)
        private
        view
        returns (address nextPair, address token0)
    {
        uint256 penultimatePairIndex = finalPairIndex - 1;
        if (i < penultimatePairIndex) {
            (nextPair, token0) = UniswapV2Library.pairAndToken0For(
                TSUNAMI_V2_FACTORY, TSUNAMI_V2_PAIR_INIT_CODE_HASH, path[i + 1], path[i + 2]
            );
        } else {
            nextPair = recipient;
            token0 = address(0);
        }
    }

    function _getSwapAmounts(address pair, address input, address token0)
        private
        view
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (uint256 reserveInput, uint256 reserveOutput) =
            input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 amountInput = ERC20(input).balanceOf(pair) - reserveInput;
        uint256 amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
        (amount0Out, amount1Out) =
            input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
    }

    /// @notice Performs a Tsunami V2 exact input swap
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The amount of input tokens for the trade
    /// @param amountOutMinimum The minimum desired amount of output tokens
    /// @param path The path of the trade as an array of token addresses
    /// @param payer The address that will be paying the input
    function v2SwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address[] calldata path,
        address payer
    ) internal {
        address firstPair =
            UniswapV2Library.pairFor(TSUNAMI_V2_FACTORY, TSUNAMI_V2_PAIR_INIT_CODE_HASH, path[0], path[1]);
        if (
            amountIn != Constants.ALREADY_PAID // amountIn of 0 to signal that the pair already has the tokens
        ) {
            payOrPermit2Transfer(path[0], payer, firstPair, amountIn);
        }

        ERC20 tokenOut = ERC20(path[path.length - 1]);
        uint256 balanceBefore = tokenOut.balanceOf(recipient);

        _v2Swap(path, recipient, firstPair);

        uint256 amountOut = tokenOut.balanceOf(recipient) - balanceBefore;
        if (amountOut < amountOutMinimum) revert V2TooLittleReceived();
    }

    /// @notice Performs a Tsunami V2 exact output swap
    /// @param recipient The recipient of the output tokens
    /// @param amountOut The amount of output tokens to receive for the trade
    /// @param amountInMaximum The maximum desired amount of input tokens
    /// @param path The path of the trade as an array of token addresses
    /// @param payer The address that will be paying the input
    function v2SwapExactOutput(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        address[] calldata path,
        address payer
    ) internal {
        (uint256 amountIn, address firstPair) =
            UniswapV2Library.getAmountInMultihop(TSUNAMI_V2_FACTORY, TSUNAMI_V2_PAIR_INIT_CODE_HASH, amountOut, path);
        if (amountIn > amountInMaximum) revert V2TooMuchRequested();

        payOrPermit2Transfer(path[0], payer, firstPair, amountIn);
        _v2Swap(path, recipient, firstPair);
    }
}
