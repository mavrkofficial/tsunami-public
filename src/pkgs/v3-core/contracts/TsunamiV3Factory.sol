// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/ITsunamiV3Factory.sol';

import './TsunamiV3PoolDeployer.sol';
import './NoDelegateCall.sol';

import './TsunamiV3Pool.sol';

/// @title Canonical Tsunami V3 factory
/// @notice Deploys Tsunami V3 pools and manages ownership and control over pool protocol fees
contract TsunamiV3Factory is ITsunamiV3Factory, TsunamiV3PoolDeployer, NoDelegateCall {
    /// @inheritdoc ITsunamiV3Factory
    address public override owner;

    /// @inheritdoc ITsunamiV3Factory
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    /// @inheritdoc ITsunamiV3Factory
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        // ── Standard fee tiers (inherited from Uniswap V3) ─────────────────
        feeAmountTickSpacing[500] = 10;       // 0.05% — stable / correlated pairs
        emit FeeAmountEnabled(500, 10);
        feeAmountTickSpacing[3000] = 60;      // 0.30% — standard pairs
        emit FeeAmountEnabled(3000, 60);
        feeAmountTickSpacing[10000] = 200;    // 1.00% — exotic / high-vol pairs
        emit FeeAmountEnabled(10000, 200);

        // ── Tsunami extended fee tiers ──────────────────────────────────────
        feeAmountTickSpacing[100] = 1;        // 0.01% — pegged stablecoins (USDC/USDT)
        emit FeeAmountEnabled(100, 1);
        feeAmountTickSpacing[2500] = 50;      // 0.25% — liquid mid-vol altcoins
        emit FeeAmountEnabled(2500, 50);
        feeAmountTickSpacing[5000] = 100;     // 0.50% — higher-volatility assets
        emit FeeAmountEnabled(5000, 100);
        feeAmountTickSpacing[20000] = 400;    // 2.00% — meme coins / new launches
        emit FeeAmountEnabled(20000, 400);
        feeAmountTickSpacing[50000] = 1000;   // 5.00% — extreme volatility / launchpad tokens
        emit FeeAmountEnabled(50000, 1000);
    }

    /// @inheritdoc ITsunamiV3Factory
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0);
        require(getPool[token0][token1][fee] == address(0));
        pool = deploy(address(this), token0, token1, fee, tickSpacing);
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc ITsunamiV3Factory
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc ITsunamiV3Factory
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        require(msg.sender == owner);
        require(fee < 1000000);
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
