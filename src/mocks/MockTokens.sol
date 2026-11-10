// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("ERC-20 Test token", "ETT") { }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract MockFeeToken is ERC20 {
    uint256 public feeBps;

    constructor() ERC20("Mock Fee Token", "MFT") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFee(uint256 bps) external {
        feeBps = bps;
    }

    function _update(address from, address to, uint256 amount) internal override {
        uint256 fee = from != address(0) && to != address(0) ? amount * feeBps / 10_000 : 0;

        if (fee != 0) {
            super._update(from, address(0), fee);
        }

        super._update(from, to, amount - fee);
    }
}

contract MockWrappedDMD is MockFeeToken {
    bool public underpay;

    function setUnderpay(bool value) external {
        underpay = value;
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        Address.sendValue(payable(msg.sender), underpay ? amount - 1 : amount);
    }
}
