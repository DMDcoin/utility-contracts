// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { DexFeeCollector } from "src/DexFeeCollector.sol";
import { IDmdSwapRouter } from "src/interfaces/IDmdSwapRouter.sol";

contract MockRouter is IDmdSwapRouter {
    address public immutable WDMD;
    address public constant unwrapper = address(0xBEEF);

    mapping(address tokenA => mapping(address tokenB => bool exists)) public pairExists;

    uint256 public output = 2 ether;
    uint256 public reportedOutput = 2 ether;
    bool public ignoreMinimum;
    bool public tryReentry;
    bool public reentryBlocked;
    uint256 public protocolFeeRefund;
    uint256 public lastAmountIn;
    uint256 public lastMinimum;
    uint256 public lastDeadline;
    uint256 public lastAllowance;
    address public lastRecipient;
    bytes32 public lastPathHash;
    uint256 public receivedInput;

    constructor(address wrapped) {
        WDMD = wrapped;
    }

    function setPair(address tokenA, address tokenB, bool exists) external {
        pairExists[tokenA][tokenB] = exists;
        pairExists[tokenB][tokenA] = exists;
    }

    function configure(uint256 output_, bool ignoreMinimum_, bool tryReentry_, uint256 protocolFeeRefund_) external {
        output = output_;
        reportedOutput = output_;
        ignoreMinimum = ignoreMinimum_;
        tryReentry = tryReentry_;
        protocolFeeRefund = protocolFeeRefund_;
    }

    function setReportedOutput(uint256 amount) external {
        reportedOutput = amount;
    }

    function swapExactTokensForDMDSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256) {
        require(block.timestamp <= deadline, "expired");
        require(amountOutMin != 0, "zero minimum");
        require(path.length >= 2 && path.length <= 5 && path[path.length - 1] == WDMD, "invalid path");
        for (uint256 i; i + 1 < path.length; ++i) {
            require(pairExists[path[i]][path[i + 1]], "pair not found");
        }
        require(ignoreMinimum || output >= amountOutMin, "slippage");

        lastAmountIn = amountIn;
        lastMinimum = amountOutMin;
        lastDeadline = deadline;
        lastRecipient = to;
        lastPathHash = keccak256(abi.encode(path));
        IERC20 token = IERC20(path[0]);
        lastAllowance = token.allowance(msg.sender, address(this));
        uint256 beforeBalance = token.balanceOf(address(this));
        require(token.transferFrom(msg.sender, address(this), amountIn));
        receivedInput = token.balanceOf(address(this)) - beforeBalance;

        if (protocolFeeRefund != 0) require(token.transfer(msg.sender, protocolFeeRefund));
        if (tryReentry) {
            try DexFeeCollector(payable(msg.sender)).convert(path[0]) { }
            catch (bytes memory reason) {
                reentryBlocked = bytes4(reason) == ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector;
            }
        }
        Address.sendValue(payable(to), output);
        return reportedOutput;
    }
}
