// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { ScintillaRecovery } from "src/ScintillaRecovery.sol";

contract MockReentrantGovernance {
    ScintillaRecovery private recovery;

    bool public reentryBlocked;
    bytes4 public observedError;

    function configure(ScintillaRecovery recovery_) external {
        recovery = recovery_;
    }

    receive() external payable {
        ScintillaRecovery.PayoutInstruction[] memory nested = new ScintillaRecovery.PayoutInstruction[](1);
        nested[0] = ScintillaRecovery.PayoutInstruction({ target: address(0xBEEF), amount: 1 });

        try recovery.payout(nested) {
            reentryBlocked = false;
        } catch (bytes memory reason) {
            bytes4 selector;
            if (reason.length >= 4) {
                assembly ("memory-safe") {
                    selector := mload(add(reason, 0x20))
                }
            }

            observedError = selector;
            reentryBlocked = selector == ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector;
        }
    }
}
