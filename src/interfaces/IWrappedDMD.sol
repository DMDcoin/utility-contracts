// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWrappedDMD is IERC20 {
    function withdraw(uint256 amount) external;
}
