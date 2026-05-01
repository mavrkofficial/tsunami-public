// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Script.sol";

import {TsunamiSwapRouter02} from "src/pkgs/swap-router-contracts/contracts/SwapRouter02.sol";

contract RedeploySwapRouter is Script {
    function run() external {
        address factory = vm.envAddress("V3_FACTORY");
        address weth9 = vm.envAddress("WETH9");
        address v2Factory = vm.envOr("V2_FACTORY", address(0));
        address positionManager = vm.envAddress("V3_POSITION_MANAGER");

        vm.startBroadcast();

        TsunamiSwapRouter02 swapRouter =
            new TsunamiSwapRouter02(v2Factory, factory, positionManager, weth9);

        vm.stopBroadcast();

        console2.log("TsunamiSwapRouter02 (NEW)", address(swapRouter));
    }
}
