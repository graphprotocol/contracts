// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

abstract contract ProvisionManagerV1Storage {
    /// @notice The minimum amount of tokens required to register a provision in the data service
    uint256 public minimumProvisionTokens;

    /// @notice The maximum amount of tokens allowed to register a provision in the data service
    uint256 public maximumProvisionTokens;

    /// @notice Minimum delegation to self stake ratio required
    uint32 public minimumDelegationRatio;

    /// @notice Maximum delegation to self stake ratio allowed for a service provider
    uint32 public maximumDelegationRatio;

    /// @notice The minimum thawing period required to register a provision in the data service
    uint64 public minimumThawingPeriod;

    /// @notice The maximum thawing period allowed to register a provision in the data service
    uint64 public maximumThawingPeriod;

    /// @notice The minimum verifier cut required to register a provision in the data service
    uint32 public minimumVerifierCut;

    /// @notice The maximum verifier cut allowed to register a provision in the data service
    uint32 public maximumVerifierCut;

    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;
}
