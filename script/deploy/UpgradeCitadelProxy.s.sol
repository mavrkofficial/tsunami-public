// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

/// @dev OpenZeppelin TransparentUpgradeableProxy / ProxyAdmin interface (minimal).
interface IProxyAdmin {
    function upgrade(address proxy, address implementation) external;
    function upgradeAndCall(address proxy, address implementation, bytes memory data) external payable;
    function owner() external view returns (address);
}

interface ICitadelV2 {
    function version() external view returns (string memory);
    function owner() external view returns (address);
}

/// @notice Upgrades the Citadel proxy to point at a freshly-deployed CitadelV2
///         implementation. Must be run by the ProxyAdmin owner.
///
/// Env vars:
///   PRIVATE_KEY         signer key — MUST be the ProxyAdmin owner
///   CITADEL_PROXY       proxy address   (default: 0x111474f3062E9B8B7B9d568675c5bb1262d6F862)
///   PROXY_ADMIN         admin address   (default: 0x915c2e6b8ece2a5a144bd1636c3a630c273b6f63)
///   CITADEL_V2_IMPL     new implementation address (required — output of DeployCitadelV2)
///
/// Usage:
///   CITADEL_V2_IMPL=0xNEW... forge script \
///     script/deploy/UpgradeCitadelProxy.s.sol:UpgradeCitadelProxy \
///     --rpc-url ink --broadcast
contract UpgradeCitadelProxy is Script {
    address constant DEFAULT_PROXY = 0x111474f3062E9B8B7B9d568675c5bb1262d6F862;
    address constant DEFAULT_PROXY_ADMIN = 0x915c2E6b8Ece2A5A144Bd1636c3a630c273b6F63;

    function run() external {
        address proxy = vm.envOr("CITADEL_PROXY", DEFAULT_PROXY);
        address admin = vm.envOr("PROXY_ADMIN", DEFAULT_PROXY_ADMIN);
        address newImpl = vm.envAddress("CITADEL_V2_IMPL");

        require(newImpl != address(0), "CITADEL_V2_IMPL not set");

        IProxyAdmin proxyAdmin = IProxyAdmin(admin);
        address adminOwner = proxyAdmin.owner();
        console.log("ProxyAdmin owner:", adminOwner);
        console.log("Signing with broadcaster - must match owner.");
        console.log("Proxy:", proxy);
        console.log("New implementation:", newImpl);

        vm.startBroadcast();
        proxyAdmin.upgrade(proxy, newImpl);
        vm.stopBroadcast();

        // Post-upgrade verification — should echo "2.0.0"
        string memory v = ICitadelV2(proxy).version();
        console.log("Upgrade complete. Proxy.version():", v);
    }
}
