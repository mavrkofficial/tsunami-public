// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {Permit2} from "lib/permit2/src/Permit2.sol";
import {UniversalRouter} from "contracts/UniversalRouter.sol";
import {RouterParameters} from "contracts/base/RouterImmutables.sol";

contract DeployTsunamiUniversalRouter is Script {
    bytes32 private constant DEFAULT_POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    function _buildParams(address permit2Addr) internal returns (RouterParameters memory params) {
        params.permit2 = permit2Addr;
        params.weth9 = vm.envAddress("WETH9");
        params.v2Factory = vm.envOr("V2_FACTORY", address(0));
        params.v3Factory = vm.envAddress("V3_FACTORY");
        params.pairInitCodeHash = vm.envOr("V2_PAIR_INIT_CODE_HASH", bytes32(0));
        params.poolInitCodeHash = vm.envOr("V3_POOL_INIT_CODE_HASH", DEFAULT_POOL_INIT_CODE_HASH);
        params.seaportV1_5 = vm.envOr("SEAPORT_V1_5", address(0));
        params.seaportV1_4 = vm.envOr("SEAPORT_V1_4", address(0));
        params.openseaConduit = vm.envOr("OPENSEA_CONDUIT", address(0));
        params.nftxZap = vm.envOr("NFTX_ZAP", address(0));
        params.x2y2 = vm.envOr("X2Y2", address(0));
        params.foundation = vm.envOr("FOUNDATION", address(0));
        params.sudoswap = vm.envOr("SUDOSWAP", address(0));
        params.elementMarket = vm.envOr("ELEMENT_MARKET", address(0));
        params.nft20Zap = vm.envOr("NFT20_ZAP", address(0));
        params.cryptopunks = vm.envOr("CRYPTOPUNKS", address(0));
        params.looksRareV2 = vm.envOr("LOOKSRARE_V2", address(0));
        params.routerRewardsDistributor = vm.envOr("ROUTER_REWARDS_DISTRIBUTOR", address(0));
        params.looksRareRewardsDistributor = vm.envOr("LOOKSRARE_REWARDS_DISTRIBUTOR", address(0));
        params.looksRareToken = vm.envOr("LOOKSRARE_TOKEN", address(0));
    }

    function run() external {
        address permit2 = vm.envOr("PERMIT2", address(0));

        vm.startBroadcast();

        if (permit2 == address(0)) {
            permit2 = address(new Permit2());
        }

        RouterParameters memory params = _buildParams(permit2);
        UniversalRouter router = new UniversalRouter(params);

        vm.stopBroadcast();

        console2.log("Permit2", permit2);
        console2.log("UniversalRouter", address(router));
    }
}
