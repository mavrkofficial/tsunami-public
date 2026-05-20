// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {ProtocolFeeReceiver} from "contracts/governance/ProtocolFeeReceiver.sol";

contract MiniTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "assertEq(uint256) failed");
    }

    function assertEq(address a, address b) internal pure {
        require(a == b, "assertEq(address) failed");
    }
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract ProtocolFeeReceiverTest is MiniTest {
    address ink = address(0x1111);
    address sentry = address(0x2222);
    address treasury = address(0x3333);

    ProtocolFeeReceiver receiver;
    MockERC20 token;

    function setUp() public {
        receiver = new ProtocolFeeReceiver(ink, sentry, treasury);
        token = new MockERC20();
    }

    function testConstructorSetsImmutables() public {
        assertEq(receiver.inkFoundation(), ink);
        assertEq(receiver.sentryRevenueDistributor(), sentry);
        assertEq(receiver.tsunamiTreasury(), treasury);
        assertEq(receiver.INK_FOUNDATION_BPS() + receiver.SENTRY_DISTRIBUTOR_BPS() + receiver.TSUNAMI_TREASURY_BPS(), 10_000);
    }

    function testConstructorRevertsOnZeroAddress() public {
        vm.expectRevert(bytes("Receiver: ink foundation zero"));
        new ProtocolFeeReceiver(address(0), sentry, treasury);

        vm.expectRevert(bytes("Receiver: sentry distributor zero"));
        new ProtocolFeeReceiver(ink, address(0), treasury);

        vm.expectRevert(bytes("Receiver: treasury zero"));
        new ProtocolFeeReceiver(ink, sentry, address(0));
    }

    function testDistributeSplitsTokenBalance() public {
        token.mint(address(receiver), 10_000);

        receiver.distribute(address(token));

        assertEq(token.balanceOf(ink), 8_000);
        assertEq(token.balanceOf(sentry), 1_500);
        assertEq(token.balanceOf(treasury), 500);
        assertEq(token.balanceOf(address(receiver)), 0);
    }

    function testDustRoundingRoutesToInkFoundation() public {
        token.mint(address(receiver), 101);

        receiver.distribute(address(token));

        assertEq(token.balanceOf(sentry), 15);
        assertEq(token.balanceOf(treasury), 5);
        assertEq(token.balanceOf(ink), 81);
    }

    function testDistributeMany() public {
        MockERC20 token2 = new MockERC20();
        token.mint(address(receiver), 1_000);
        token2.mint(address(receiver), 2_000);

        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token2);

        receiver.distributeMany(tokens);

        assertEq(token.balanceOf(ink), 800);
        assertEq(token2.balanceOf(ink), 1_600);
    }

    function testDistributeEth() public {
        vm.deal(address(receiver), 101);

        receiver.distributeETH();

        assertEq(ink.balance, 81);
        assertEq(sentry.balance, 15);
        assertEq(treasury.balance, 5);
    }

    function testDistributeEthZeroBalanceGraceful() public {
        receiver.distributeETH();
        assertEq(ink.balance, 0);
    }
}
