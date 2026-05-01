// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

struct TsunamiParameters {
    address v2Factory;
    address v3Factory;
    bytes32 pairInitCodeHash;
    bytes32 poolInitCodeHash;
}

contract TsunamiImmutables {
    /// @dev The address of TsunamiV2Factory
    address internal immutable TSUNAMI_V2_FACTORY;

    /// @dev The TsunamiV2Pair initcodehash
    bytes32 internal immutable TSUNAMI_V2_PAIR_INIT_CODE_HASH;

    /// @dev The address of TsunamiV3Factory
    address internal immutable TSUNAMI_V3_FACTORY;

    /// @dev The TsunamiV3Pool initcodehash
    bytes32 internal immutable TSUNAMI_V3_POOL_INIT_CODE_HASH;

    constructor(TsunamiParameters memory params) {
        TSUNAMI_V2_FACTORY = params.v2Factory;
        TSUNAMI_V2_PAIR_INIT_CODE_HASH = params.pairInitCodeHash;
        TSUNAMI_V3_FACTORY = params.v3Factory;
        TSUNAMI_V3_POOL_INIT_CODE_HASH = params.poolInitCodeHash;
    }
}
