// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { ScintillaRecovery } from "src/ScintillaRecovery.sol";
import { MockReentrantGovernance } from "src/mocks/MockReentrantGovernance.sol";
import { MockRevertingReceiver } from "src/mocks/MockRevertingReceiver.sol";

contract ScintillaRecoveryTest is Test {
    address internal constant GOVERNANCE = 0xDA0da0da0Da0Da0Da0DA00DA0da0da0DA0DA0dA0;

    ScintillaRecovery internal recovery;

    address internal alice;
    address internal bob;
    address internal attacker;

    function setUp() external {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        attacker = makeAddr("attacker");

        ScintillaRecovery impl = new ScintillaRecovery();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl), GOVERNANCE, abi.encodeCall(ScintillaRecovery.initialize, ())
        );

        recovery = ScintillaRecovery(address(proxy));
    }

    function test_Initialize() external view {
        assertEq(recovery.owner(), GOVERNANCE);

        address proxyAdmin = Upgrades.getAdminAddress(address(recovery));
        assertEq(ProxyAdmin(proxyAdmin).owner(), GOVERNANCE);
    }

    function test_Initilalize_Implementation_Reverts() external {
        address impl = Upgrades.getImplementationAddress(address(recovery));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ScintillaRecovery(impl).initialize();
    }

    function test_Initialize_Reinitialization_Reverts() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        recovery.initialize();
    }

    function test_Payout_OnlyGovernance() external {
        ScintillaRecovery.PayoutInstruction[] memory instructions = _singleInstruction(alice, 1 ether);
        vm.deal(address(recovery), 1 ether);

        vm.expectRevert(ScintillaRecovery.OnlyGovernance.selector);
        vm.prank(attacker);
        recovery.payout(instructions);

        assertEq(alice.balance, 0);
        assertEq(address(recovery).balance, 1 ether);
    }

    function test_Payout_BatchTransfers() external {
        ScintillaRecovery.PayoutInstruction[] memory instructions = new ScintillaRecovery.PayoutInstruction[](2);
        instructions[0] = ScintillaRecovery.PayoutInstruction({ target: alice, amount: 1 ether });
        instructions[1] = ScintillaRecovery.PayoutInstruction({ target: bob, amount: 2 ether });
        vm.deal(address(recovery), 3 ether);

        vm.expectEmit(true, true, false, true, address(recovery));
        emit ScintillaRecovery.Payout(alice, 1 ether);
        vm.expectEmit(true, true, false, true, address(recovery));
        emit ScintillaRecovery.Payout(bob, 2 ether);

        vm.prank(GOVERNANCE);
        recovery.payout(instructions);

        assertEq(alice.balance, 1 ether);
        assertEq(bob.balance, 2 ether);
        assertEq(address(recovery).balance, 0);
    }

    function test_Payout_BatchTransfers_RejectedReceiver_Reverts() external {
        MockRevertingReceiver revertingReceiver = new MockRevertingReceiver();

        ScintillaRecovery.PayoutInstruction[] memory instructions = new ScintillaRecovery.PayoutInstruction[](3);

        instructions[0] = ScintillaRecovery.PayoutInstruction({ target: alice, amount: 1 ether });
        instructions[1] = ScintillaRecovery.PayoutInstruction({ target: address(revertingReceiver), amount: 1 ether });
        instructions[2] = ScintillaRecovery.PayoutInstruction({ target: bob, amount: 1 ether });

        vm.deal(address(recovery), 3 ether);

        vm.expectRevert(Address.FailedInnerCall.selector);
        vm.prank(GOVERNANCE);
        recovery.payout(instructions);

        assertEq(alice.balance, 0);
        assertEq(bob.balance, 0);
        assertEq(address(recovery).balance, 3 ether);
    }

    function test_Payout_Reentrancy_Reverts() external {
        MockReentrantGovernance template = new MockReentrantGovernance();
        vm.etch(GOVERNANCE, address(template).code);

        MockReentrantGovernance governance = MockReentrantGovernance(payable(GOVERNANCE));
        governance.configure(recovery);
        vm.deal(address(recovery), 2 ether);

        vm.prank(GOVERNANCE);
        recovery.payout(_singleInstruction(GOVERNANCE, 1 ether));

        assertTrue(governance.reentryBlocked());
        assertEq(governance.observedError(), ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        assertEq(address(recovery).balance, 1 ether);
    }

    function test_TransferToRecoveryContract_Reverts() external {
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        (bool success,) = address(recovery).call{ value: 1 ether }("");

        assertFalse(success);
        assertEq(alice.balance, 1 ether);
        assertEq(address(recovery).balance, 0);
    }

    function test_Payout_InsufficientBalance_Reverts() external {
        ScintillaRecovery.PayoutInstruction[] memory instructions = new ScintillaRecovery.PayoutInstruction[](2);
        instructions[0] = ScintillaRecovery.PayoutInstruction({ target: alice, amount: 1 ether });
        instructions[1] = ScintillaRecovery.PayoutInstruction({ target: bob, amount: 2 ether });
        vm.deal(address(recovery), 2 ether);

        vm.expectRevert(abi.encodeWithSelector(Address.AddressInsufficientBalance.selector, address(recovery)));
        vm.prank(GOVERNANCE);
        recovery.payout(instructions);

        assertEq(alice.balance, 0);
        assertEq(bob.balance, 0);
        assertEq(address(recovery).balance, 2 ether);
    }

    function testFuzz_Payout(uint96 amount) external {
        vm.assume(amount > 0);
        vm.deal(address(recovery), amount);

        vm.prank(GOVERNANCE);
        recovery.payout(_singleInstruction(alice, amount));

        assertEq(alice.balance, amount);
        assertEq(address(recovery).balance, 0);
    }

    function _singleInstruction(
        address target,
        uint256 amount
    ) private pure returns (ScintillaRecovery.PayoutInstruction[] memory instructions) {
        instructions = new ScintillaRecovery.PayoutInstruction[](1);
        instructions[0] = ScintillaRecovery.PayoutInstruction({ target: target, amount: amount });
    }
}
