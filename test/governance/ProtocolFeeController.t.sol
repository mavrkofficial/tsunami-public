// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {ProtocolFeeController} from "contracts/governance/ProtocolFeeController.sol";

contract MiniTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "assertEq(uint256) failed");
    }

    function assertEq(address a, address b) internal pure {
        require(a == b, "assertEq(address) failed");
    }

    function assertLt(uint256 a, uint256 b) internal pure {
        require(a < b, "assertLt(uint256) failed");
    }
}

contract MockPool {
    uint24 public immutable fee;
    uint8 public feeProtocol0;
    uint8 public feeProtocol1;
    bool public shouldRevertCollect;
    uint128 public nextAmount0 = 1;
    uint128 public nextAmount1 = 2;

    constructor(uint24 fee_) {
        fee = fee_;
    }

    function setFeeProtocol(uint8 feeProtocol0_, uint8 feeProtocol1_) external {
        feeProtocol0 = feeProtocol0_;
        feeProtocol1 = feeProtocol1_;
    }

    function collectProtocol(address, uint128 amount0Requested, uint128 amount1Requested)
        external
        returns (uint128 amount0, uint128 amount1)
    {
        if (shouldRevertCollect) revert("collect fail");
        amount0 = nextAmount0 < amount0Requested ? nextAmount0 : amount0Requested;
        amount1 = nextAmount1 < amount1Requested ? nextAmount1 : amount1Requested;
    }

    function setRevertCollect(bool value) external {
        shouldRevertCollect = value;
    }
}

contract ProtocolFeeControllerTest is MiniTest {
    address factory = address(0xFACADE);
    address receiver = address(0xBEEF);
    address sentryFactory = address(0x5157);
    address alice = address(0xA11CE);

    ProtocolFeeController controller;

    function setUp() public {
        controller = new ProtocolFeeController(factory, receiver);
        controller.setSentryFactory(sentryFactory);
    }

    function testTierMapping() public {
        assertEq(controller.feeProtocolForTier(100), 10);
        assertEq(controller.feeProtocolForTier(500), 10);
        assertEq(controller.feeProtocolForTier(2500), 10);
        assertEq(controller.feeProtocolForTier(3000), 10);
        assertEq(controller.feeProtocolForTier(5000), 10);
        assertEq(controller.feeProtocolForTier(10000), 4);
        assertEq(controller.feeProtocolForTier(20000), 4);
        assertEq(controller.feeProtocolForTier(50000), 4);
    }

    function testOwnerCanSetProtocolFeeForPool() public {
        MockPool lowTier = new MockPool(500);
        MockPool highTier = new MockPool(10000);

        controller.setProtocolFeeForPool(address(lowTier));
        controller.setProtocolFeeForPool(address(highTier));

        assertEq(lowTier.feeProtocol0(), 10);
        assertEq(lowTier.feeProtocol1(), 10);
        assertEq(highTier.feeProtocol0(), 4);
        assertEq(highTier.feeProtocol1(), 4);
    }

    function testSentryFactoryCanSetProtocolFeeForPool() public {
        MockPool pool = new MockPool(20000);

        vm.prank(sentryFactory);
        controller.setProtocolFeeForPool(address(pool));

        assertEq(pool.feeProtocol0(), 4);
        assertEq(pool.feeProtocol1(), 4);
    }

    function testUnauthorizedCannotSetProtocolFee() public {
        MockPool pool = new MockPool(500);

        vm.prank(alice);
        vm.expectRevert(bytes("Controller: unauthorized"));
        controller.setProtocolFeeForPool(address(pool));
    }

    function testBatchSetProtocolFeeFiftyPoolsUnderFiveMillionGas() public {
        address[] memory pools = new address[](50);
        for (uint256 i = 0; i < pools.length; i++) {
            pools[i] = address(new MockPool(i % 2 == 0 ? 500 : 10000));
        }

        uint256 gasBefore = gasleft();
        controller.batchSetProtocolFee(pools);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 5_000_000);
    }

    function testCollectAndDistributePermissionlessAndSkipsFailures() public {
        MockPool ok = new MockPool(500);
        MockPool bad = new MockPool(500);
        bad.setRevertCollect(true);

        address[] memory pools = new address[](2);
        pools[0] = address(ok);
        pools[1] = address(bad);
        uint128[] memory amount0s = new uint128[](2);
        uint128[] memory amount1s = new uint128[](2);
        amount0s[0] = type(uint128).max;
        amount1s[0] = type(uint128).max;
        amount0s[1] = type(uint128).max;
        amount1s[1] = type(uint128).max;

        vm.prank(alice);
        controller.collectAndDistribute(pools, amount0s, amount1s);
    }

    function testTransferOwnership() public {
        controller.transferOwnership(alice);
        assertEq(controller.owner(), alice);

        vm.prank(alice);
        controller.setSentryFactory(address(0x1234));
        assertEq(controller.sentryFactory(), address(0x1234));
    }
}
