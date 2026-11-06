// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { ScintillaRecovery } from "../src/ScintillaRecovery.sol";

contract Deploy is Script {
    function run() external {
        address proxyAdminOwner = 0xDA0da0da0Da0Da0Da0DA00DA0da0da0DA0DA0dA0;
        Options memory opts;

        opts.unsafeSkipProxyAdminCheck = true;

        vm.startBroadcast();

        ScintillaRecovery sr = ScintillaRecovery(
            Upgrades.deployTransparentProxy(
                "ScintillaRecovery.sol:ScintillaRecovery",
                proxyAdminOwner,
                abi.encodeCall(ScintillaRecovery.initialize, ()),
                opts
            )
        );

        vm.stopBroadcast();

        console.log("ScintillaRecovery: %s", address(sr));
    }
}
