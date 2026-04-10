// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementCancelTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_SubgraphService_CancelByPayer_OK(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 acceptedAgreementId
        ) = _withAcceptedIndexingAgreement(ctx, _withIndexer(ctx));

        _cancelAgreement(ctx, acceptedAgreementId, acceptedRca.serviceProvider, acceptedRca.payer, false);
    }

    function test_SubgraphService_CancelByProvider_OK(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 acceptedAgreementId
        ) = _withAcceptedIndexingAgreement(ctx, _withIndexer(ctx));

        _cancelAgreement(ctx, acceptedAgreementId, acceptedRca.serviceProvider, acceptedRca.payer, true);
    }

    // solhint-disable-next-line graph/func-name-mixedcase
    /// @notice An indexer whose provision drops below minimum should still be able
    /// to cancel their indexing agreement. Cancel is an exit path.
    function test_SubgraphService_CancelIndexingAgreement_OK_WhenProvisionBelowMinimum(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 acceptedAgreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Thaw tokens to bring effective provision below minimum.
        // _withIndexer provisions at least MINIMUM_PROVISION_TOKENS, so thawing
        // (tokens - MINIMUM_PROVISION_TOKENS + 1) puts us 1 below the floor.
        uint256 thawAmount = indexerState.tokens - MINIMUM_PROVISION_TOKENS + 1;
        resetPrank(indexerState.addr);
        staking.thaw(indexerState.addr, address(subgraphService), thawAmount);

        // Verify provision is now below minimum
        uint256 effectiveTokens = indexerState.tokens - thawAmount;
        assertLt(effectiveTokens, MINIMUM_PROVISION_TOKENS);

        // Cancel should succeed despite invalid provision
        _cancelAgreement(ctx, acceptedAgreementId, acceptedRca.serviceProvider, acceptedRca.payer, true);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
