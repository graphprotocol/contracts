// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

// solhint-disable use-natspec

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

interface IProvisionTracker {
    // Errors
    error ProvisionTrackerInsufficientTokens(uint256 tokensAvailable, uint256 tokensRequired);
}
