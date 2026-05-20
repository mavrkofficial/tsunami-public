// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {ProtocolFeeController} from "contracts/governance/ProtocolFeeController.sol";

contract SetExistingPoolFees is Script {
    using stdJson for string;

    struct PoolConfig {
        address address_;
        uint24 fee;
        int24 tickSpacing;
    }

    uint256 private constant CHUNK_SIZE = 50;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address controllerAddress = vm.envAddress("PROTOCOL_FEE_CONTROLLER_ADDRESS");
        string memory path = vm.envOr("POOLS_JSON_PATH", string("script/governance/pools.json"));

        string memory json = vm.readFile(path);
        bytes memory rawPools = json.parseRaw("");
        PoolConfig[] memory pools = abi.decode(rawPools, (PoolConfig[]));

        ProtocolFeeController controller = ProtocolFeeController(controllerAddress);
        uint256 totalGasStart = gasleft();

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < pools.length; i += CHUNK_SIZE) {
            uint256 end = i + CHUNK_SIZE;
            if (end > pools.length) end = pools.length;

            address[] memory chunk = new address[](end - i);
            for (uint256 j = i; j < end; j++) {
                chunk[j - i] = pools[j].address_;
                console2.log("pool", pools[j].address_);
                console2.log("tier", pools[j].fee);
                console2.log("N", controller.feeProtocolForTier(pools[j].fee));
            }
            controller.batchSetProtocolFee(chunk);
        }

        vm.stopBroadcast();

        uint256 totalGasUsed = totalGasStart - gasleft();
        console2.log("=== Set Existing Pool Fees ===");
        console2.log("total pools", pools.length);
        console2.log("gas used estimate", totalGasUsed);
        console2.log("estimated cost wei", totalGasUsed * tx.gasprice);
    }
}
