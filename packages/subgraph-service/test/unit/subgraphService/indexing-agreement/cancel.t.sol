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

    /* solhint-enable graph/func-name-mixedcase */
}
