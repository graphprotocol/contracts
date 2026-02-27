// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IDataService } from "./IDataService.sol";

/**
 * @title Interface for data services that manage indexing agreements.
 * @author Edge & Node
 * @notice Extension for the {IDataService} contract to support payer-initiated
 * cancellation of indexing agreements. Any data service that participates in
 * agreement lifecycle management via {ServiceAgreementManager} should implement
 * this interface.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IDataServiceAgreements is IDataService {
    /**
     * @notice Cancel an indexing agreement by payer / signer.
     * @param agreementId The id of the indexing agreement
     */
    function cancelIndexingAgreementByPayer(bytes16 agreementId) external;
}
