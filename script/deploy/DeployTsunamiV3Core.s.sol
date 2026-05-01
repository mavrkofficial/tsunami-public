// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Script.sol";

import {TsunamiV3Factory} from "src/pkgs/v3-core/contracts/TsunamiV3Factory.sol";
import {TsunamiV3PositionManager} from "contracts/NonfungiblePositionManager.sol";
import {TsunamiV3TokenPositionDescriptor} from "contracts/NonfungibleTokenPositionDescriptor.sol";
import {TsunamiQuoterV2} from "contracts/lens/QuoterV2.sol";
import {TsunamiTickLens} from "contracts/lens/TickLens.sol";
import {TsunamiSwapRouter02} from "src/pkgs/swap-router-contracts/contracts/SwapRouter02.sol";

/// @notice Deploys the full Tsunami V3 core + periphery stack on Ink.
///
/// Contracts deployed (in order):
///   1. TsunamiV3Factory          — core pool factory (8 fee tiers baked in)
///   2. TsunamiV3TokenPositionDescriptor — on-chain LP NFT metadata + Tsunami SVG art
///   3. TsunamiV3PositionManager  — LP NFT manager with inline ERC-2771 support
///   4. TsunamiQuoterV2           — price quoter (off-chain simulation)
///   5. TsunamiTickLens           — tick bitmap reader
///   6. TsunamiSwapRouter02       — main swap router
///
/// Required env vars:
///   WETH9, PRIVATE_KEY, INK_RPC_URL
/// Optional:
///   V2_FACTORY (default: zero — no V2 routing)
///   NATIVE_LABEL (default: "INK")
///   GELATO_TRUSTED_FORWARDER (default: Gelato's Ink forwarder)
contract DeployTsunamiV3Core is Script {
    // Gelato trusted forwarder on Ink — used by NPM for gasless LP operations
    address constant DEFAULT_FORWARDER = 0x61F2976610970AFeDc1d83229e1E21bdc3D5cbE4;

    function run() external {
        address weth9        = vm.envAddress("WETH9");
        address v2Factory    = vm.envOr("V2_FACTORY", address(0));
        string memory label  = vm.envOr("NATIVE_LABEL", string("INK"));
        address forwarder    = vm.envOr("GELATO_TRUSTED_FORWARDER", DEFAULT_FORWARDER);
        bytes32 labelBytes   = toBytes32(label);

        vm.startBroadcast();

        // 1. Factory (includes all 8 fee tiers in constructor)
        TsunamiV3Factory factory = new TsunamiV3Factory();

        // 2. On-chain NFT descriptor (Tsunami SVG art)
        TsunamiV3TokenPositionDescriptor descriptor =
            new TsunamiV3TokenPositionDescriptor(weth9, labelBytes);

        // 3. Position manager — ERC-2771 forwarder wired in at construction
        TsunamiV3PositionManager positionManager =
            new TsunamiV3PositionManager(
                address(factory),
                weth9,
                address(descriptor),
                forwarder           // Gelato trusted forwarder for gasless LP ops
            );

        // 4. Quoter (off-chain price simulation)
        TsunamiQuoterV2 quoter = new TsunamiQuoterV2(address(factory), weth9);

        // 5. Tick lens (off-chain tick data)
        TsunamiTickLens tickLens = new TsunamiTickLens();

        // 6. Swap router
        TsunamiSwapRouter02 swapRouter =
            new TsunamiSwapRouter02(v2Factory, address(factory), address(positionManager), weth9);

        vm.stopBroadcast();

        // ── Output addresses for .env ────────────────────────────────────────
        console2.log("=== Tsunami V3 Core Deployment ===");
        console2.log("TsunamiV3Factory            ", address(factory));
        console2.log("TsunamiV3TokenPositionDescriptor", address(descriptor));
        console2.log("TsunamiV3PositionManager    ", address(positionManager));
        console2.log("TsunamiQuoterV2             ", address(quoter));
        console2.log("TsunamiTickLens             ", address(tickLens));
        console2.log("TsunamiSwapRouter02         ", address(swapRouter));
        console2.log("---");
        console2.log("WETH9                       ", weth9);
        console2.log("Gelato Forwarder            ", forwarder);
    }

    function toBytes32(string memory value) private pure returns (bytes32 result) {
        bytes memory temp = bytes(value);
        require(temp.length <= 32, "label too long");
        assembly {
            result := mload(add(temp, 32))
        }
    }
}
