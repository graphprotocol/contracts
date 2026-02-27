// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorGetMaxNextClaimTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_GetMaxNextClaim_NotAccepted() public view {
        bytes16 fakeId = bytes16(keccak256("nonexistent"));
        assertEq(_recurringCollector.getMaxNextClaim(fakeId), 0);
    }

    function test_GetMaxNextClaim_Accepted_NeverCollected(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // Never collected: includes maxInitialTokens
        // Window = endsAt - acceptedAt, capped at maxSecondsPerCollection
        uint256 windowSeconds = rca.endsAt - block.timestamp;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds + rca.maxInitialTokens;
        assertEq(maxClaim, expected);
    }

    function test_GetMaxNextClaim_Accepted_AfterCollection(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Perform a first collection
        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, keccak256("col"), 1, 0));
        vm.prank(rca.dataService);
        _recurringCollector.collect(_paymentType(0), data);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // After collection: no initial tokens, window from lastCollectionAt
        uint256 windowSeconds = rca.endsAt - block.timestamp;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds;
        assertEq(maxClaim, expected);
    }

    function test_GetMaxNextClaim_CanceledByServiceProvider(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        assertEq(_recurringCollector.getMaxNextClaim(agreementId), 0);
    }

    function test_GetMaxNextClaim_CanceledByPayer(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // CanceledByPayer: window frozen at canceledAt
        // canceledAt == block.timestamp, acceptedAt == (block.timestamp - 0)
        // So window = canceledAt - acceptedAt = 0 (canceled in same block as accepted)
        // Since window is 0, maxClaim should be 0
        assertEq(maxClaim, 0);
    }

    function test_GetMaxNextClaim_CanceledByPayer_WithWindow(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Advance time, then cancel
        skip(rca.minSecondsPerCollection + 100);

        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // canceledAt = now, acceptedAt = now - (minSeconds + 100)
        // window = canceledAt - acceptedAt = minSeconds + 100, capped at maxSecondsPerCollection
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        uint256 windowSeconds = agreement.canceledAt - agreement.acceptedAt;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds + rca.maxInitialTokens;
        assertEq(maxClaim, expected);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
