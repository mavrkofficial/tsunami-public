// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {SentryLaunchFactory} from "contracts/sentry/SentryLaunchFactory.sol";

/// @notice Deploys a fresh SentryLaunchFactory implementation contract for proxy upgrade.
///
/// This script ONLY deploys a new implementation. It does NOT touch the existing
/// proxy or ProxyAdmin. After this runs, the proxy admin owner calls
/// ProxyAdmin.upgrade(proxy, newImpl) to point the live proxy at this new logic.
///
/// Constructor sets `_initialized = true` on the implementation contract itself,
/// so `initialize()` cannot be called directly on the impl — only via the proxy
/// (which already initialized once and won't re-init).
///
/// Usage:
///   forge script script/deploy/DeploySentryLaunchpadImpl.s.sol \
///     --rpc-url $RPC_URL \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast \
///     --chain ink \
///     --verify
contract DeploySentryLaunchpadImpl is Script {
    address constant SENTRY_LAUNCH_FACTORY_PROXY = 0xDc37e11B68052d1539fa23386eE58Ac444bf5BE1;

    function run() external {
        vm.startBroadcast();

        SentryLaunchFactory impl = new SentryLaunchFactory();

        vm.stopBroadcast();

        console2.log("=== SentryLaunchFactory Implementation Deployed ===");
        console2.log("Implementation address:", address(impl));
        console2.log("");
        console2.log("Next step (manual, from ProxyAdmin owner):");
        console2.log("  ProxyAdmin.upgrade(proxy, newImpl)");
        console2.log("Proxy:", SENTRY_LAUNCH_FACTORY_PROXY);
        console2.log("New Impl:", address(impl));
    }
}
