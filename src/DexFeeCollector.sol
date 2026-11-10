// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IDmdSwapRouter } from "./interfaces/IDmdSwapRouter.sol";
import { IWrappedDMD } from "./interfaces/IWrappedDMD.sol";

/// @title DexFeeCollector
/// @notice Converts ERC-20 DMDSwap fees into native DMD and transfers them to reinsert pot.
contract DexFeeCollector is Initializable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    address public constant GOVERNANCE_ADDRESS = 0xDA0da0da0Da0Da0Da0DA00DA0da0da0DA0DA0dA0;

    address payable public reinsertPot;

    IWrappedDMD public wdmd;
    IDmdSwapRouter public router;

    mapping(address => address[]) private _swapPaths;

    error OnlyGovernance();
    error InvalidAddress();
    error InvalidSwapPath();
    error UnsupportedRouter();
    error NothingToConvert();
    error NothingToForward();

    event FeesConverted(address indexed caller, address indexed token, uint256 amountIn, uint256 dmdOut);
    event NativeForwarded(address indexed caller, uint256 amount);
    event SwapPathUpdated(address indexed token, address[] path);

    modifier onlyGovernance() {
        if (msg.sender != GOVERNANCE_ADDRESS) {
            revert OnlyGovernance();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _wdmd, address payable _reinsertPot, address _router) external initializer {
        if (_wdmd == address(0) || _reinsertPot == address(0) || _router == address(0)) {
            revert InvalidAddress();
        }

        __ReentrancyGuard_init();

        router = IDmdSwapRouter(_router);
        wdmd = IWrappedDMD(_wdmd);
        reinsertPot = _reinsertPot;

        if (router.WDMD() != _wdmd) {
            revert UnsupportedRouter();
        }
    }

    /// @dev Accept native payouts from the WrappedDMD and direct native fee deposits.
    receive() external payable { }

    /// @notice Configures a token's swap path. An empty path restores the direct token/WDMD route.
    function setSwapPath(address token, address[] calldata path) external onlyGovernance {
        if (token == address(0) || token == address(wdmd)) {
            revert InvalidSwapPath();
        }

        if (path.length == 0) {
            delete _swapPaths[token];

            emit SwapPathUpdated(token, path);

            return;
        }

        if (path.length < 2 || path.length > 5) {
            revert InvalidSwapPath();
        }

        if (path[0] != token || path[path.length - 1] != address(wdmd)) {
            revert InvalidSwapPath();
        }

        for (uint256 i; i < path.length; ++i) {
            if (path[i] == address(0)) {
                revert InvalidSwapPath();
            }

            if (path[i].code.length == 0) {
                revert InvalidSwapPath();
            }
        }

        _swapPaths[token] = path;

        emit SwapPathUpdated(token, path);
    }

    /// @notice Returns the custom path, or an empty array when the direct token/WDMD route is used.
    function swapPath(address token) external view returns (address[] memory) {
        return _swapPaths[token];
    }

    /// @notice Converts the entire balance of a fee token and pays native DMD to the reinsert pot.
    /// @dev Uses the governance-configured path, or the direct token/WDMD pair by default, accepting any
    /// nonzero output with no price protection.
    function convert(address token) external nonReentrant {
        uint256 amountIn = IERC20(token).balanceOf(address(this));

        if (amountIn == 0) {
            revert NothingToConvert();
        }

        uint256 minimum = 1;
        uint256 nativeBefore = address(this).balance;

        if (token == address(wdmd)) {
            minimum = amountIn;

            wdmd.withdraw(amountIn);
        } else {
            address[] memory path = _swapPaths[token];
            if (path.length == 0) {
                path = new address[](2);
                path[0] = token;
                path[1] = address(wdmd);
            }

            IERC20(token).forceApprove(address(router), amountIn);

            router.swapExactTokensForDMDSupportingFeeOnTransferTokens(
                amountIn, minimum, path, address(this), block.timestamp
            );

            IERC20(token).forceApprove(address(router), 0);
        }

        uint256 dmdOut = address(this).balance - nativeBefore;
        if (dmdOut < minimum) {
            revert NothingToForward();
        }

        emit FeesConverted(msg.sender, token, amountIn, dmdOut);

        _forwardToReinsertPot(dmdOut);
    }

    /// @notice Sends any directly deposited native DMD to the reinsert pot.
    function forwardNative() external nonReentrant returns (uint256 amount) {
        amount = address(this).balance;
        if (amount == 0) {
            revert NothingToForward();
        }

        _forwardToReinsertPot(amount);
    }

    function _forwardToReinsertPot(uint256 amount) private {
        Address.sendValue(reinsertPot, amount);

        emit NativeForwarded(msg.sender, amount);
    }
}
