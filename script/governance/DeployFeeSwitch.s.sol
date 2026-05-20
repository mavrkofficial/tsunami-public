// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {ProtocolFeeReceiver} from "contracts/governance/ProtocolFeeReceiver.sol";
import {ProtocolFeeController} from "contracts/governance/ProtocolFeeController.sol";

interface ITsunamiFactoryOwner {
    function owner() external view returns (address);
    function setOwner(address owner) external;
}

contract DeployFeeSwitch is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address inkFoundation = vm.envAddress("INK_FOUNDATION_ADDRESS");
        address sentryDistributor = vm.envAddress("SENTRY_REVENUE_DISTRIBUTOR_ADDRESS");
        address tsunamiTreasury = vm.envAddress("TSUNAMI_TREASURY_ADDRESS");
        address factoryAddress = vm.envAddress("TSUNAMI_FACTORY_ADDRESS");
        bool transferFactoryOwnership = vm.envOr("TRANSFER_FACTORY_OWNERSHIP", false);
        bool allowEoaRecipients = vm.envOr("ALLOW_EOA_RECIPIENTS", false);

        require(inkFoundation != address(0), "INK_FOUNDATION_ADDRESS is zero");
        require(sentryDistributor != address(0), "SENTRY_REVENUE_DISTRIBUTOR_ADDRESS is zero");
        require(tsunamiTreasury != address(0), "TSUNAMI_TREASURY_ADDRESS is zero");
        require(factoryAddress != address(0), "TSUNAMI_FACTORY_ADDRESS is zero");

        _warnIfEoa("INK_FOUNDATION_ADDRESS", inkFoundation, allowEoaRecipients);
        _warnIfEoa("SENTRY_REVENUE_DISTRIBUTOR_ADDRESS", sentryDistributor, allowEoaRecipients);
        _warnIfEoa("TSUNAMI_TREASURY_ADDRESS", tsunamiTreasury, allowEoaRecipients);

        vm.startBroadcast(deployerKey);

        ProtocolFeeReceiver receiver = new ProtocolFeeReceiver(
            inkFoundation,
            sentryDistributor,
            tsunamiTreasury
        );
        ProtocolFeeController controller = new ProtocolFeeController(
            factoryAddress,
            address(receiver)
        );

        if (transferFactoryOwnership) {
            ITsunamiFactoryOwner(factoryAddress).setOwner(address(controller));
        }

        vm.stopBroadcast();

        console2.log("=== Tsunami Fee Switch Deployment ===");
        console2.log("ProtocolFeeReceiver   ", address(receiver));
        console2.log("ProtocolFeeController ", address(controller));
        console2.log("Ink Foundation        ", inkFoundation);
        console2.log("SENTRY Distributor    ", sentryDistributor);
        console2.log("Tsunami Treasury      ", tsunamiTreasury);
        console2.log("Factory               ", factoryAddress);
        console2.log("Factory owner         ", ITsunamiFactoryOwner(factoryAddress).owner());
        console2.log("Transfer ownership    ", transferFactoryOwnership);
    }

    function _warnIfEoa(string memory label, address account, bool allowEoaRecipients) internal view {
        if (account.code.length == 0) {
            console2.log(string.concat("WARNING: ", label, " is an EOA, expected a multisig or contract."));
            require(allowEoaRecipients, "EOA recipient blocked; set ALLOW_EOA_RECIPIENTS=true");
        }
    }
}
