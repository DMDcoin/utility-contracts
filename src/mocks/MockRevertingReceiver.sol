// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

contract MockRevertingReceiver {
    receive() external payable {
        revert("receiver rejected payment");
    }
}
