// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '../interfaces/IMulticall.sol';

/// @title Multicall
/// @notice Enables calling multiple methods in a single call to the contract
/// @dev Reentrancy guard applied inline to prevent re-entrant multicall attacks.
///      Uses a storage mutex rather than inheritance to stay compatible with
///      Solidity 0.7.6 and avoid storage-layout conflicts with sibling base contracts.
abstract contract Multicall is IMulticall {

    // ── Reentrancy guard ───────────────────────────────────────────────────
    uint256 private constant _MULTICALL_NOT_ENTERED = 1;
    uint256 private constant _MULTICALL_ENTERED     = 2;
    uint256 private _multicallStatus = _MULTICALL_NOT_ENTERED;

    modifier multicallNonReentrant() {
        require(_multicallStatus != _MULTICALL_ENTERED, 'Multicall: reentrant call');
        _multicallStatus = _MULTICALL_ENTERED;
        _;
        _multicallStatus = _MULTICALL_NOT_ENTERED;
    }

    // ── Core ───────────────────────────────────────────────────────────────

    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data)
        public
        payable
        override
        multicallNonReentrant
        returns (bytes[] memory results)
    {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}
