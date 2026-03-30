// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IAgreementStateChangeCallback } from "../horizon/IAgreementStateChangeCallback.sol";

/**
 * @title Interface for data services that manage indexing agreements.
 * @author Edge & Node
 * @notice Callback interface that data services implement to participate in
 * agreement lifecycle management via {RecurringCollector}.
 * - {acceptAgreement}: Reverting callback during accept — validates and sets up
 *   domain-specific state (e.g. allocation binding). CAN revert to reject the transition.
 * - {afterAgreementStateChange} (inherited): Non-reverting notification on lifecycle events.
 *   Implementations should filter by state flags and ignore unrecognised combinations.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IDataServiceAgreements is IAgreementStateChangeCallback {
    /**
     * @notice Called when a service provider accepts an agreement (initial or update).
     * @dev Revert to reject the acceptance. Called before the collector finalizes state.
     * For initial acceptance the data service should set up domain-specific state (e.g. bind allocation).
     * For updates the data service should validate and apply updated terms.
     * The data service can distinguish initial vs update by checking its own state for the agreementId.
     * @param agreementId The ID of the agreement being accepted
     * @param versionHash The hash of the terms version being accepted
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider accepting
     * @param metadata The agreement metadata (data-service-specific)
     * @param extraData Opaque data forwarded from the accept calldata (e.g. allocationId)
     */
    function acceptAgreement(
        bytes16 agreementId,
        bytes32 versionHash,
        address payer,
        address serviceProvider,
        bytes calldata metadata,
        bytes calldata extraData
    ) external;
}
