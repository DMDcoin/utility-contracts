// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { DexFeeCollector } from "../src/DexFeeCollector.sol";

contract DeployDexFeeCollector is Script {
    function run() external {
        address governance = 0xDA0da0da0Da0Da0Da0DA00DA0da0da0DA0DA0dA0;
        address payable reinsertPot = payable(0x2000000000000000000000000000000000000001);
        address router = 0x8B9AaCF84AFFf11e2A318f5f4EA35D25E660B9C9;
        address wdmd = 0x2B1Bb4D22309af4330C216D797298b63Dbe97eA6;

        Options memory opts;

        opts.unsafeSkipProxyAdminCheck = true;

        vm.startBroadcast();

        address collector = payable(Upgrades.deployTransparentProxy(
                "DexFeeCollector.sol:DexFeeCollector",
                governance,
                abi.encodeCall(DexFeeCollector.initialize, (wdmd, reinsertPot, router)),
                opts
            ));

        vm.stopBroadcast();

        console.log("DexFeeCollector: %s", address(collector));
        console.log("ProxyAdmin: %s", Upgrades.getAdminAddress(address(collector)));
    }
}
