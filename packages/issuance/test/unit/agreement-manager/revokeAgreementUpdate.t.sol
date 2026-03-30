// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import {
    IAgreementCollector,
    REGISTERED,
    ACCEPTED
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementManagerCancelPendingUpdateTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_CancelPendingUpdate_ClearsPendingState() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

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

        // max(current, pending) = max(3700, 14600) = 14600
        uint256 pendingMaxClaim = 14600 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), pendingMaxClaim);

        // Cancel pending update clears pending terms on the collector and reconciles
        _cancelPendingUpdate(agreementId);

        // sumMaxNextClaim drops to active-only (3700) since pending was cleared
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim);
    }

    function test_CancelPendingUpdate_EmitsEvent() public {
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

        // Read pending terms hash from the collector
        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        // Before cancel: maxNextClaim = max(active=3700, pending=14600) = 14600
        // After cancel: pending deleted, maxNextClaim = active-only = 3700
        uint256 oldMaxClaim = agreementManager
            .getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId)
            .maxNextClaim;
        uint256 activeOnlyClaim = 1 ether * 3600 + 100 ether;

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementReconciled(agreementId, oldMaxClaim, activeOnlyClaim);

        vm.prank(operator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, pendingHash, 0);
    }

    function test_CancelPendingUpdate_CanOfferNewUpdateAfterCancel() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

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

        // Cancel pending update on collector, then offer a new update
        _cancelPendingUpdate(agreementId);

        // Offer a new update with the next valid nonce (2) — collector incremented to 1
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

        // maxNextClaim = max(3700, 950) = 3700 (active dominates)
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(
            IAgreementCollector(address(recurringCollector)),
            agreementId
        );
        assertEq(info.maxNextClaim, originalMaxClaim);
    }

    function test_CancelPendingUpdate_RejectsUnknown_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));

        // cancelAgreement is a passthrough — unknown agreement triggers AgreementRejected via callback
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRejected(
            fakeId,
            address(recurringCollector),
            IRecurringAgreementManagement.AgreementRejectionReason.UnknownAgreement
        );

        vm.prank(operator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), fakeId, bytes32(0), 0);
    }

    function test_CancelPendingUpdate_Revert_WhenNotOperator() public {
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
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, bytes32(0), 0);
    }

    function test_CancelPendingUpdate_Succeeds_WhenPaused() public {
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

        // Role-gated functions should succeed even when paused
        vm.prank(operator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, bytes32(0), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
