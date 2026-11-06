// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import { Test } from "forge-std/Test.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { ScintillaRecovery } from "../src/ScintillaRecovery.sol";

contract RevertingReceiver {
    receive() external payable {
        revert("receiver rejected payment");
    }
}

contract ReentrantGovernance {
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

contract MockERC20 is ERC20 {
    constructor() ERC20("Recovery test token", "RTT") { }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract ScintillaRecoveryTest is Test {
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address internal constant GOVERNANCE = 0xDA0da0da0Da0Da0Da0DA00DA0da0da0DA0DA0dA0;

    ScintillaRecovery internal implementation;
    ScintillaRecovery internal recovery;

    address internal alice;
    address internal bob;
    address internal attacker;

    event Payout(address indexed receiver, uint256 indexed amount);

    function setUp() external {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        attacker = makeAddr("attacker");

        implementation = new ScintillaRecovery();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation), GOVERNANCE, abi.encodeCall(ScintillaRecovery.initialize, ())
        );

        recovery = ScintillaRecovery(address(proxy));
    }

    function test_DeploymentInitializesOwnerAndProxyAdmin() external view {
        assertEq(recovery.owner(), GOVERNANCE);

        address proxyAdmin = address(uint160(uint256(vm.load(address(recovery), ERC1967_ADMIN_SLOT))));
        assertEq(ProxyAdmin(proxyAdmin).owner(), GOVERNANCE);
    }

    function test_ImplementationCannotBeInitialized() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize();
    }

    function test_ProxyCannotBeInitializedTwice() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        recovery.initialize();
    }

    function test_OnlyGovernanceCanPayout() external {
        ScintillaRecovery.PayoutInstruction[] memory instructions = _singleInstruction(alice, 1 ether);
        vm.deal(address(recovery), 1 ether);

        vm.expectRevert(ScintillaRecovery.OnlyGovernance.selector);
        vm.prank(attacker);
        recovery.payout(instructions);

        assertEq(alice.balance, 0);
        assertEq(address(recovery).balance, 1 ether);
    }

    function test_GovernanceCanExecuteBatchPayout() external {
        ScintillaRecovery.PayoutInstruction[] memory instructions = new ScintillaRecovery.PayoutInstruction[](2);
        instructions[0] = ScintillaRecovery.PayoutInstruction({ target: alice, amount: 1 ether });
        instructions[1] = ScintillaRecovery.PayoutInstruction({ target: bob, amount: 2 ether });
        vm.deal(address(recovery), 3 ether);

        vm.expectEmit(true, true, false, true, address(recovery));
        emit Payout(alice, 1 ether);
        vm.expectEmit(true, true, false, true, address(recovery));
        emit Payout(bob, 2 ether);

        vm.prank(GOVERNANCE);
        recovery.payout(instructions);

        assertEq(alice.balance, 1 ether);
        assertEq(bob.balance, 2 ether);
        assertEq(address(recovery).balance, 0);
    }

    function testFuzz_GovernanceCanPayoutNativeBalance(uint96 amount) external {
        vm.assume(amount > 0);
        vm.deal(address(recovery), amount);

        vm.prank(GOVERNANCE);
        recovery.payout(_singleInstruction(alice, amount));

        assertEq(alice.balance, amount);
        assertEq(address(recovery).balance, 0);
    }

    function test_ReentrancyGuardBlocksGovernanceReceiverReentry() external {
        ReentrantGovernance template = new ReentrantGovernance();
        vm.etch(GOVERNANCE, address(template).code);

        ReentrantGovernance governance = ReentrantGovernance(payable(GOVERNANCE));
        governance.configure(recovery);
        vm.deal(address(recovery), 2 ether);

        vm.prank(GOVERNANCE);
        recovery.payout(_singleInstruction(GOVERNANCE, 1 ether));

        assertTrue(governance.reentryBlocked());
        assertEq(governance.observedError(), ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        assertEq(address(recovery).balance, 1 ether);
    }

    function test_AuditZeroAddressInstructionBurnsFunds() external {
        uint256 amount = 1 ether;
        uint256 zeroAddressBalanceBefore = address(0).balance;
        vm.deal(address(recovery), amount);

        vm.prank(GOVERNANCE);
        recovery.payout(_singleInstruction(address(0), amount));

        assertEq(address(0).balance, zeroAddressBalanceBefore + amount);
        assertEq(address(recovery).balance, 0);
    }

    function test_AuditRevertingReceiverBlocksTheEntireBatch() external {
        RevertingReceiver revertingReceiver = new RevertingReceiver();
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

    function test_AuditProxyRejectsOrdinaryNativeTransfers() external {
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        (bool success,) = address(recovery).call{ value: 1 ether }("");

        assertFalse(success);
        assertEq(alice.balance, 1 ether);
        assertEq(address(recovery).balance, 0);
    }

    function test_AuditERC20TokensHaveNoRecoveryPath() external {
        MockERC20 token = new MockERC20();
        token.mint(address(recovery), 100 ether);

        vm.prank(GOVERNANCE);
        (bool success,) = address(recovery).call(abi.encodeCall(ERC20.transfer, (alice, 100 ether)));

        assertFalse(success);
        assertEq(token.balanceOf(address(recovery)), 100 ether);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_InsufficientBalanceRevertsWithoutPartialPayout() external {
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

    function _singleInstruction(
        address target,
        uint256 amount
    ) private pure returns (ScintillaRecovery.PayoutInstruction[] memory instructions) {
        instructions = new ScintillaRecovery.PayoutInstruction[](1);
        instructions[0] = ScintillaRecovery.PayoutInstruction({ target: target, amount: amount });
    }
}
