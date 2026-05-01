// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {SentryLaunchFactory} from "contracts/sentry/SentryLaunchFactory.sol";
import {SentryLowCapPoolManagerETH} from "contracts/sentry/SentryPoolManagerETH.sol";

/// @notice Deploys SentryLaunchFactory behind a TransparentUpgradeableProxy.
///
/// Deployment order:
///   1. SentryPoolManagerETH    — pool parameter calculator for WETH pairs
///   2. SentryLaunchFactory     — implementation contract (logic only)
///   3. ProxyAdmin              — admin that controls proxy upgrades
///   4. TransparentUpgradeableProxy — proxy pointing at implementation
///      └─ calls initialize(...) during construction
///
/// To upgrade later (via ProxyAdmin):
///   forge script script/deploy/UpgradeSentryLaunchpad.s.sol --broadcast
///
/// Required env vars:
///   NPM_ADDRESS, WETH9, TREASURY, PRIVATE_KEY
/// Optional:
///   POOL_MANAGER (default: deploys fresh SentryLowCapPoolManagerETH)
///   GELATO_TRUSTED_FORWARDER (default: Gelato's Ink forwarder)
contract DeploySentryLaunchpad is Script {

    address constant DEFAULT_FORWARDER = 0x61F2976610970AFeDc1d83229e1E21bdc3D5cbE4;

    function run() external {
        // ── Required env vars ─────────────────────────────────────────────────
        address npmAddress       = vm.envAddress("NPM_ADDRESS");
        address weth9            = vm.envAddress("WETH9");
        address treasury         = vm.envAddress("TREASURY");
        address trustedForwarder = vm.envOr("GELATO_TRUSTED_FORWARDER", DEFAULT_FORWARDER);
        address poolManager      = vm.envOr("POOL_MANAGER", address(0));

        vm.startBroadcast();

        // ── 1. Pool manager ───────────────────────────────────────────────────
        if (poolManager == address(0)) {
            SentryLowCapPoolManagerETH pm = new SentryLowCapPoolManagerETH();
            poolManager = address(pm);
            console2.log("SentryPoolManagerETH (new)", poolManager);
        } else {
            console2.log("SentryPoolManagerETH (reused)", poolManager);
        }

        // ── 2. Implementation (no constructor args — logic only) ──────────────
        SentryLaunchFactory impl = new SentryLaunchFactory();
        console2.log("SentryLaunchFactory (impl)", address(impl));

        // ── 3. ProxyAdmin ─────────────────────────────────────────────────────
        // Deployed via deployCode so Foundry handles the 0.7.x / 0.8.x version gap.
        address proxyAdmin = deployCode("ProxyAdmin.sol:ProxyAdmin");
        console2.log("ProxyAdmin", proxyAdmin);

        // ── 4. Transparent proxy — calls initialize() during construction ─────
        bytes memory initData = abi.encodeCall(
            SentryLaunchFactory.initialize,
            (
                npmAddress,      // Tsunami V3 NonfungiblePositionManager
                weth9,           // Initial base token (WETH on Ink)
                poolManager,     // Pool manager for WETH pairs
                treasury,        // All LP fees routed here
                trustedForwarder // Gelato ERC-2771 forwarder
            )
        );

        address proxy = deployCode(
            "TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
            abi.encode(address(impl), proxyAdmin, initData)
        );

        vm.stopBroadcast();

        // ── Output ────────────────────────────────────────────────────────────
        console2.log("=== Sentry Launchpad Deployment ===");
        console2.log("SentryLaunchFactory (proxy)  ", proxy);
        console2.log("SentryLaunchFactory (impl)   ", address(impl));
        console2.log("ProxyAdmin                   ", proxyAdmin);
        console2.log("SentryPoolManagerETH         ", poolManager);
        console2.log("---");
        console2.log("NPM                          ", npmAddress);
        console2.log("Base Token (WETH)            ", weth9);
        console2.log("Treasury                     ", treasury);
        console2.log("Trusted Forwarder            ", trustedForwarder);
        console2.log("---");
        console2.log(">> Add to .env:");
        console2.log("SENTRY_LAUNCH_FACTORY=", proxy);
        console2.log("SENTRY_PROXY_ADMIN=", proxyAdmin);
        console2.log("POOL_MANAGER=", poolManager);
    }
}
