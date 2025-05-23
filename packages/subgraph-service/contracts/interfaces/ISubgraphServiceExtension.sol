// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";

import { IndexingAgreement } from "../libraries/IndexingAgreement.sol";

interface ISubgraphServiceExtension {
    /**
     * @notice Accept an indexing agreement.
     */
    // function acceptIndexingAgreement(address allocationId, IRecurringCollector.SignedRCA calldata signedRCA) external;

    /**
     * @notice Update an indexing agreement.
     */
    function updateIndexingAgreement(address indexer, IRecurringCollector.SignedRCAU calldata signedRCAU) external;

    /**
     * @notice Cancel an indexing agreement by indexer / operator.
     */
    function cancelIndexingAgreement(address indexer, bytes16 agreementId) external;

    /**
     * @notice Cancel an indexing agreement by payer / signer.
     */
    function cancelIndexingAgreementByPayer(bytes16 agreementId) external;

    function getIndexingAgreement(
        bytes16 agreementId
    ) external view returns (IndexingAgreement.AgreementWrapper memory);
}
