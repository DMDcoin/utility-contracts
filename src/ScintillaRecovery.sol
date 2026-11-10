// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @dev Сontract for storing tokens recovered as a result of a Scintilla hardfork
contract ScintillaRecovery is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct PayoutInstruction {
        address target;
        uint256 amount;
    }

    address public constant GOVERNANCE_ADDRESS = 0xDA0da0da0Da0Da0Da0DA00DA0da0da0DA0DA0dA0;

    error OnlyGovernance();

    event Payout(address indexed receiver, uint256 indexed amount);

    modifier onlyGovernance() {
        if (msg.sender != GOVERNANCE_ADDRESS) {
            revert OnlyGovernance();
        }
        _;
    }

    /// @notice Prevents initialization of the implementation contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    function initialize() external initializer {
        __Ownable_init(GOVERNANCE_ADDRESS);
        __ReentrancyGuard_init();
    }

    function payout(PayoutInstruction[] calldata instructions) external onlyGovernance nonReentrant {
        for (uint256 i = 0; i < instructions.length; ++i) {
            PayoutInstruction memory inst = instructions[i];

            Address.sendValue(payable(inst.target), inst.amount);

            emit Payout(inst.target, inst.amount);
        }
    }
}
