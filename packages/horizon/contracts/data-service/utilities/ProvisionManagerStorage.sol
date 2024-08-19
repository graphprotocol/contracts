// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

/**
 * @title Storage layout for the {ProvisionManager} helper contract.
 */
abstract contract ProvisionManagerV1Storage {
    /// @notice The minimum amount of tokens required to register a provision in the data service
    uint256 public minimumProvisionTokens;

    /// @notice The maximum amount of tokens allowed to register a provision in the data service
    uint256 public maximumProvisionTokens;

    /// @notice The minimum thawing period required to register a provision in the data service
    uint64 public minimumThawingPeriod;

    /// @notice The maximum thawing period allowed to register a provision in the data service
    uint64 public maximumThawingPeriod;

    /// @notice The minimum verifier cut required to register a provision in the data service (in PPM)
    uint32 public minimumVerifierCut;

    /// @notice The maximum verifier cut allowed to register a provision in the data service (in PPM)
    uint32 public maximumVerifierCut;

    /// @notice How much delegation the service provider can effectively use
    /// @dev Max calculated as service provider's stake * delegationRatio
    uint32 public delegationRatio;

    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;
}
