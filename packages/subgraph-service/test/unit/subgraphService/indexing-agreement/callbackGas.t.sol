// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { OFFER_TYPE_NEW, OFFER_TYPE_UPDATE } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

/// @notice Gas measurement for SubgraphService.acceptAgreement callback.
/// RecurringCollector forwards at most MAX_CALLBACK_GAS (1.5M) to acceptAgreement
/// during auto-update. If the callback exceeds this budget, auto-update silently
/// fails and the agreement transitions to SETTLED.
///
/// These tests call acceptAgreement directly (pranking as the collector) to isolate
/// the data-service callback gas from the collector overhead.
contract SubgraphServiceCallbackGasTest is SubgraphServiceIndexingAgreementSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    /// @notice Must match MAX_CALLBACK_GAS in RecurringCollector.
    uint256 internal constant MAX_CALLBACK_GAS = 1_500_000;

    /// @notice Assert callbacks use less than half the budget.
    /// Leaves margin for cold storage and EVM repricing.
    uint256 internal constant GAS_THRESHOLD = MAX_CALLBACK_GAS / 2; // 750_000

    /// @notice Initial accept (onAcceptCallback): heaviest path with allocation binding,
    /// storage writes for agreement state, and allocationToActiveAgreementId mapping.
    function test_AcceptAgreement_GasWithinBudget_InitialAccept(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _generateAcceptableRCA(ctx, indexerState.addr);

        // Payer submits offer to get a valid agreement in the collector
        vm.prank(rca.payer);
        bytes16 agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        bytes32 versionHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;

        // Call acceptAgreement directly on SS, pranking as the collector,
        // to isolate the data-service callback gas.
        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        subgraphService.acceptAgreement(
            agreementId,
            versionHash,
            rca.payer,
            indexerState.addr,
            rca.metadata,
            abi.encode(indexerState.allocationId)
        );
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "acceptAgreement (initial) exceeds half of callback gas budget");
    }

    /// @notice Update accept (onAcceptCallback update path): validates terms and updates storage.
    /// Lighter than initial accept but still exercises storage writes.
    function test_AcceptAgreement_GasWithinBudget_UpdateAccept(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);

        // Create and accept initial agreement through the normal flow
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Submit an update offer
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);
        vm.prank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;

        // Build update metadata matching what the collector would pass
        IndexingAgreement.UpdateIndexingAgreementMetadata memory updateMeta = IndexingAgreement
            .UpdateIndexingAgreementMetadata({
                version: IIndexingAgreement.IndexingAgreementVersion.V1,
                terms: abi.encode(
                    IndexingAgreement.IndexingAgreementTermsV1({ tokensPerSecond: 0, tokensPerEntityPerSecond: 0 })
                )
            });

        // Call acceptAgreement directly on SS for the update path
        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        subgraphService.acceptAgreement(
            agreementId,
            pendingHash,
            rca.payer,
            indexerState.addr,
            abi.encode(updateMeta),
            bytes("")
        );
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "acceptAgreement (update) exceeds half of callback gas budget");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
