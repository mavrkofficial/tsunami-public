// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CitadelV2} from "../../contracts/citadel/CitadelV2.sol";

/// @notice Deploys the CitadelV2 implementation contract on Ink.
///         This does NOT upgrade the proxy — see UpgradeCitadelProxy.s.sol for that.
///
/// Env vars:
///   PRIVATE_KEY         deployer key (no leading 0x required by forge)
///   INK_RPC_URL         RPC endpoint
///
/// Usage:
///   forge script script/deploy/DeployCitadelV2.s.sol:DeployCitadelV2 \
///     --rpc-url ink --broadcast --verify
contract DeployCitadelV2 is Script {
    function run() external returns (address implementation) {
        vm.startBroadcast();

        CitadelV2 impl = new CitadelV2();
        implementation = address(impl);

        vm.stopBroadcast();

        console.log("CitadelV2 implementation deployed at:", implementation);
        console.log("Version:", impl.version());
        console.log("");
        console.log("Next step: run UpgradeCitadelProxy.s.sol with:");
        console.log("  CITADEL_V2_IMPL=", implementation);
    }
}
