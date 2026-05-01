// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './pool/ITsunamiV3PoolImmutables.sol';
import './pool/ITsunamiV3PoolState.sol';
import './pool/ITsunamiV3PoolDerivedState.sol';
import './pool/ITsunamiV3PoolActions.sol';
import './pool/ITsunamiV3PoolOwnerActions.sol';
import './pool/ITsunamiV3PoolEvents.sol';

/// @title The interface for a Tsunami V3 Pool
/// @notice A Tsunami pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface ITsunamiV3Pool is
    ITsunamiV3PoolImmutables,
    ITsunamiV3PoolState,
    ITsunamiV3PoolDerivedState,
    ITsunamiV3PoolActions,
    ITsunamiV3PoolOwnerActions,
    ITsunamiV3PoolEvents
{

}
