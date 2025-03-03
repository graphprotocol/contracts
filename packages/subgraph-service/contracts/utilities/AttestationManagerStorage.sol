// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

/**
 * @title AttestationManagerStorage
 * @notice This contract holds all the storage variables for the Attestation Manager contract.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract AttestationManagerV1Storage {
    /// @dev EIP712 domain separator
    bytes32 internal _domainSeparator;

    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;
}
