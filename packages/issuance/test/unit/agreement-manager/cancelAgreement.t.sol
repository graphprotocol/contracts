// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IServiceAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IServiceAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { ServiceAgreementManagerSharedTest } from "./shared.t.sol";

contract ServiceAgreementManagerCancelAgreementTest is ServiceAgreementManagerSharedTest {
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
        emit IServiceAgreementManager.AgreementCanceled(agreementId, indexer);

        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);

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

        uint256 originalRequired = agreementManager.getRequiredEscrow(indexer);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertEq(originalRequired, maxClaim);

        // Accept, then cancel by SP (maxNextClaim -> 0)
        _setAgreementCanceledBySP(agreementId, rca);

        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);

        // After cancelAgreement (which now reconciles), required escrow should decrease
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
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
        agreementManager.cancelAgreement(agreementId);

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
        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);

        // Should NOT have called SubgraphService
        assertEq(mockSubgraphService.cancelCallCount(agreementId), 0);

        // Required escrow should drop to 0 (CanceledBySP has maxNextClaim=0)
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
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
        vm.expectRevert(abi.encodeWithSelector(IServiceAgreementManager.AgreementNotAccepted.selector, agreementId));
        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);
    }

    function test_CancelAgreement_Revert_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));

        vm.expectRevert(abi.encodeWithSelector(IServiceAgreementManager.AgreementNotOffered.selector, fakeId));
        vm.prank(operator);
        agreementManager.cancelAgreement(fakeId);
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
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonOperator, OPERATOR_ROLE)
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
        emit IServiceAgreementManager.AgreementCanceled(agreementId, indexer);

        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
