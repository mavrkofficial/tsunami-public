// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title ProtocolFeeReceiver
/// @notice Immutable 80/15/5 fee splitter for Tsunami protocol fees.
contract ProtocolFeeReceiver {
    using Address for address payable;

    uint256 public constant INK_FOUNDATION_BPS = 8000;
    uint256 public constant SENTRY_DISTRIBUTOR_BPS = 1500;
    uint256 public constant TSUNAMI_TREASURY_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public immutable inkFoundation;
    address public immutable sentryRevenueDistributor;
    address public immutable tsunamiTreasury;

    event Distributed(
        address indexed token,
        uint256 inkFoundationAmount,
        uint256 sentryAmount,
        uint256 tsunamiAmount
    );

    constructor(
        address inkFoundation_,
        address sentryRevenueDistributor_,
        address tsunamiTreasury_
    ) {
        require(inkFoundation_ != address(0), "Receiver: ink foundation zero");
        require(sentryRevenueDistributor_ != address(0), "Receiver: sentry distributor zero");
        require(tsunamiTreasury_ != address(0), "Receiver: treasury zero");
        require(
            INK_FOUNDATION_BPS + SENTRY_DISTRIBUTOR_BPS + TSUNAMI_TREASURY_BPS == BPS_DENOMINATOR,
            "Receiver: invalid bps"
        );

        inkFoundation = inkFoundation_;
        sentryRevenueDistributor = sentryRevenueDistributor_;
        tsunamiTreasury = tsunamiTreasury_;
    }

    receive() external payable {}

    function distribute(address token) public {
        require(token != address(0), "Receiver: token zero");
        uint256 balance = IERC20Minimal(token).balanceOf(address(this));
        if (balance == 0) {
            emit Distributed(token, 0, 0, 0);
            return;
        }

        (uint256 inkAmount, uint256 sentryAmount, uint256 treasuryAmount) = _split(balance);

        _safeTransfer(token, inkFoundation, inkAmount);
        _safeTransfer(token, sentryRevenueDistributor, sentryAmount);
        _safeTransfer(token, tsunamiTreasury, treasuryAmount);

        emit Distributed(token, inkAmount, sentryAmount, treasuryAmount);
    }

    function distributeMany(address[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            distribute(tokens[i]);
        }
    }

    function distributeETH() public {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            emit Distributed(address(0), 0, 0, 0);
            return;
        }

        (uint256 inkAmount, uint256 sentryAmount, uint256 treasuryAmount) = _split(balance);

        payable(inkFoundation).sendValue(inkAmount);
        payable(sentryRevenueDistributor).sendValue(sentryAmount);
        payable(tsunamiTreasury).sendValue(treasuryAmount);

        emit Distributed(address(0), inkAmount, sentryAmount, treasuryAmount);
    }

    function _split(uint256 amount) internal pure returns (
        uint256 inkAmount,
        uint256 sentryAmount,
        uint256 treasuryAmount
    ) {
        sentryAmount = (amount * SENTRY_DISTRIBUTOR_BPS) / BPS_DENOMINATOR;
        treasuryAmount = (amount * TSUNAMI_TREASURY_BPS) / BPS_DENOMINATOR;
        inkAmount = amount - sentryAmount - treasuryAmount;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Receiver: transfer failed");
    }
}
