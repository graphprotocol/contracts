// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IIndexingAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIndexingAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { IndexingAgreementManagerSharedTest } from "./shared.t.sol";

contract IndexingAgreementManagerMaintainTest is IndexingAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_Maintain_ThawsWhenNoAgreements() public {
        // Create agreement, fund escrow, then remove it
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Verify escrow was funded
        uint256 escrowBalance = paymentsEscrow.getBalance(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowBalance, maxClaim);

        // SP cancels and we remove
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.removeAgreement(agreementId);
        assertEq(agreementManager.getIndexerAgreementCount(indexer), 0);

        // Maintain should thaw the escrow balance
        vm.expectEmit(address(agreementManager));
        emit IIndexingAgreementManager.EscrowThawed(indexer, maxClaim);

        agreementManager.maintain(indexer);

        // getBalance should now return 0 (thawing)
        escrowBalance = paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer);
        assertEq(escrowBalance, 0);
    }

    function test_Maintain_WithdrawsAfterThawComplete() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // SP cancels and remove
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.removeAgreement(agreementId);

        // First maintain: thaw
        agreementManager.maintain(indexer);

        // Fast forward past thawing period (1 day in mock)
        vm.warp(block.timestamp + 1 days + 1);

        uint256 agreementManagerBalanceBefore = token.balanceOf(address(agreementManager));

        // Second maintain: withdraw + no more to thaw
        vm.expectEmit(address(agreementManager));
        emit IIndexingAgreementManager.EscrowWithdrawn(indexer);

        agreementManager.maintain(indexer);

        // Tokens should be back in IndexingAgreementManager
        uint256 agreementManagerBalanceAfter = token.balanceOf(address(agreementManager));
        assertEq(agreementManagerBalanceAfter - agreementManagerBalanceBefore, maxClaim);
    }

    function test_Maintain_NoopWhenNoBalance() public {
        // No agreements, no balance — should succeed silently
        agreementManager.maintain(indexer);
    }

    function test_Maintain_ReturnsEarlyWhenStillThawing() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // SP cancels and remove
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.removeAgreement(agreementId);

        // First maintain: thaw
        agreementManager.maintain(indexer);

        // Second maintain before thaw complete: should return early (no events)
        agreementManager.maintain(indexer);

        // Balance should still be 0 (thawing in progress)
        uint256 escrowBalance = paymentsEscrow.getBalance(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowBalance, 0);
    }

    function test_Maintain_Revert_WhenAgreementsExist() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        _offerAgreement(rca);

        vm.expectRevert(
            abi.encodeWithSelector(
                IIndexingAgreementManager.IndexingAgreementManagerStillHasAgreements.selector,
                indexer
            )
        );
        agreementManager.maintain(indexer);
    }

    function test_Maintain_Permissionless() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.removeAgreement(agreementId);

        // Anyone can call maintain
        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        agreementManager.maintain(indexer);
    }

    function test_Maintain_ThawIsolation_CrossIndexer() public {
        address indexer2 = makeAddr("indexer2");

        // Create agreements for two different indexers
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
        rca2.serviceProvider = indexer2;
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // Verify both indexers have funded escrow
        assertEq(paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer), maxClaim1);
        assertEq(
            paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer2),
            maxClaim2
        );

        // Cancel and remove only indexer1's agreement
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.removeAgreement(id1);

        // Maintain indexer1 — should thaw
        agreementManager.maintain(indexer);

        // Indexer1 escrow should be thawing (balance = 0)
        assertEq(paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer), 0);

        // Indexer2 escrow should be unaffected
        assertEq(
            paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer2),
            maxClaim2
        );

        // Maintain on indexer2 should revert (still has agreements)
        vm.expectRevert(
            abi.encodeWithSelector(
                IIndexingAgreementManager.IndexingAgreementManagerStillHasAgreements.selector,
                indexer2
            )
        );
        agreementManager.maintain(indexer2);

        // Cancel and remove indexer2's agreement
        _setAgreementCanceledBySP(id2, rca2);
        agreementManager.removeAgreement(id2);

        // Now indexer2 can be maintained independently
        agreementManager.maintain(indexer2);
        assertEq(paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer2), 0);
    }

    function test_OfferAgreement_CancelsThaw() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // SP cancels, remove, and start thawing
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.removeAgreement(agreementId);
        agreementManager.maintain(indexer);

        // getBalance should be 0 (thawing)
        uint256 escrowBalance = paymentsEscrow.getBalance(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowBalance, 0);

        // Now offer a new agreement — should cancel the thaw
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 180 days)
        );
        rca2.nonce = 2;
        _offerAgreement(rca2);

        // Thaw should have been canceled — getBalance should be positive again
        escrowBalance = paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer);
        assertTrue(escrowBalance > 0, "Thaw should have been canceled");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
