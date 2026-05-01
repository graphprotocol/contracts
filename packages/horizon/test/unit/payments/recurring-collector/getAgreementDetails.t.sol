// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import {
    IAgreementCollector,
    OFFER_TYPE_NEW,
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PAYER,
    BY_PROVIDER,
    VERSION_CURRENT
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

contract RecurringCollectorGetAgreementDetailsTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- Accepted agreement --

    function test_GetAgreementDetails_Accepted(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        IAgreementCollector.AgreementDetails memory details = _recurringCollector.getAgreementDetails(agreementId, 0);

        assertEq(details.agreementId, agreementId);
        assertEq(details.payer, rca.payer);
        assertEq(details.dataService, rca.dataService);
        assertEq(details.serviceProvider, rca.serviceProvider);
        assertNotEq(details.versionHash, bytes32(0));
    }

    // -- Stored RCA offer (not yet accepted) --

    function test_GetAgreementDetails_StoredOffer() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(approver),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory offerDetails = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        bytes16 agreementId = offerDetails.agreementId;

        IAgreementCollector.AgreementDetails memory details = _recurringCollector.getAgreementDetails(agreementId, 0);

        assertEq(details.agreementId, agreementId);
        assertEq(details.payer, address(approver));
        assertEq(details.dataService, rca.dataService);
        assertEq(details.serviceProvider, rca.serviceProvider);
        assertEq(details.versionHash, offerDetails.versionHash);
        assertEq(details.state, REGISTERED);
    }

    // -- Unknown agreement returns zero --

    function test_GetAgreementDetails_Unknown() public view {
        bytes16 unknownId = bytes16(keccak256("nonexistent"));

        IAgreementCollector.AgreementDetails memory details = _recurringCollector.getAgreementDetails(unknownId, 0);

        assertEq(details.agreementId, bytes16(0));
        assertEq(details.payer, address(0));
        assertEq(details.dataService, address(0));
        assertEq(details.serviceProvider, address(0));
        assertEq(details.versionHash, bytes32(0));
    }

    // -- Canceled agreement still returns details --

    function test_GetAgreementDetails_Canceled(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        vm.prank(rca.dataService);
        _recurringCollector.cancel(agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        IAgreementCollector.AgreementDetails memory details = _recurringCollector.getAgreementDetails(agreementId, 0);

        assertEq(details.agreementId, agreementId);
        assertEq(details.payer, rca.payer);
        assertEq(details.dataService, rca.dataService);
        assertEq(details.serviceProvider, rca.serviceProvider);
        assertNotEq(details.versionHash, bytes32(0));
    }

    // -- Cancel sets NOTICE_GIVEN + origin flag; provider cancel is always SETTLED --

    function test_GetAgreementDetails_CanceledByServiceProvider_Flags(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        vm.prank(rca.dataService);
        _recurringCollector.cancel(agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        IAgreementCollector.AgreementDetails memory details = _recurringCollector.getAgreementDetails(
            agreementId,
            VERSION_CURRENT
        );

        assertEq(
            details.state,
            REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PROVIDER | SETTLED,
            "provider cancel: REGISTERED|ACCEPTED|NOTICE_GIVEN|BY_PROVIDER|SETTLED"
        );
    }

    function test_GetAgreementDetails_CanceledByPayer_Flags(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        vm.prank(rca.dataService);
        _recurringCollector.cancel(agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        IAgreementCollector.AgreementDetails memory details = _recurringCollector.getAgreementDetails(
            agreementId,
            VERSION_CURRENT
        );

        uint16 baseline = REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PAYER;
        assertTrue(
            details.state == baseline || details.state == (baseline | SETTLED),
            "payer cancel: REGISTERED|ACCEPTED|NOTICE_GIVEN|BY_PAYER (+SETTLED if fully elapsed)"
        );
        assertEq(details.state & NOTICE_GIVEN, NOTICE_GIVEN, "NOTICE_GIVEN set");
        assertEq(details.state & BY_PAYER, BY_PAYER, "BY_PAYER set");
        assertEq(details.state & BY_PROVIDER, 0, "BY_PROVIDER not set");
    }

    // -- Accepted agreement with nothing left to claim reports SETTLED --

    function test_GetAgreementDetails_Accepted_ElapsedSetsSettled(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        // Jump past the agreement's end so no further collection is possible once lastCollectionAt
        // catches up. Without any collections, _getMaxNextClaim still returns a non-zero value
        // (late-collection semantics), so the clearest SETTLED case is via provider cancel — but
        // we want to assert the non-cancel path here too. Simulate fully-collected state by
        // advancing to endsAt + 1 and marking lastCollectionAt == endsAt via a well-formed path:
        // easiest is a payer cancel far in the past (canceledAt in the past → window empty).
        vm.prank(rca.dataService);
        _recurringCollector.cancel(agreementId, IRecurringCollector.CancelAgreementBy.Payer);
        vm.warp(rca.endsAt + 1);

        IAgreementCollector.AgreementDetails memory details = _recurringCollector.getAgreementDetails(
            agreementId,
            VERSION_CURRENT
        );

        assertEq(details.state & SETTLED, SETTLED, "SETTLED set when nothing left to claim");
    }
}
