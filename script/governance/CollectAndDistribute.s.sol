// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {ProtocolFeeController} from "contracts/governance/ProtocolFeeController.sol";
import {ProtocolFeeReceiver} from "contracts/governance/ProtocolFeeReceiver.sol";

interface ITsunamiPoolFees {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function protocolFees() external view returns (uint128 token0, uint128 token1);
}

contract CollectAndDistribute is Script {
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
        address receiverAddress = vm.envAddress("PROTOCOL_FEE_RECEIVER_ADDRESS");
        string memory path = vm.envOr("POOLS_JSON_PATH", string("script/governance/pools.json"));

        PoolConfig[] memory configs = abi.decode(vm.readFile(path).parseRaw(""), (PoolConfig[]));

        address[] memory poolsTmp = new address[](configs.length);
        uint128[] memory amount0Tmp = new uint128[](configs.length);
        uint128[] memory amount1Tmp = new uint128[](configs.length);
        address[] memory tokensTmp = new address[](configs.length * 2);
        uint256 count = 0;
        uint256 tokenCount = 0;

        for (uint256 i = 0; i < configs.length; i++) {
            ITsunamiPoolFees pool = ITsunamiPoolFees(configs[i].address_);
            (uint128 fee0, uint128 fee1) = pool.protocolFees();
            if (fee0 == 0 && fee1 == 0) continue;

            poolsTmp[count] = configs[i].address_;
            amount0Tmp[count] = fee0;
            amount1Tmp[count] = fee1;
            count++;

            if (fee0 > 0) tokenCount = _pushUnique(tokensTmp, tokenCount, pool.token0());
            if (fee1 > 0) tokenCount = _pushUnique(tokensTmp, tokenCount, pool.token1());
        }

        ProtocolFeeController controller = ProtocolFeeController(controllerAddress);
        ProtocolFeeReceiver receiver = ProtocolFeeReceiver(payable(receiverAddress));

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < count; i += CHUNK_SIZE) {
            uint256 end = i + CHUNK_SIZE;
            if (end > count) end = count;

            address[] memory pools = new address[](end - i);
            uint128[] memory amount0s = new uint128[](end - i);
            uint128[] memory amount1s = new uint128[](end - i);
            for (uint256 j = i; j < end; j++) {
                pools[j - i] = poolsTmp[j];
                amount0s[j - i] = amount0Tmp[j];
                amount1s[j - i] = amount1Tmp[j];
            }
            controller.collectAndDistribute(pools, amount0s, amount1s);
        }

        address[] memory tokens = new address[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) tokens[i] = tokensTmp[i];
        receiver.distributeMany(tokens);
        if (receiverAddress.balance > 0) receiver.distributeETH();

        vm.stopBroadcast();

        console2.log("=== Collect And Distribute ===");
        console2.log("pools with fees", count);
        console2.log("tokens distributed", tokenCount);
    }

    function _pushUnique(address[] memory tokens, uint256 count, address token) internal pure returns (uint256) {
        for (uint256 i = 0; i < count; i++) {
            if (tokens[i] == token) return count;
        }
        tokens[count] = token;
        return count + 1;
    }
}
