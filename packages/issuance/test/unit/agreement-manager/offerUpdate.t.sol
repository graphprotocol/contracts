// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

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

        // pendingMaxNextClaim = 2e18 * 7200 + 200e18 = 14600e18
        uint256 expectedPendingMaxClaim = 2 ether * 7200 + 200 ether;
        // Original maxNextClaim = 1e18 * 3600 + 100e18 = 3700e18
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        // Required escrow should include both
        assertEq(
            agreementManager.getSumMaxNextClaim(_collector(), indexer),
            originalMaxClaim + expectedPendingMaxClaim
        );
        // Original maxNextClaim unchanged
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), originalMaxClaim);
    }

    function test_OfferUpdate_AuthorizesHash() public {
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

        // The update hash should be authorized for the IAgreementOwner callback
        bytes32 updateHash = recurringCollector.hashRCAU(rcau);
        bytes4 result = agreementManager.approveAgreement(updateHash);
        assertEq(result, agreementManager.approveAgreement.selector);
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
        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;
        uint256 sumMaxNextClaim = originalMaxClaim + pendingMaxClaim;

        // Fund and offer agreement
        token.mint(address(agreementManager), sumMaxNextClaim);
        vm.prank(operator);
        bytes16 agreementId = agreementManager.offerAgreement(rca, _collector());

        // Offer update (should fund the deficit)
        token.mint(address(agreementManager), pendingMaxClaim);
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
        agreementManager.offerAgreementUpdate(rcau);

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

        // First pending update
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

        uint256 pendingMaxClaim1 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim + pendingMaxClaim1);

        // Second pending update (replaces first — same nonce since first was never accepted)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 180 days),
            1
        );
        _offerAgreementUpdate(rcau2);

        uint256 pendingMaxClaim2 = 0.5 ether * 1800 + 50 ether;
        // Old pending removed, new pending added
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim + pendingMaxClaim2);
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

        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementUpdateOffered(agreementId, pendingMaxClaim, 1);

        vm.prank(operator);
        agreementManager.offerAgreementUpdate(rcau);
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

        vm.expectRevert(abi.encodeWithSelector(IRecurringAgreementManagement.AgreementNotOffered.selector, fakeId));
        vm.prank(operator);
        agreementManager.offerAgreementUpdate(rcau);
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
        agreementManager.offerAgreementUpdate(rcau);
    }

    function test_OfferUpdate_Revert_WhenPaused() public {
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

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(operator);
        agreementManager.offerAgreementUpdate(rcau);
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

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringAgreementManagement.InvalidUpdateNonce.selector, agreementId, 1, 2)
        );
        vm.prank(operator);
        agreementManager.offerAgreementUpdate(rcau);
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
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: uint64(block.timestamp),
                lastCollectionAt: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 7200,
                updateNonce: 1,
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );

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

        // Verify pending state was set
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2Check = rcau2;
        bytes32 updateHash = recurringCollector.hashRCAU(rcau2Check);
        assertEq(agreementManager.approveAgreement(updateHash), agreementManager.approveAgreement.selector);
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
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: uint64(block.timestamp),
                lastCollectionAt: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 7200,
                updateNonce: 1,
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );

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

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringAgreementManagement.InvalidUpdateNonce.selector, agreementId, 2, 1)
        );
        vm.prank(operator);
        agreementManager.offerAgreementUpdate(rcau2);
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

    /* solhint-enable graph/func-name-mixedcase */
}
