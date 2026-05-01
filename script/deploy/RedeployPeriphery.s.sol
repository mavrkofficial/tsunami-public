// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Script.sol";

import {TsunamiV3PositionManager} from "contracts/NonfungiblePositionManager.sol";
import {TsunamiV3TokenPositionDescriptor} from "contracts/NonfungibleTokenPositionDescriptor.sol";
import {TsunamiQuoterV2} from "contracts/lens/QuoterV2.sol";
import {TsunamiSwapRouter02} from "src/pkgs/swap-router-contracts/contracts/SwapRouter02.sol";

contract RedeployPeriphery is Script {

    address constant DEFAULT_FORWARDER = 0x61F2976610970AFeDc1d83229e1E21bdc3D5cbE4;

    function run() external {
        // ── Reuse existing factory ──────────────────────────────────
        address factory = vm.envAddress("V3_FACTORY");
        address weth9 = vm.envAddress("WETH9");
        address v2Factory = vm.envOr("V2_FACTORY", address(0));
        address forwarder = vm.envOr("GELATO_TRUSTED_FORWARDER", DEFAULT_FORWARDER);
        string memory nativeLabel = vm.envOr("NATIVE_LABEL", string("INK"));
        bytes32 nativeLabelBytes = toBytes32(nativeLabel);

        console2.log("Reusing V3Factory:", factory);
        console2.log("WETH9:", weth9);
        console2.log("Trusted Forwarder:", forwarder);

        vm.startBroadcast();

        // 1. NFT Position Descriptor (provides token URIs)
        TsunamiV3TokenPositionDescriptor descriptor =
            new TsunamiV3TokenPositionDescriptor(weth9, nativeLabelBytes);

        // 2. Position Manager (NPM) — now with corrected POOL_INIT_CODE_HASH
        TsunamiV3PositionManager positionManager =
            new TsunamiV3PositionManager(factory, weth9, address(descriptor), forwarder);

        // 3. QuoterV2 — now with corrected POOL_INIT_CODE_HASH
        TsunamiQuoterV2 quoter = new TsunamiQuoterV2(factory, weth9);

        // 4. SwapRouter02 — now with corrected POOL_INIT_CODE_HASH
        TsunamiSwapRouter02 swapRouter =
            new TsunamiSwapRouter02(v2Factory, factory, address(positionManager), weth9);

        vm.stopBroadcast();

        console2.log("---");
        console2.log("TsunamiV3TokenPositionDescriptor", address(descriptor));
        console2.log("TsunamiV3PositionManager (NPM)", address(positionManager));
        console2.log("TsunamiQuoterV2", address(quoter));
        console2.log("TsunamiSwapRouter02", address(swapRouter));
        console2.log("---");
        console2.log("V3Factory (unchanged)", factory);
    }

    function toBytes32(string memory value) private pure returns (bytes32 result) {
        bytes memory temp = bytes(value);
        require(temp.length <= 32, "label too long");
        assembly {
            result := mload(add(temp, 32))
        }
    }
}
