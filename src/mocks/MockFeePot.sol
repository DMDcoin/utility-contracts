// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { DexFeeCollector } from "src/DexFeeCollector.sol";

contract MockFeePot {
    bool public rejectPayment;
    bool public tryReentry;
    bool public reentryBlocked;

    function configure(bool rejectPayment_, bool tryReentry_) external {
        rejectPayment = rejectPayment_;
        tryReentry = tryReentry_;
    }

    receive() external payable {
        require(!rejectPayment, "rejected");
        if (tryReentry) {
            try DexFeeCollector(payable(msg.sender)).forwardNative() { }
            catch (bytes memory reason) {
                reentryBlocked = bytes4(reason) == ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector;
            }
        }
    }
}
