// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITsunamiV3FactoryOwner {
    function owner() external view returns (address);
}

interface ITsunamiV3PoolProtocolFee {
    function fee() external view returns (uint24);
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external;
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}

/// @title ProtocolFeeController
/// @notice Owns the Tsunami V3 factory and controls pool protocol-fee activation.
contract ProtocolFeeController {
    ITsunamiV3FactoryOwner public immutable factory;
    address public immutable feeReceiver;

    address public owner;
    address public sentryFactory;

    event ProtocolFeeSet(address indexed pool, uint24 tier, uint8 N);
    event SentryFactorySet(address indexed sentryFactory);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ProtocolFeesCollected(address indexed pool, uint128 amount0, uint128 amount1);
    event ProtocolFeeCollectFailed(address indexed pool, bytes reason);

    modifier onlyOwner() {
        require(msg.sender == owner, "Controller: only owner");
        _;
    }

    modifier onlyOwnerOrSentryFactory() {
        require(msg.sender == owner || msg.sender == sentryFactory, "Controller: unauthorized");
        _;
    }

    constructor(address factory_, address feeReceiver_) {
        require(factory_ != address(0), "Controller: factory zero");
        require(feeReceiver_ != address(0), "Controller: receiver zero");
        factory = ITsunamiV3FactoryOwner(factory_);
        feeReceiver = feeReceiver_;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function setSentryFactory(address sentryFactory_) external onlyOwner {
        require(sentryFactory_ != address(0), "Controller: sentry factory zero");
        sentryFactory = sentryFactory_;
        emit SentryFactorySet(sentryFactory_);
    }

    function feeProtocolForTier(uint24 tier) public pure returns (uint8) {
        return tier <= 5000 ? 10 : 4;
    }

    function setProtocolFeeForPool(address pool) public onlyOwnerOrSentryFactory {
        require(pool != address(0), "Controller: pool zero");
        uint24 tier = ITsunamiV3PoolProtocolFee(pool).fee();
        uint8 denominator = feeProtocolForTier(tier);
        ITsunamiV3PoolProtocolFee(pool).setFeeProtocol(denominator, denominator);
        emit ProtocolFeeSet(pool, tier, denominator);
    }

    function batchSetProtocolFee(address[] calldata pools) external onlyOwner {
        for (uint256 i = 0; i < pools.length; i++) {
            setProtocolFeeForPool(pools[i]);
        }
    }

    function collectAndDistribute(
        address[] calldata pools,
        uint128[] calldata amount0s,
        uint128[] calldata amount1s
    ) external {
        require(
            pools.length == amount0s.length && pools.length == amount1s.length,
            "Controller: length mismatch"
        );

        for (uint256 i = 0; i < pools.length; i++) {
            try ITsunamiV3PoolProtocolFee(pools[i]).collectProtocol(
                feeReceiver,
                amount0s[i],
                amount1s[i]
            ) returns (uint128 amount0, uint128 amount1) {
                emit ProtocolFeesCollected(pools[i], amount0, amount1);
            } catch (bytes memory reason) {
                emit ProtocolFeeCollectFailed(pools[i], reason);
            }
        }
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Controller: owner zero");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
}
