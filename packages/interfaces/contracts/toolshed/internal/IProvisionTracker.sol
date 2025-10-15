// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable use-natspec

pragma solidity 0.8.27;

interface IProvisionTracker {
    // Errors
    error ProvisionTrackerInsufficientTokens(uint256 tokensAvailable, uint256 tokensRequired);
}
