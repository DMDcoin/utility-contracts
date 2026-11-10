// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { DexFeeCollector } from "src/DexFeeCollector.sol";
import { MockFeePot } from "src/mocks/MockFeePot.sol";
import { MockRouter } from "src/mocks/MockRouter.sol";
import { MockFeeToken, MockWrappedDMD } from "src/mocks/MockTokens.sol";

contract DexFeeCollectorTest is Test {
    address private constant DAO = 0xDA0da0da0Da0Da0Da0DA00DA0da0da0DA0DA0dA0;
    uint256 private constant INITIAL_BALANCE = 100 ether;

    address private caller;

    DexFeeCollector private collector;

    MockFeeToken private token;
    MockFeeToken private bridge;
    MockRouter private router;
    MockWrappedDMD private wrapped;
    MockFeePot private pot;

    function setUp() external {
        caller = makeAddr("caller");

        token = new MockFeeToken();
        bridge = new MockFeeToken();
        wrapped = new MockWrappedDMD();
        router = new MockRouter(address(wrapped));
        pot = new MockFeePot();

        vm.deal(address(router), INITIAL_BALANCE);
        vm.deal(address(wrapped), INITIAL_BALANCE);
        router.setPair(address(token), address(wrapped), true);
        router.setPair(address(token), address(bridge), true);
        router.setPair(address(bridge), address(wrapped), true);

        collector = _deploy(address(wrapped), payable(address(pot)), address(router));
        token.mint(address(collector), INITIAL_BALANCE);
    }

    function test_Initialize() external view {
        assertEq(collector.reinsertPot(), address(pot));
        assertEq(address(collector.wdmd()), address(wrapped));
        assertEq(address(collector.router()), address(router));
        assertEq(collector.GOVERNANCE_ADDRESS(), DAO);
        assertEq(_admin().owner(), DAO);
        assertEq(collector.swapPath(address(token)).length, 0);
    }

    function test_Initialize_Reinitialization_Reverts() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        collector.initialize(address(wrapped), payable(caller), address(router));
    }

    function test_Initialize_ImplementationInitialization_Reverts() external {
        DexFeeCollector impl = DexFeeCollector(payable(Upgrades.getImplementationAddress(address(collector))));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(address(wrapped), payable(address(pot)), address(router));
    }

    function test_Initialize_ZeroAddressArguments_Reverts() external {
        vm.expectRevert(DexFeeCollector.InvalidAddress.selector);
        _deploy(address(0), payable(address(pot)), address(router));

        vm.expectRevert(DexFeeCollector.InvalidAddress.selector);
        _deploy(address(wrapped), payable(address(0)), address(router));

        vm.expectRevert(DexFeeCollector.InvalidAddress.selector);
        _deploy(address(wrapped), payable(address(pot)), address(0));
    }

    function test_Initialize_UnsupportedRouter_Reverts() external {
        MockRouter wrongRouter = new MockRouter(address(token));
        vm.expectRevert(DexFeeCollector.UnsupportedRouter.selector);
        _deploy(address(wrapped), payable(address(pot)), address(wrongRouter));
    }

    function test_SetSwapPath_OnlyGovernance_Reverts() external {
        address[] memory path = _bridgePath();
        vm.prank(caller);
        vm.expectRevert(DexFeeCollector.OnlyGovernance.selector);
        collector.setSwapPath(address(token), path);
        assertEq(collector.swapPath(address(token)).length, 0);
    }

    function test_SetSwapPath_EmitsEvent() external {
        address[] memory path = _bridgePath();
        vm.expectEmit(true, false, false, true, address(collector));
        emit DexFeeCollector.SwapPathUpdated(address(token), path);
        _setPath(path);

        assertEq(collector.swapPath(address(token)), path);
        assertEq(token.balanceOf(address(collector)), INITIAL_BALANCE);
        assertEq(token.allowance(address(collector), address(router)), 0);
    }

    function test_SetSwapPath_RemovesCustomRoute() external {
        _setPath(_bridgePath());
        address[] memory empty = new address[](0);
        vm.expectEmit(true, false, false, true, address(collector));
        emit DexFeeCollector.SwapPathUpdated(address(token), empty);
        _setPath(empty);

        assertEq(collector.swapPath(address(token)).length, 0);
    }

    function test_SetSwapPath_InvalidRoute_Reverts() external {
        address[] memory path = new address[](1);
        path[0] = address(token);
        _expectInvalidPath(address(token), path);
        _expectInvalidPath(address(token), new address[](6));
    }

    function test_SetSwapPath_InvalidStartEndTokens_Reverts() external {
        address[] memory path = _directPath();
        path[0] = address(bridge);
        _expectInvalidPath(address(token), path);

        path = _directPath();
        path[1] = address(bridge);
        _expectInvalidPath(address(token), path);
    }

    function test_SetSwapPath_ZeroAddress_Reverts() external {
        address[] memory path = _bridgePath();
        path[1] = address(0);
        _expectInvalidPath(address(token), path);
    }

    function test_SetSwapPath_EOA_Reverts() external {
        address[] memory path = _bridgePath();
        path[1] = caller;
        _expectInvalidPath(address(token), path);
    }

    function test_SetSwapPath_ZeroTokenAddress_Reverts() external {
        _expectInvalidPath(address(0), new address[](0));
    }

    function test_SetSwapPath_WDMDAddress_Reverts() external {
        _expectInvalidPath(address(wrapped), new address[](0));
        address[] memory path = _directPath();
        path[0] = address(wrapped);
        _expectInvalidPath(address(wrapped), path);
    }

    function test_Convert() external {
        vm.expectEmit(true, true, false, true, address(collector));
        emit DexFeeCollector.FeesConverted(caller, address(token), INITIAL_BALANCE, 2 ether);
        vm.expectEmit(true, false, false, true, address(collector));
        emit DexFeeCollector.NativeForwarded(caller, 2 ether);
        vm.prank(caller);
        collector.convert(address(token));

        assertEq(address(pot).balance, 2 ether);
        assertEq(caller.balance, 0);
        assertEq(address(collector).balance, 0);
        assertEq(token.balanceOf(address(collector)), 0);
        assertEq(token.allowance(address(collector), address(router)), 0);
        assertEq(router.lastAllowance(), INITIAL_BALANCE);
        assertEq(router.lastAmountIn(), INITIAL_BALANCE);
        assertEq(router.lastMinimum(), 1);
        assertEq(router.lastDeadline(), block.timestamp);
        assertEq(router.lastRecipient(), address(collector));
        assertEq(router.lastPathHash(), keccak256(abi.encode(_directPath())));
    }

    function test_Convert_MultiHopRoute() external {
        router.setPair(address(token), address(wrapped), false);
        vm.expectRevert("pair not found");
        collector.convert(address(token));
        _assertUnchanged();

        address[] memory path = _bridgePath();
        _setPath(path);
        vm.prank(caller);
        collector.convert(address(token));

        assertEq(router.lastPathHash(), keccak256(abi.encode(path)));
        assertEq(router.lastAmountIn(), INITIAL_BALANCE);
        assertEq(router.lastMinimum(), 1);
        assertEq(router.lastRecipient(), address(collector));
        assertEq(token.balanceOf(address(collector)), 0);
        assertEq(token.allowance(address(collector), address(router)), 0);
        assertEq(address(pot).balance, 2 ether);
        assertEq(caller.balance, 0);
    }

    function test_Convert_FiveTokensPath() external {
        address[] memory path = _fiveTokenPath();
        _setPath(path);

        router.setPair(address(token), address(wrapped), false);
        collector.convert(address(token));

        assertEq(router.lastPathHash(), keccak256(abi.encode(path)));
        assertEq(address(pot).balance, 2 ether);
    }

    function test_Convert_WholeBalance() external {
        token.mint(address(collector), INITIAL_BALANCE + 1);
        collector.convert(address(token));

        assertEq(router.lastAmountIn(), 2 * INITIAL_BALANCE + 1);
        assertEq(token.balanceOf(address(collector)), 0);

        vm.expectRevert(DexFeeCollector.NothingToConvert.selector);
        collector.convert(address(token));
    }

    function test_Conver_ZeroOutput_Reverts() external {
        router.configure(0, false, false, 0);
        vm.expectRevert("slippage");
        collector.convert(address(token));
        _assertUnchanged();
    }

    function test_Convert_Reentrancy_Reverts() external {
        _setPath(_bridgePath());

        router.configure(2 ether, false, true, 0);
        pot.configure(false, true);
        collector.convert(address(token));

        assertTrue(router.reentryBlocked());
        assertTrue(pot.reentryBlocked());
        assertEq(address(pot).balance, 2 ether);
    }

    function test_Convert_WholeWDMDBalance() external {
        uint256 amount = 1 ether;
        wrapped.mint(address(collector), amount);

        vm.expectEmit(true, true, false, true, address(collector));
        emit DexFeeCollector.FeesConverted(caller, address(wrapped), amount, amount);
        vm.expectEmit(true, false, false, true, address(collector));
        emit DexFeeCollector.NativeForwarded(caller, amount);
        vm.prank(caller);
        collector.convert(address(wrapped));

        assertEq(address(pot).balance, amount);
        assertEq(wrapped.balanceOf(address(collector)), 0);
        assertEq(router.lastAmountIn(), 0);
        assertEq(caller.balance, 0);
    }

    function test_ForwardNative() external {
        vm.deal(caller, 4 ether);
        vm.prank(caller);
        (bool success,) = address(collector).call{ value: 4 ether }("");
        assertTrue(success);

        vm.expectEmit(true, false, false, true, address(collector));
        emit DexFeeCollector.NativeForwarded(caller, 4 ether);
        vm.prank(caller);

        assertEq(collector.forwardNative(), 4 ether);
        assertEq(address(pot).balance, 4 ether);
        assertEq(address(collector).balance, 0);
        assertEq(caller.balance, 0);
    }

    function testFuzz_Convert(uint96 rawExtraInput, uint96 rawOutput, uint96 rawDust, bool useCustomPath) external {
        if (useCustomPath) {
            _setPath(_bridgePath());
        }

        uint256 totalInput = INITIAL_BALANCE + uint256(rawExtraInput);
        uint256 output = bound(uint256(rawOutput), 1, INITIAL_BALANCE);

        token.mint(address(collector), rawExtraInput);
        router.configure(output, false, false, 0);

        vm.deal(address(collector), rawDust);
        vm.prank(caller);
        collector.convert(address(token));

        assertEq(router.lastAmountIn(), totalInput);
        assertEq(token.balanceOf(address(collector)), 0);
        assertEq(address(pot).balance, output);
        assertEq(address(collector).balance, rawDust);
        assertEq(caller.balance, 0);
        assertEq(token.allowance(address(collector), address(router)), 0);
    }

    function _deploy(address wrapped_, address payable recipient, address router_) private returns (DexFeeCollector) {
        DexFeeCollector impl = new DexFeeCollector();

        return DexFeeCollector(
            payable(address(
                    new TransparentUpgradeableProxy(
                        address(impl), DAO, abi.encodeCall(DexFeeCollector.initialize, (wrapped_, recipient, router_))
                    )
                ))
        );
    }

    function _setPath(address[] memory path) private {
        vm.prank(DAO);
        collector.setSwapPath(address(token), path);
    }

    function _expectInvalidPath(address token_, address[] memory path) private {
        vm.prank(DAO);
        vm.expectRevert(DexFeeCollector.InvalidSwapPath.selector);
        collector.setSwapPath(token_, path);
    }

    function _directPath() private view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(token);
        path[1] = address(wrapped);
    }

    function _bridgePath() private view returns (address[] memory path) {
        path = new address[](3);
        path[0] = address(token);
        path[1] = address(bridge);
        path[2] = address(wrapped);
    }

    function _fiveTokenPath() private returns (address[] memory path) {
        path = new address[](5);
        path[0] = address(token);
        path[1] = address(bridge);
        path[2] = address(new MockFeeToken());
        path[3] = address(new MockFeeToken());
        path[4] = address(wrapped);
        for (uint256 i; i + 1 < path.length; ++i) {
            router.setPair(path[i], path[i + 1], true);
        }
    }

    function _admin() private view returns (ProxyAdmin) {
        return ProxyAdmin(Upgrades.getAdminAddress(address(collector)));
    }

    function _assertUnchanged() private view {
        assertEq(token.balanceOf(address(collector)), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token.allowance(address(collector), address(router)), 0);
        assertEq(address(pot).balance, 0);
    }
}
