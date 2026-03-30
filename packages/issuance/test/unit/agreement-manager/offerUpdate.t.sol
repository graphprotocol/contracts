// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import {
    REGISTERED,
    ACCEPTED,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

contract RecurringAgreementManagerOfferUpdateTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_OfferUpdate_SetsState() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );

        _offerAgreementUpdate(rcau);

        // Original maxNextClaim = 1e18 * 3600 + 100e18 = 3700e18
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;
        // Pending = ongoing + initialExtra = 2e18 * 7200 + 200e18 = 14600e18
        uint256 pendingTotal = 2 ether * 7200 + 200 ether;

        // Contribution = max(pending, current) since only one set of terms is active at a time
        assertEq(
            agreementManager.getSumMaxNextClaim(_collector(), indexer),
            pendingTotal // max(3700, 14600) = 14600
        );
        // maxNextClaim now stores max(active, pending)
        assertEq(agreementManager.getAgreementMaxNextClaim(address(recurringCollector), agreementId), pendingTotal);
    }

    function test_OfferUpdate_StoresOnCollector() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );

        _offerAgreementUpdate(rcau);

        // The update is stored on the collector (not via hash authorization)
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        assertTrue(pendingHash != bytes32(0), "Pending update should be stored");
    }

    function test_OfferUpdate_FundsEscrow() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;
        // Pending = ongoing + initialExtra = 2e18 * 7200 + 200e18 = 14600e18
        uint256 pendingTotal = 2 ether * 7200 + 200 ether;
        // Contribution = max(pendingTotal, originalMaxClaim) = 14600 (only one agreement)
        uint256 sumMaxNextClaim = pendingTotal;

        // Fund generously so Full mode stays active through both offers.
        // After both offers, smnca = sumMaxNextClaim, deficit = sumMaxNextClaim.
        // spare = balance - deficit. Full requires smnca * 272 / 256 < spare.
        token.mint(address(agreementManager), sumMaxNextClaim + (sumMaxNextClaim * 272) / 256 + 1);
        vm.prank(operator);
        bytes16 agreementId = agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));

        // Offer update (should fund the deficit)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        vm.prank(operator);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_UPDATE, abi.encode(rcau));

        // Verify escrow was funded for both
        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowBalance, sumMaxNextClaim);
    }

    function test_OfferUpdate_ReplacesExistingPending() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        // First pending update (nonce=1)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau1);

        // Pending1 = ongoing + initialExtra = 2e18 * 7200 + 200e18 = 14600e18
        // Contribution = max(14600, 3700) = 14600
        uint256 pendingTotal1 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), pendingTotal1);

        // Revoke first, then offer second (nonce=2, since collector incremented to 1)
        _cancelPendingUpdate(agreementId);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 180 days),
            2
        );
        _offerAgreementUpdate(rcau2);

        // Pending2 = ongoing + initialExtra = 0.5e18 * 1800 + 50e18 = 950e18
        // Contribution = max(950, 3700) = 3700 (original dominates)
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim);
    }

    function test_OfferUpdate_EmitsEvent() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );

        // Pending maxNextClaim = ongoing + initialExtra = 2e18 * 7200 + 200e18 = 14600e18
        uint256 pendingTotal = 2 ether * 7200 + 200 ether;
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        // The callback fires during offer, emitting AgreementReconciled
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementReconciled(agreementId, originalMaxClaim, pendingTotal);

        vm.prank(operator);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_UPDATE, abi.encode(rcau));
    }

    function test_OfferUpdate_Revert_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            fakeId,
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days),
            1
        );

        vm.expectRevert(abi.encodeWithSelector(IRecurringAgreementManagement.ServiceProviderZeroAddress.selector));
        vm.prank(operator);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_UPDATE, abi.encode(rcau));
    }

    function test_OfferUpdate_Revert_WhenNotOperator() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );

        address nonOperator = makeAddr("nonOperator");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonOperator,
                AGREEMENT_MANAGER_ROLE
            )
        );
        vm.prank(nonOperator);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_UPDATE, abi.encode(rcau));
    }

    function test_OfferUpdate_Revert_WhenNonceWrong() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Try nonce=2 when collector expects nonce=1 (updateNonce=0)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            2
        );

        // Nonce validation is now done by the collector
        vm.expectRevert("MockRecurringCollector: invalid nonce");
        vm.prank(operator);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_UPDATE, abi.encode(rcau));
    }

    function test_OfferUpdate_Nonce2_AfterFirstAccepted() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Offer first update (nonce=1)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau1);

        // Simulate: agreement accepted with update nonce=1 applied
        IRecurringCollector.RecurringCollectionAgreement memory updatedRca = _makeRCA(
            200 ether, 2 ether, 60, 7200, uint64(block.timestamp + 730 days)
        );
        updatedRca.payer = rca.payer;
        updatedRca.dataService = rca.dataService;
        updatedRca.serviceProvider = rca.serviceProvider;
        MockRecurringCollector.AgreementStorage memory data = _buildAgreementStorage(
            updatedRca, REGISTERED | ACCEPTED, uint64(block.timestamp), 0, 0
        );
        data.updateNonce = 1;
        recurringCollector.setAgreement(agreementId, data);

        // Offer second update (nonce=2) — should succeed because collector's updateNonce=1
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            300 ether,
            3 ether,
            60,
            3600,
            uint64(block.timestamp + 1095 days),
            2
        );
        _offerAgreementUpdate(rcau2);

        // Verify pending state was set on the collector
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        assertTrue(pendingHash != bytes32(0), "Second pending update should be stored");
        IRecurringCollector.AgreementData memory result = recurringCollector.getAgreementData(agreementId);
        assertEq(result.updateNonce, 2);
    }

    function test_OfferUpdate_Revert_Nonce1_AfterFirstAccepted() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Offer first update (nonce=1)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau1);

        // Simulate: agreement accepted with update nonce=1 applied
        IRecurringCollector.RecurringCollectionAgreement memory updatedRca = _makeRCA(
            200 ether, 2 ether, 60, 7200, uint64(block.timestamp + 730 days)
        );
        updatedRca.payer = rca.payer;
        updatedRca.dataService = rca.dataService;
        updatedRca.serviceProvider = rca.serviceProvider;
        MockRecurringCollector.AgreementStorage memory data = _buildAgreementStorage(
            updatedRca, REGISTERED | ACCEPTED, uint64(block.timestamp), 0, 0
        );
        data.updateNonce = 1;
        recurringCollector.setAgreement(agreementId, data);

        // Try nonce=1 again — should fail because collector already at updateNonce=1
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            300 ether,
            3 ether,
            60,
            3600,
            uint64(block.timestamp + 1095 days),
            1
        );

        // Nonce validation is now done by the collector
        vm.expectRevert("MockRecurringCollector: invalid nonce");
        vm.prank(operator);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_UPDATE, abi.encode(rcau2));
    }

    function test_OfferUpdate_ReconcilesDuringOffer() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 preOfferMax = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        // Simulate acceptance with a collection (maxNextClaim should change)
        uint64 acceptedAt = uint64(block.timestamp);
        uint64 collectionAt = uint64(block.timestamp + 1800);
        vm.warp(collectionAt);
        _setAgreementCollected(agreementId, rca, acceptedAt, collectionAt);

        // Offer an update — this should reconcile first, updating maxNextClaim
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 365 days),
            1
        );
        _offerAgreementUpdate(rcau);

        // The base maxNextClaim should have been reconciled (reduced from pre-offer estimate)
        // and the pending update added on top
        uint256 pendingMaxClaim = 0.5 ether * 1800 + 50 ether;
        uint256 postOfferMax = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        // Post-reconcile base should be less than the pre-offer estimate
        // (collection happened, so remaining window is smaller)
        assertTrue(postOfferMax < preOfferMax + pendingMaxClaim);
    }

    function test_OfferUpdate_Succeeds_WhenPaused() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );

        // Grant pause role and pause
        vm.startPrank(governor);
        agreementManager.grantRole(keccak256("PAUSE_ROLE"), governor);
        agreementManager.pause();
        vm.stopPrank();

        // Role-gated functions should succeed even when paused
        vm.prank(operator);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_UPDATE, abi.encode(rcau));
    }

    /* solhint-enable graph/func-name-mixedcase */
}
