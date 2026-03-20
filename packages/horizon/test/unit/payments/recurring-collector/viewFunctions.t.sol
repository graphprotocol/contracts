// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

/// @notice Tests for view functions: getCollectionInfo, computeMaxFirstClaim, computeMaxUpdateClaim.
contract RecurringCollectorViewFunctionsTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== getCollectionInfo ====================

    function test_GetCollectionInfo_Accepted(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Advance past minSecondsPerCollection so it's collectable
        skip(rca.minSecondsPerCollection);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        (
            bool isCollectable,
            uint256 collectionSeconds,
            IRecurringCollector.AgreementNotCollectableReason reason
        ) = _recurringCollector.getCollectionInfo(agreement);

        assertTrue(isCollectable, "Accepted agreement should be collectable");
        assertEq(uint256(reason), uint256(IRecurringCollector.AgreementNotCollectableReason.None));
        assertTrue(collectionSeconds > 0, "Collection seconds should be > 0");
    }

    function test_GetCollectionInfo_CanceledBySP(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        (bool isCollectable, , IRecurringCollector.AgreementNotCollectableReason reason) = _recurringCollector
            .getCollectionInfo(agreement);

        assertFalse(isCollectable, "CanceledBySP should not be collectable");
        assertEq(uint256(reason), uint256(IRecurringCollector.AgreementNotCollectableReason.InvalidAgreementState));
    }

    function test_GetCollectionInfo_NotAccepted() public view {
        // Fabricate a NotAccepted agreement
        IRecurringCollector.AgreementData memory agreement;
        agreement.state = IRecurringCollector.AgreementState.NotAccepted;

        (bool isCollectable, , IRecurringCollector.AgreementNotCollectableReason reason) = _recurringCollector
            .getCollectionInfo(agreement);

        assertFalse(isCollectable);
        assertEq(uint256(reason), uint256(IRecurringCollector.AgreementNotCollectableReason.InvalidAgreementState));
    }

    function test_GetCollectionInfo_CanceledByPayer_SameBlock(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Cancel in same block -> collectionEnd == collectionStart
        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        (bool isCollectable, , IRecurringCollector.AgreementNotCollectableReason reason) = _recurringCollector
            .getCollectionInfo(agreement);

        assertFalse(isCollectable, "Same-block cancel should not be collectable");
        assertEq(uint256(reason), uint256(IRecurringCollector.AgreementNotCollectableReason.ZeroCollectionSeconds));
    }

    function test_GetCollectionInfo_CanceledByPayer_WithWindow(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        skip(rca.minSecondsPerCollection + 100);
        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        (
            bool isCollectable,
            uint256 collectionSeconds,
            IRecurringCollector.AgreementNotCollectableReason reason
        ) = _recurringCollector.getCollectionInfo(agreement);

        assertTrue(isCollectable, "CanceledByPayer with elapsed time should be collectable");
        assertEq(uint256(reason), uint256(IRecurringCollector.AgreementNotCollectableReason.None));
        assertTrue(collectionSeconds > 0);
    }

    function test_GetCollectionInfo_CollectionEndBeforeStart() public {
        // Fabricate an agreement where collectionEnd < collectionStart
        // This can happen if lastCollectionAt is after endsAt
        vm.warp(10_000); // ensure enough room for arithmetic
        IRecurringCollector.AgreementData memory agreement;
        agreement.state = IRecurringCollector.AgreementState.Accepted;
        agreement.acceptedAt = uint64(block.timestamp - 2000);
        agreement.lastCollectionAt = uint64(block.timestamp);
        agreement.endsAt = uint64(block.timestamp - 500); // ends before lastCollectionAt
        agreement.maxSecondsPerCollection = 3600;

        (bool isCollectable, , IRecurringCollector.AgreementNotCollectableReason reason) = _recurringCollector
            .getCollectionInfo(agreement);

        assertFalse(isCollectable, "Should not be collectable when end < start");
        assertEq(uint256(reason), uint256(IRecurringCollector.AgreementNotCollectableReason.InvalidTemporalWindow));
    }

    // ==================== computeMaxFirstClaim ====================

    function test_ComputeMaxFirstClaim() public view {
        IRecurringCollector.RecurringCollectionAgreement memory rca;
        rca.maxOngoingTokensPerSecond = 1 ether;
        rca.maxSecondsPerCollection = 3600;
        rca.maxInitialTokens = 100 ether;
        rca.endsAt = uint64(block.timestamp + 100_000); // remaining > maxSecondsPerCollection

        uint256 maxTokens = _recurringCollector.computeMaxFirstClaim(rca);
        // effectiveSeconds = min(100_000, 3600) = 3600
        assertEq(maxTokens, 1 ether * 3600 + 100 ether);
    }

    function test_ComputeMaxFirstClaim_PastEndsAt() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca;
        rca.maxOngoingTokensPerSecond = 1 ether;
        rca.maxSecondsPerCollection = 3600;
        rca.maxInitialTokens = 100 ether;
        rca.endsAt = uint64(block.timestamp + 1000); // remaining < maxSecondsPerCollection

        // Warp past endsAt
        vm.warp(rca.endsAt + 1);

        uint256 maxTokens = _recurringCollector.computeMaxFirstClaim(rca);
        // remainingSeconds = 0 (block.timestamp > endsAt), so only initialTokens
        assertEq(maxTokens, 100 ether);
    }

    function test_ComputeMaxFirstClaim_RemainingLessThanMaxSeconds() public view {
        IRecurringCollector.RecurringCollectionAgreement memory rca;
        rca.maxOngoingTokensPerSecond = 1 ether;
        rca.maxSecondsPerCollection = 100_000;
        rca.maxInitialTokens = 50 ether;
        rca.endsAt = uint64(block.timestamp + 3600); // remaining (3600) < maxSecondsPerCollection (100_000)

        uint256 maxTokens = _recurringCollector.computeMaxFirstClaim(rca);
        // effectiveSeconds = min(3600, 100_000) = 3600
        assertEq(maxTokens, 1 ether * 3600 + 50 ether);
    }

    // ==================== computeMaxUpdateClaim ====================

    function test_ComputeMaxUpdateClaim_NeverCollected(FuzzyTestAccept calldata fuzzy) public {
        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzy);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau;
        rcau.maxOngoingTokensPerSecond = 2 ether;
        rcau.maxSecondsPerCollection = 7200;
        rcau.maxInitialTokens = 200 ether;
        rcau.endsAt = uint64(block.timestamp + 500_000);

        (uint256 initialExtra, uint256 ongoing) = _recurringCollector.computeMaxUpdateClaim(agreementId, rcau);

        // Never collected -> initialExtra = maxInitialTokens
        assertEq(initialExtra, 200 ether, "Should include initial tokens when never collected");
        // ongoing = rate * min(remaining, maxSecondsPerCollection)
        uint256 remaining = rcau.endsAt - block.timestamp;
        uint256 effectiveSeconds = remaining < rcau.maxSecondsPerCollection ? remaining : rcau.maxSecondsPerCollection;
        assertEq(ongoing, 2 ether * effectiveSeconds);
    }

    function test_ComputeMaxUpdateClaim_AfterCollection(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Collect once to set lastCollectionAt
        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, keccak256("col"), 1, 0));
        vm.prank(rca.dataService);
        _recurringCollector.collect(_paymentType(0), data);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau;
        rcau.maxOngoingTokensPerSecond = 2 ether;
        rcau.maxSecondsPerCollection = 7200;
        rcau.maxInitialTokens = 200 ether;
        rcau.endsAt = uint64(block.timestamp + 500_000);

        (uint256 initialExtra, uint256 ongoing) = _recurringCollector.computeMaxUpdateClaim(agreementId, rcau);

        // Already collected -> initialExtra = 0
        assertEq(initialExtra, 0, "Should not include initial tokens after collection");
        assertTrue(ongoing > 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
