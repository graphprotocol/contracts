// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IServiceAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IServiceAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { ServiceAgreementManagerSharedTest } from "./shared.t.sol";

contract ServiceAgreementManagerOfferUpdateTest is ServiceAgreementManagerSharedTest {
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
        assertEq(agreementManager.getRequiredEscrow(indexer), originalMaxClaim + expectedPendingMaxClaim);
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

        // The update hash should be authorized for the IContractApprover callback
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
        uint256 totalRequired = originalMaxClaim + pendingMaxClaim;

        // Fund and offer agreement
        token.mint(address(agreementManager), totalRequired);
        vm.prank(operator);
        bytes16 agreementId = agreementManager.offerAgreement(rca);

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
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer).balance,
            totalRequired
        );
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
        assertEq(agreementManager.getRequiredEscrow(indexer), originalMaxClaim + pendingMaxClaim1);

        // Second pending update (replaces first)
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

        uint256 pendingMaxClaim2 = 0.5 ether * 1800 + 50 ether;
        // Old pending removed, new pending added
        assertEq(agreementManager.getRequiredEscrow(indexer), originalMaxClaim + pendingMaxClaim2);
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
        emit IServiceAgreementManager.AgreementUpdateOffered(agreementId, pendingMaxClaim, 1);

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

        vm.expectRevert(abi.encodeWithSelector(IServiceAgreementManager.AgreementNotOffered.selector, fakeId));
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
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonOperator, OPERATOR_ROLE)
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

    /* solhint-enable graph/func-name-mixedcase */
}
