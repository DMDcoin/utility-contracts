// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

/// @dev Minimal interface of the deployed DMDSwap router, including its native-DMD swap variant.
interface IDmdSwapRouter {
    function WDMD() external view returns (address);

    function swapExactTokensForDMDSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}
