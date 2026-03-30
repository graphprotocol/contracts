// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementManagerCollectionCallbackTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- beforeCollection --

    function test_BeforeCollection_TopsUpWhenEscrowShort() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Simulate: escrow was partially drained (e.g. by a previous collection)
        // The mock escrow has the full balance from offerAgreement, so we need to
        // set up a scenario where balance < tokensToCollect.
        // We'll just call beforeCollection with a large tokensToCollect.
        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Mint more tokens so SAM has available balance to deposit
        token.mint(address(agreementManager), 1000 ether);

        // Request more than current escrow balance
        uint256 tokensToCollect = escrowBalance + 500 ether;

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, tokensToCollect);

        // Escrow should now have enough
        (uint256 newBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(newBalance, tokensToCollect);
    }

    function test_BeforeCollection_NoOpWhenEscrowSufficient() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        (uint256 escrowBefore, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Request less than current escrow — should be a no-op
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1 ether);

        (uint256 escrowAfter, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowAfter, escrowBefore);
    }

    function test_BeforeCollection_NoOp_WhenCallerNotRecurringCollector() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Wrong collector sees no agreement under its namespace — silent no-op
        agreementManager.beforeCollection(agreementId, 100 ether);
    }

    function test_BeforeCollection_IgnoresUnknownAgreement() public {
        bytes16 unknownId = bytes16(keccak256("unknown"));

        // Should not revert
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(unknownId, 100 ether);
    }

    // -- afterCollection --

    function test_AfterCollection_ReconcileAndFundEscrow() public {
        // Offer: maxNextClaim = 1e18 * 3600 + 100e18 = 3700e18
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 3700 ether);

        // Simulate: agreement accepted and first collection happened
        uint64 acceptedAt = uint64(block.timestamp);
        uint64 lastCollectionAt = uint64(block.timestamp + 1 hours);
        _setAgreementCollected(agreementId, rca, acceptedAt, lastCollectionAt);

        vm.warp(lastCollectionAt);

        // Call afterCollection as RecurringCollector (simulates post-collect callback)
        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 500 ether);

        // After first collection, maxInitialTokens no longer applies
        // New max = 1e18 * 3600 = 3600e18
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            3600 ether
        );
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 3600 ether);
    }

    function test_AfterCollection_NoOp_WhenCallerNotRecurringCollector() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Wrong collector sees no agreement under its namespace — silent no-op
        agreementManager.afterCollection(agreementId, 100 ether);
    }

    function test_AfterCollection_IgnoresUnknownAgreement() public {
        bytes16 unknownId = bytes16(keccak256("unknown"));

        // Should not revert — just silently return
        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(unknownId, 100 ether);
    }

    function test_AfterCollection_CanceledByServiceProvider() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementCanceledBySP(agreementId, rca);

        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 0);

        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            0
        );
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
