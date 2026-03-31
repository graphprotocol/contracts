// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

/// @notice Tests for getCollectionInfo and getAgreement view functions across agreement states.
contract RecurringCollectorViewFunctionsTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== getCollectionInfo: Accepted ====================

    function test_GetCollectionInfo_Accepted_AfterTime(FuzzyTestAccept calldata fuzzy) public {
        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzy);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);

        // Skip some time
        skip(agreement.minSecondsPerCollection);

        // Re-read agreement (timestamps don't change but view computes based on block.timestamp)
        (bool isCollectable, uint256 collectionSeconds, ) = _recurringCollector.getCollectionInfo(agreementId);

        assertTrue(isCollectable, "Should be collectable after min time");
        assertTrue(collectionSeconds > 0, "Should have collectable seconds");
    }

    // ==================== getCollectionInfo: CanceledByServiceProvider ====================

    function test_GetCollectionInfo_CanceledBySP(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Cancel by service provider
        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);

        (bool isCollectable, , IRecurringCollector.AgreementNotCollectableReason reason) = _recurringCollector
            .getCollectionInfo(agreementId);

        assertFalse(isCollectable, "CanceledByServiceProvider should not be collectable");
        assertEq(
            uint8(reason),
            uint8(IRecurringCollector.AgreementNotCollectableReason.InvalidAgreementState),
            "Reason should be InvalidAgreementState"
        );
    }

    // ==================== getCollectionInfo: NotAccepted ====================

    function test_GetCollectionInfo_NotAccepted() public view {
        // Non-existent agreement has state NotAccepted
        bytes16 nonExistentId = bytes16(uint128(999));

        (bool isCollectable, , IRecurringCollector.AgreementNotCollectableReason reason) = _recurringCollector
            .getCollectionInfo(nonExistentId);

        assertFalse(isCollectable, "NotAccepted should not be collectable");
        assertEq(
            uint8(reason),
            uint8(IRecurringCollector.AgreementNotCollectableReason.InvalidAgreementState),
            "Reason should be InvalidAgreementState"
        );
    }

    // ==================== getCollectionInfo: CanceledByPayer same block ====================

    function test_GetCollectionInfo_CanceledByPayer_SameBlock(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Cancel by payer in the same block as accept
        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);

        (bool isCollectable, uint256 collectionSeconds, ) = _recurringCollector.getCollectionInfo(agreementId);

        // Same block cancel means no time elapsed
        assertFalse(isCollectable, "Same-block payer cancel should not be collectable");
        assertEq(collectionSeconds, 0, "Should have 0 collection seconds");
    }

    // ==================== getCollectionInfo: CanceledByPayer with window ====================

    function test_GetCollectionInfo_CanceledByPayer_WithWindow(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Skip time then cancel by payer
        skip(rca.minSecondsPerCollection);
        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);

        (bool isCollectable, uint256 collectionSeconds, ) = _recurringCollector.getCollectionInfo(agreementId);

        assertTrue(isCollectable, "Payer cancel with elapsed time should be collectable");
        assertTrue(collectionSeconds > 0, "Should have collectable seconds");
    }

    // ==================== getAgreement: basic field checks ====================

    function test_GetAgreement_FieldsMatch(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);

        assertEq(agreement.payer, rca.payer, "payer should match");
        assertEq(agreement.dataService, rca.dataService, "dataService should match");
        assertEq(agreement.serviceProvider, rca.serviceProvider, "serviceProvider should match");
        assertEq(agreement.endsAt, rca.endsAt, "endsAt should match");
        assertEq(agreement.minSecondsPerCollection, rca.minSecondsPerCollection, "minSeconds should match");
        assertEq(agreement.maxSecondsPerCollection, rca.maxSecondsPerCollection, "maxSeconds should match");
        assertEq(agreement.maxInitialTokens, rca.maxInitialTokens, "maxInitialTokens should match");
        assertEq(
            agreement.maxOngoingTokensPerSecond,
            rca.maxOngoingTokensPerSecond,
            "maxOngoingTokensPerSecond should match"
        );
        assertEq(
            uint8(agreement.state),
            uint8(IRecurringCollector.AgreementState.Accepted),
            "state should be Accepted"
        );
        assertTrue(agreement.acceptedAt > 0, "acceptedAt should be set");
        assertTrue(agreement.activeTermsHash != bytes32(0), "activeTermsHash should be set");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
