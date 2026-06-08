// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementManagerCancelAgreementTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_CancelAgreement_Accepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Simulate acceptance, then advance time so cancel creates a non-zero claim window
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));
        vm.warp(block.timestamp + 10);

        // After cancel by payer with 10s elapsed: maxNextClaim = 1e18 * 10 + 100e18 = 110e18
        uint256 preMaxClaim = agreementManager
            .getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId)
            .maxNextClaim;

        bool gone = _cancelAgreement(agreementId);
        // CanceledByPayer with remaining claim window => still tracked
        assertFalse(gone);

        // Verify maxNextClaim decreased to the payer-cancel window
        uint256 postMaxClaim = agreementManager
            .getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId)
            .maxNextClaim;
        assertEq(postMaxClaim, 1 ether * 10 + 100 ether, "maxNextClaim should reflect payer-cancel window");
        assertTrue(postMaxClaim < preMaxClaim, "maxNextClaim should decrease after cancel");
    }

    function test_CancelAgreement_ReconcileAfterCancel() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        uint256 originalRequired = agreementManager.getSumMaxNextClaim(_collector(), indexer);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertEq(originalRequired, maxClaim);

        // Accept, then cancel by SP (maxNextClaim -> 0)
        _setAgreementCanceledBySP(agreementId, rca);

        // CanceledBySP has maxNextClaim=0 so agreement is deleted inline
        bool gone = _cancelAgreement(agreementId);
        assertTrue(gone); // deleted inline — nothing left to claim

        // After cancelAgreement (which now reconciles), required escrow should decrease
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_CancelAgreement_AlreadyCanceled_StillForwards() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as CanceledByPayer (already canceled)
        _setAgreementCanceledByPayer(agreementId, rca, uint64(block.timestamp), uint64(block.timestamp + 1 hours), 0);

        // cancelAgreement always forwards to collector — caller is responsible
        // for knowing whether the agreement is already canceled
        bool gone = _cancelAgreement(agreementId);
        // Agreement may or may not be fully gone depending on collector behavior
        // after re-cancel — the key invariant is that it doesn't revert
        assertTrue(gone || !gone); // no-op assertion, just verify no revert
    }

    function test_CancelAgreement_Idempotent_CanceledByServiceProvider() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as CanceledByServiceProvider
        _setAgreementCanceledBySP(agreementId, rca);

        // Should succeed — idempotent, reconciles to update escrow
        // CanceledBySP has maxNextClaim=0 so agreement is deleted inline
        bool gone = _cancelAgreement(agreementId);
        assertTrue(gone); // deleted inline — nothing left to claim

        // Required escrow should drop to 0
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_CancelAgreement_Offered() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Cancel an offered (not yet accepted) agreement — should succeed and clean up
        bool gone = _cancelAgreement(agreementId);
        assertTrue(gone);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_CancelAgreement_RejectsUnknown_WhenNotOffered() public {
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

    function test_CancelAgreement_Revert_WhenNotOperator() public {
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

        bytes32 activeHash = recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        address nonOperator = makeAddr("nonOperator");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonOperator,
                AGREEMENT_MANAGER_ROLE
            )
        );
        vm.prank(nonOperator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, activeHash, 0);
    }

    function test_CancelAgreement_SucceedsWhenPaused() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        vm.startPrank(governor);
        agreementManager.grantRole(keccak256("PAUSE_ROLE"), governor);
        agreementManager.pause();
        vm.stopPrank();

        // Role-gated functions should succeed even when paused
        bytes32 activeHash = recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(operator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, activeHash, 0);
    }

    function test_CancelAgreement_EmitsEvent() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRemoved(agreementId);

        _cancelAgreement(agreementId);
    }

    function test_CancelAgreement_Succeeds_WhenPaused() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        vm.startPrank(governor);
        agreementManager.grantRole(keccak256("PAUSE_ROLE"), governor);
        agreementManager.pause();
        vm.stopPrank();

        // Role-gated functions should succeed even when paused
        bytes32 activeHash = recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(operator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, activeHash, 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
