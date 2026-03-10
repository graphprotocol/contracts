// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

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

        // Simulate acceptance
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementCanceled(agreementId, indexer);

        vm.prank(operator);
        bool gone = agreementManager.cancelAgreement(agreementId);
        assertFalse(gone); // still tracked after cancel

        // Verify the mock was called
        assertTrue(mockSubgraphService.canceled(agreementId));
        assertEq(mockSubgraphService.cancelCallCount(agreementId), 1);
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
        vm.prank(operator);
        bool gone = agreementManager.cancelAgreement(agreementId);
        assertTrue(gone); // deleted inline — nothing left to claim

        // After cancelAgreement (which now reconciles), required escrow should decrease
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_CancelAgreement_Idempotent_CanceledByPayer() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as CanceledByPayer (already canceled)
        _setAgreementCanceledByPayer(agreementId, rca, uint64(block.timestamp), uint64(block.timestamp + 1 hours), 0);

        // Should succeed — idempotent, skips the external cancel call
        vm.prank(operator);
        bool gone = agreementManager.cancelAgreement(agreementId);
        assertFalse(gone); // still tracked after cancel

        // Should NOT have called SubgraphService
        assertEq(mockSubgraphService.cancelCallCount(agreementId), 0);
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
        vm.prank(operator);
        bool gone = agreementManager.cancelAgreement(agreementId);
        assertTrue(gone); // deleted inline — nothing left to claim

        // Should NOT have called SubgraphService
        assertEq(mockSubgraphService.cancelCallCount(agreementId), 0);

        // Required escrow should drop to 0
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_CancelAgreement_Revert_WhenNotAccepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Agreement is NotAccepted — should revert
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringAgreementManagement.AgreementNotAccepted.selector, agreementId)
        );
        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);
    }

    function test_CancelAgreement_ReturnsTrue_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));

        // Returns true (gone) when agreement not found
        vm.prank(operator);
        bool gone = agreementManager.cancelAgreement(fakeId);
        assertTrue(gone);
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

        address nonOperator = makeAddr("nonOperator");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonOperator,
                AGREEMENT_MANAGER_ROLE
            )
        );
        vm.prank(nonOperator);
        agreementManager.cancelAgreement(agreementId);
    }

    function test_CancelAgreement_Revert_WhenPaused() public {
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

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);
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
        emit IRecurringAgreementManagement.AgreementCanceled(agreementId, indexer);

        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
