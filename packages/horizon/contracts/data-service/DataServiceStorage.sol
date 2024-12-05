// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

abstract contract DataServiceV1Storage {
    /// @dev Gap to allow adding variables in future upgrades
    /// Note that this contract is not upgradeable but might be inherited by an upgradeable contract
    uint256[50] private __gap;
}
