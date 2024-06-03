// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

abstract contract AttestationManagerV1Storage {
    /// @dev EIP712 domain separator
    bytes32 internal _domainSeparator;

    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;
}
