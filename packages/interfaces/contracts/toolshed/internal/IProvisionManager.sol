// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

// solhint-disable use-natspec

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

interface IProvisionManager {
    // Events
    event ProvisionTokensRangeSet(uint256 min, uint256 max);
    event DelegationRatioSet(uint32 ratio);
    event VerifierCutRangeSet(uint32 min, uint32 max);
    event ThawingPeriodRangeSet(uint64 min, uint64 max);

    // Errors
    error ProvisionManagerInvalidValue(bytes message, uint256 value, uint256 min, uint256 max);
    error ProvisionManagerInvalidRange(uint256 min, uint256 max);
    error ProvisionManagerNotAuthorized(address serviceProvider, address caller);
    error ProvisionManagerProvisionNotFound(address serviceProvider);
}
