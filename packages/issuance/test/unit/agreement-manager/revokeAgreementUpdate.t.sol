// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementManagerRevokeAgreementUpdateTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_RevokeAgreementUpdate_ClearsPendingState() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        // Offer a pending update
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

        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim + pendingMaxClaim);

        // Revoke the pending update
        vm.prank(operator);
        bool revoked = agreementManager.revokeAgreementUpdate(agreementId);
        assertTrue(revoked);

        // Pending state should be fully cleared
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(agreementId);
        assertEq(info.pendingUpdateMaxNextClaim, 0, "pending escrow should be zero");
        assertEq(info.pendingUpdateNonce, 0, "pending nonce should be zero");
        assertEq(info.pendingUpdateHash, bytes32(0), "pending hash should be zero");

        // sumMaxNextClaim should only include the base claim
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim);

        // The update hash should no longer be authorized
        bytes32 updateHash = recurringCollector.hashRCAU(rcau);
        bytes4 result = agreementManager.approveAgreement(updateHash);
        assertTrue(result != agreementManager.approveAgreement.selector, "hash should not be authorized");
    }

    function test_RevokeAgreementUpdate_EmitsEvent() public {
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

        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementUpdateRevoked(agreementId, pendingMaxClaim, 1);

        vm.prank(operator);
        agreementManager.revokeAgreementUpdate(agreementId);
    }

    function test_RevokeAgreementUpdate_ReturnsFalse_WhenNoPending() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // No pending update — should return false
        vm.prank(operator);
        bool revoked = agreementManager.revokeAgreementUpdate(agreementId);
        assertFalse(revoked);
    }

    function test_RevokeAgreementUpdate_ReturnsFalse_WhenAlreadyApplied() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Offer update
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

        // Simulate: accepted with update already applied (updateNonce=1)
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: uint64(block.timestamp),
                lastCollectionAt: 0,
                endsAt: rcau.endsAt,
                maxInitialTokens: rcau.maxInitialTokens,
                maxOngoingTokensPerSecond: rcau.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rcau.minSecondsPerCollection,
                maxSecondsPerCollection: rcau.maxSecondsPerCollection,
                updateNonce: 1,
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );

        // Reconcile inside revokeAgreementUpdate detects the update was applied
        // and clears it — returns false (nothing left to revoke)
        vm.prank(operator);
        bool revoked = agreementManager.revokeAgreementUpdate(agreementId);
        assertFalse(revoked);
    }

    function test_RevokeAgreementUpdate_CanOfferNewUpdateAfterRevoke() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Offer update nonce=1
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

        // Revoke it
        vm.prank(operator);
        agreementManager.revokeAgreementUpdate(agreementId);

        // Offer a new update with the same nonce (1) — should succeed since the
        // collector's updateNonce is still 0 and the pending was cleared
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

        // New pending should be set
        uint256 newPendingMaxClaim = 0.5 ether * 1800 + 50 ether;
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(agreementId);
        assertEq(info.pendingUpdateMaxNextClaim, newPendingMaxClaim);
        assertEq(info.pendingUpdateNonce, 1);
    }

    function test_RevokeAgreementUpdate_Revert_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));

        vm.expectRevert(abi.encodeWithSelector(IRecurringAgreementManagement.AgreementNotOffered.selector, fakeId));
        vm.prank(operator);
        agreementManager.revokeAgreementUpdate(fakeId);
    }

    function test_RevokeAgreementUpdate_Revert_WhenNotOperator() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        address nonOperator = makeAddr("nonOperator");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonOperator,
                AGREEMENT_MANAGER_ROLE
            )
        );
        vm.prank(nonOperator);
        agreementManager.revokeAgreementUpdate(agreementId);
    }

    function test_RevokeAgreementUpdate_Revert_WhenPaused() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        _offerAgreement(rca);
        bytes16 agreementId = recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        vm.startPrank(governor);
        agreementManager.grantRole(keccak256("PAUSE_ROLE"), governor);
        agreementManager.pause();
        vm.stopPrank();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(operator);
        agreementManager.revokeAgreementUpdate(agreementId);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
