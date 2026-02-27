// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IServiceAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IServiceAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { ServiceAgreementManagerSharedTest } from "./shared.t.sol";

contract ServiceAgreementManagerRemoveTest is ServiceAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_Remove_CanceledByServiceProvider() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);

        // SP cancels - immediately removable
        _setAgreementCanceledBySP(agreementId, rca);

        vm.expectEmit(address(agreementManager));
        emit IServiceAgreementManager.AgreementRemoved(agreementId, indexer);

        agreementManager.removeAgreement(agreementId);

        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 0);
    }

    function test_Remove_FullyExpiredAgreement() public {
        uint64 endsAt = uint64(block.timestamp + 1 hours);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            endsAt
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as accepted, collected at endsAt (fully expired, window empty)
        _setAgreementCollected(agreementId, rca, uint64(block.timestamp), endsAt);
        vm.warp(endsAt);

        agreementManager.removeAgreement(agreementId);

        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
    }

    function test_Remove_CanceledByPayer_WindowExpired() public {
        uint64 startTime = uint64(block.timestamp);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(startTime + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Payer canceled, window fully consumed
        uint64 canceledAt = uint64(startTime + 2 hours);
        _setAgreementCanceledByPayer(agreementId, rca, startTime, canceledAt, canceledAt);

        agreementManager.removeAgreement(agreementId);

        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
    }

    function test_Remove_ReducesRequiredEscrow_WithMultipleAgreements() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether; // 3700e18
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether; // 14600e18
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim1 + maxClaim2);

        // Cancel agreement 1 by SP and remove it
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.removeAgreement(id1);

        // Only agreement 2's original maxClaim remains
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim2);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);

        // Agreement 2 still tracked
        assertEq(agreementManager.getAgreementMaxNextClaim(id2), maxClaim2);
    }

    function test_Remove_Revert_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));
        vm.expectRevert(abi.encodeWithSelector(IServiceAgreementManager.AgreementNotOffered.selector, fakeId));
        agreementManager.removeAgreement(fakeId);
    }

    function test_Remove_Revert_WhenStillClaimable_Accepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as accepted but never collected - still claimable
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        vm.expectRevert(
            abi.encodeWithSelector(IServiceAgreementManager.AgreementStillClaimable.selector, agreementId, maxClaim)
        );
        agreementManager.removeAgreement(agreementId);
    }

    function test_Remove_ExpiredOffer_NotAccepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Warp past the RCA deadline (default: block.timestamp + 1 hours in _makeRCA)
        vm.warp(block.timestamp + 2 hours);

        // Agreement not accepted + past deadline — should be removable
        agreementManager.removeAgreement(agreementId);

        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
    }

    function test_Remove_Revert_WhenStillClaimable_NotAccepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Not accepted yet - stored maxNextClaim is used (can still be accepted and then claimed)
        uint256 storedMaxClaim = agreementManager.getAgreementMaxNextClaim(agreementId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IServiceAgreementManager.AgreementStillClaimable.selector,
                agreementId,
                storedMaxClaim
            )
        );
        agreementManager.removeAgreement(agreementId);
    }

    function test_Remove_Revert_WhenCanceledByPayer_WindowStillOpen() public {
        uint64 startTime = uint64(block.timestamp);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(startTime + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Payer canceled but window is still open (not yet collected)
        uint64 canceledAt = uint64(startTime + 2 hours);
        _setAgreementCanceledByPayer(agreementId, rca, startTime, canceledAt, 0);

        // Still claimable: window = canceledAt - acceptedAt = 7200s, capped at 3600s
        // maxClaim = 1e18 * 3600 + 100e18 (never collected)
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        vm.expectRevert(
            abi.encodeWithSelector(IServiceAgreementManager.AgreementStillClaimable.selector, agreementId, maxClaim)
        );
        agreementManager.removeAgreement(agreementId);
    }

    function test_Remove_Permissionless() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // SP cancels
        _setAgreementCanceledBySP(agreementId, rca);

        // Anyone can remove
        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        agreementManager.removeAgreement(agreementId);

        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
    }

    function test_Remove_ClearsPendingUpdate() public {
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

        // SP cancels - immediately removable
        _setAgreementCanceledBySP(agreementId, rca);

        agreementManager.removeAgreement(agreementId);

        // Both original and pending should be cleared from requiredEscrow
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
