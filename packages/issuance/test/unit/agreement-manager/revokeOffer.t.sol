// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IServiceAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IServiceAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { ServiceAgreementManagerSharedTest } from "./shared.t.sol";

contract ServiceAgreementManagerRevokeOfferTest is ServiceAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_RevokeOffer_ClearsAgreement() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);

        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim);

        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);

        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 0);
    }

    function test_RevokeOffer_InvalidatesHash() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Hash is authorized before revoke
        bytes32 rcaHash = recurringCollector.hashRCA(rca);
        agreementManager.approveAgreement(rcaHash); // should not revert

        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);

        // Hash should be rejected after revoke (agreement no longer exists)
        assertEq(agreementManager.approveAgreement(rcaHash), bytes4(0));
    }

    function test_RevokeOffer_ClearsPendingUpdate() public {
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

        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;
        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getRequiredEscrow(indexer), originalMaxClaim + pendingMaxClaim);

        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);

        // Both original and pending should be cleared
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
    }

    function test_RevokeOffer_EmitsEvent() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        vm.expectEmit(address(agreementManager));
        emit IServiceAgreementManager.OfferRevoked(agreementId, indexer);

        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);
    }

    function test_RevokeOffer_Revert_WhenAlreadyAccepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Simulate acceptance in RC
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        vm.expectRevert(
            abi.encodeWithSelector(IServiceAgreementManager.AgreementAlreadyAccepted.selector, agreementId)
        );
        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);
    }

    function test_RevokeOffer_Revert_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));
        vm.expectRevert(abi.encodeWithSelector(IServiceAgreementManager.AgreementNotOffered.selector, fakeId));
        vm.prank(operator);
        agreementManager.revokeOffer(fakeId);
    }

    function test_RevokeOffer_Revert_WhenNotOperator() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        address nonOperator = makeAddr("nonOperator");
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonOperator, OPERATOR_ROLE)
        );
        vm.prank(nonOperator);
        agreementManager.revokeOffer(agreementId);
    }

    function test_RevokeOffer_Revert_WhenPaused() public {
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
        agreementManager.revokeOffer(agreementId);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
