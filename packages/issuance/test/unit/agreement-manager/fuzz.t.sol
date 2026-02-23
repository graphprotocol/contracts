// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IIndexingAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIndexingAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { IndexingAgreementManagerSharedTest } from "./shared.t.sol";

contract IndexingAgreementManagerFuzzTest is IndexingAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- offerAgreement --

    function testFuzz_Offer_MaxNextClaimCalculation(
        uint128 maxInitialTokens,
        uint128 maxOngoingTokensPerSecond,
        uint32 maxSecondsPerCollection
    ) public {
        // Bound to avoid overflow: uint128 * uint32 fits in uint256
        vm.assume(0 < maxSecondsPerCollection);

        uint64 endsAt = uint64(block.timestamp + 365 days);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            maxInitialTokens,
            maxOngoingTokensPerSecond,
            60,
            maxSecondsPerCollection,
            endsAt
        );

        bytes16 agreementId = _offerAgreement(rca);

        uint256 expectedMaxClaim = uint256(maxOngoingTokensPerSecond) * uint256(maxSecondsPerCollection) +
            uint256(maxInitialTokens);
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), expectedMaxClaim);
        assertEq(agreementManager.getRequiredEscrow(indexer), expectedMaxClaim);
    }

    function testFuzz_Offer_EscrowFundedUpToAvailable(
        uint128 maxInitialTokens,
        uint128 maxOngoingTokensPerSecond,
        uint32 maxSecondsPerCollection,
        uint256 availableTokens
    ) public {
        vm.assume(0 < maxSecondsPerCollection);
        availableTokens = bound(availableTokens, 0, 10_000_000 ether);

        uint64 endsAt = uint64(block.timestamp + 365 days);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            maxInitialTokens,
            maxOngoingTokensPerSecond,
            60,
            maxSecondsPerCollection,
            endsAt
        );

        // Fund with a specific amount instead of the default 1M ether
        token.mint(address(agreementManager), availableTokens);
        vm.prank(operator);
        bytes16 agreementId = agreementManager.offerAgreement(rca);

        uint256 maxNextClaim = agreementManager.getAgreementMaxNextClaim(agreementId);
        uint256 escrowBalance = paymentsEscrow.getBalance(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Escrow should be min(maxNextClaim, availableTokens)
        if (availableTokens < maxNextClaim) {
            assertEq(escrowBalance, availableTokens);
        } else {
            assertEq(escrowBalance, maxNextClaim);
        }
    }

    function testFuzz_Offer_RequiredEscrowIncrements(
        uint64 maxInitial1,
        uint64 maxOngoing1,
        uint32 maxSec1,
        uint64 maxInitial2,
        uint64 maxOngoing2,
        uint32 maxSec2
    ) public {
        vm.assume(0 < maxSec1 && 0 < maxSec2);

        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            maxInitial1,
            maxOngoing1,
            60,
            maxSec1,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            maxInitial2,
            maxOngoing2,
            60,
            maxSec2,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        _offerAgreement(rca1);
        uint256 required1 = agreementManager.getRequiredEscrow(indexer);

        _offerAgreement(rca2);
        uint256 required2 = agreementManager.getRequiredEscrow(indexer);

        uint256 maxClaim1 = uint256(maxOngoing1) * uint256(maxSec1) + uint256(maxInitial1);
        uint256 maxClaim2 = uint256(maxOngoing2) * uint256(maxSec2) + uint256(maxInitial2);

        assertEq(required1, maxClaim1);
        assertEq(required2, maxClaim1 + maxClaim2);
    }

    // -- revokeOffer / removeAgreement --

    function testFuzz_RevokeOffer_RequiredEscrowDecrements(uint64 maxInitial, uint64 maxOngoing, uint32 maxSec) public {
        vm.assume(0 < maxSec);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            maxInitial,
            maxOngoing,
            60,
            maxSec,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 requiredBefore = agreementManager.getRequiredEscrow(indexer);
        assertTrue(0 < requiredBefore || (maxInitial == 0 && maxOngoing == 0));

        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);

        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
        assertEq(agreementManager.getIndexerAgreementCount(indexer), 0);
    }

    function testFuzz_Remove_AfterSPCancel_ClearsState(uint64 maxInitial, uint64 maxOngoing, uint32 maxSec) public {
        vm.assume(0 < maxSec);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            maxInitial,
            maxOngoing,
            60,
            maxSec,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementCanceledBySP(agreementId, rca);

        agreementManager.removeAgreement(agreementId);

        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
        assertEq(agreementManager.getIndexerAgreementCount(indexer), 0);
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 0);
    }

    // -- reconcile --

    function testFuzz_Reconcile_AfterCollection_UpdatesRequired(
        uint64 maxInitial,
        uint64 maxOngoing,
        uint32 maxSec,
        uint32 timeElapsed
    ) public {
        vm.assume(0 < maxSec);
        vm.assume(0 < maxOngoing);
        timeElapsed = uint32(bound(timeElapsed, 1, maxSec));

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            maxInitial,
            maxOngoing,
            60,
            maxSec,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 preAcceptRequired = agreementManager.getRequiredEscrow(indexer);

        // Simulate acceptance and a collection at block.timestamp + timeElapsed
        uint64 acceptedAt = uint64(block.timestamp);
        uint64 collectionAt = uint64(block.timestamp + timeElapsed);
        _setAgreementCollected(agreementId, rca, acceptedAt, collectionAt);

        // Warp to collection time
        vm.warp(collectionAt);

        agreementManager.reconcileAgreement(agreementId);

        uint256 postReconcileRequired = agreementManager.getRequiredEscrow(indexer);

        // After collection, the maxNextClaim should reflect remaining window (no initial tokens)
        // and should be <= the pre-acceptance estimate
        assertTrue(postReconcileRequired <= preAcceptRequired);
    }

    // -- offerAgreementUpdate --

    function testFuzz_OfferUpdate_DoubleFunding(
        uint64 maxInitial,
        uint64 maxOngoing,
        uint32 maxSec,
        uint64 updateMaxInitial,
        uint64 updateMaxOngoing,
        uint32 updateMaxSec
    ) public {
        vm.assume(0 < maxSec && 0 < updateMaxSec);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            maxInitial,
            maxOngoing,
            60,
            maxSec,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        uint256 originalMaxClaim = uint256(maxOngoing) * uint256(maxSec) + uint256(maxInitial);
        assertEq(agreementManager.getRequiredEscrow(indexer), originalMaxClaim);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            updateMaxInitial,
            updateMaxOngoing,
            60,
            updateMaxSec,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau);

        uint256 pendingMaxClaim = uint256(updateMaxOngoing) * uint256(updateMaxSec) + uint256(updateMaxInitial);

        // Both original and pending are funded simultaneously
        assertEq(agreementManager.getRequiredEscrow(indexer), originalMaxClaim + pendingMaxClaim);
    }

    // -- removeAgreement deadline --

    function testFuzz_Remove_ExpiredOffer_DeadlineBoundary(uint32 extraTime) public {
        extraTime = uint32(bound(extraTime, 1, 365 days));

        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Before deadline: should revert
        uint256 storedMaxClaim = agreementManager.getAgreementMaxNextClaim(agreementId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IIndexingAgreementManager.IndexingAgreementManagerAgreementStillClaimable.selector,
                agreementId,
                storedMaxClaim
            )
        );
        agreementManager.removeAgreement(agreementId);

        // Warp past deadline
        vm.warp(rca.deadline + extraTime);

        // After deadline: should succeed
        agreementManager.removeAgreement(agreementId);
        assertEq(agreementManager.getIndexerAgreementCount(indexer), 0);
    }

    // -- getDeficit --

    function testFuzz_GetDeficit_MatchesShortfall(uint128 maxOngoing, uint32 maxSec, uint128 available) public {
        vm.assume(0 < maxSec);
        vm.assume(0 < maxOngoing);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            0,
            maxOngoing,
            60,
            maxSec,
            uint64(block.timestamp + 365 days)
        );

        token.mint(address(agreementManager), available);
        vm.prank(operator);
        agreementManager.offerAgreement(rca);

        uint256 required = agreementManager.getRequiredEscrow(indexer);
        uint256 balance = paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer);
        uint256 deficit = agreementManager.getDeficit(indexer);

        if (balance < required) {
            assertEq(deficit, required - balance);
        } else {
            assertEq(deficit, 0);
        }
    }

    /* solhint-enable graph/func-name-mixedcase */
}
