// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IProviderEligibility
 * @author Edge & Node
 * @notice Minimal interface for checking service provider eligibility to receive rewards or payments.
 * Particularly relevant when paid by the protocol from issuance.
 * @dev This is the interface that consumers (e.g., RewardsManager, RecurringAgreementManager) need to check
 * if a provider is eligible to receive rewards.
 */
interface IProviderEligibility {
    /**
     * @notice Check if a service provider is eligible to receive rewards or other payments.
     * @param provider Address of the service provider
     * @return eligible True if the provider is eligible, false otherwise
     */
    function isEligible(address provider) external view returns (bool eligible);
}
