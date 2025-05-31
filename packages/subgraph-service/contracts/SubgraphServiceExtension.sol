// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { IHorizonStaking } from "@graphprotocol/horizon/contracts/interfaces/IHorizonStaking.sol";
import { ProvisionManagerLib } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionManagerLib.sol";

import { IndexingAgreement } from "./libraries/IndexingAgreement.sol";
import { SubgraphService } from "./SubgraphService.sol";

contract SubgraphServiceExtension is PausableUpgradeable {
    using IndexingAgreement for IndexingAgreement.Manager;

    modifier onlyValid(address indexer) {
        ProvisionManagerLib.requireAuthorizedForProvision(
            IHorizonStaking(_getBase().getGraphStaking()),
            indexer,
            address(this),
            msg.sender
        );
        _getBase().requireValidProvision(indexer);
        _getBase().requireRegisteredIndexer(indexer);
        _;
    }

    function updateIndexingAgreement(
        address indexer,
        IRecurringCollector.SignedRCAU calldata signedRCAU
    ) external whenNotPaused onlyValid(indexer) {
        IndexingAgreement._getManager().update(indexer, signedRCAU);
    }

    /**
     * @notice Cancel an indexing agreement by indexer / operator.
     * See {ISubgraphService.cancelIndexingAgreement}.
     *
     * @dev Can only be canceled on behalf of a valid indexer.
     *
     * Requirements:
     * - The indexer must be registered
     * - The caller must be authorized by the indexer
     * - The provision must be valid according to the subgraph service rules
     * - The agreement must be active
     *
     * Emits {IndexingAgreementCanceled} event
     *
     * @param agreementId The id of the agreement
     */
    function cancelIndexingAgreement(address indexer, bytes16 agreementId) external whenNotPaused onlyValid(indexer) {
        IndexingAgreement._getManager().cancel(indexer, agreementId);
    }

    /**
     * @notice Cancel an indexing agreement by payer / signer.
     * See {ISubgraphService.cancelIndexingAgreementByPayer}.
     *
     * Requirements:
     * - The caller must be authorized by the payer
     * - The agreement must be active
     *
     * Emits {IndexingAgreementCanceled} event
     *
     * @param agreementId The id of the agreement
     */
    function cancelIndexingAgreementByPayer(bytes16 agreementId) external whenNotPaused {
        IndexingAgreement._getManager().cancelByPayer(agreementId);
    }

    function getIndexingAgreement(
        bytes16 agreementId
    ) external view returns (IndexingAgreement.AgreementWrapper memory) {
        return IndexingAgreement._getManager().get(agreementId);
    }

    function _cancelAllocationIndexingAgreement(address _allocationId) internal {
        IndexingAgreement._getManager().cancelForAllocation(_allocationId);
    }

    function _getBase() internal view returns (SubgraphService) {
        return SubgraphService(address(this));
    }
}
