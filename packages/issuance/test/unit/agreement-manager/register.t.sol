// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementManagerOfferTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_Offer_SetsAgreementState() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 expectedId) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        assertEq(agreementId, expectedId);
        // maxNextClaim = maxOngoingTokensPerSecond * maxSecondsPerCollection + maxInitialTokens
        // = 1e18 * 3600 + 100e18 = 3700e18
        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), expectedMaxClaim);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), expectedMaxClaim);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
    }

    function test_Offer_FundsEscrow() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;

        // Fund with surplus so Full mode stays active (deficit < balance required)
        token.mint(address(agreementManager), expectedMaxClaim + 1);
        vm.prank(operator);
        agreementManager.offerAgreement(rca, _collector());

        // Verify escrow was funded
        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowBalance, expectedMaxClaim);
    }

    function test_Offer_PartialFunding_WhenInsufficientBalance() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;
        uint256 available = 500 ether; // Less than expectedMaxClaim

        // Fund with less than needed
        token.mint(address(agreementManager), available);
        vm.prank(operator);
        agreementManager.offerAgreement(rca, _collector());

        // Since available < required, Full degrades to OnDemand (deposit target = 0).
        // No proactive deposit; JIT beforeCollection is the safety net.
        (uint256 escrowBalanceAfter, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowBalanceAfter, 0);
        // Escrow balance is 0 since no deposit was made
        assertEq(agreementManager.getEscrowAccount(_collector(), indexer).balance, 0);
    }

    function test_Offer_EmitsEvent() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 expectedId = recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;

        token.mint(address(agreementManager), expectedMaxClaim);

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementOffered(expectedId, indexer, expectedMaxClaim);

        vm.prank(operator);
        agreementManager.offerAgreement(rca, _collector());
    }

    function test_Offer_AuthorizesHash() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        _offerAgreement(rca);

        // The agreement hash should be authorized for the IAgreementOwner callback
        bytes32 agreementHash = recurringCollector.hashRCA(rca);
        bytes4 result = agreementManager.approveAgreement(agreementHash);
        assertEq(result, agreementManager.approveAgreement.selector);
    }

    function test_Offer_MultipleAgreements_SameIndexer() public {
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

        assertTrue(id1 != id2);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim1 + maxClaim2);
    }

    function test_Offer_Revert_WhenPayerMismatch() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.payer = address(0xdead); // Wrong payer

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringAgreementManagement.PayerMustBeManager.selector,
                address(0xdead),
                address(agreementManager)
            )
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca, _collector());
    }

    function test_Offer_Revert_WhenAlreadyOffered() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringAgreementManagement.AgreementAlreadyOffered.selector, agreementId)
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca, _collector());
    }

    function test_Offer_Revert_WhenNotOperator() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
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
        agreementManager.offerAgreement(rca, _collector());
    }

    function test_Offer_Revert_WhenUnauthorizedCollector() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        address fakeCollector = makeAddr("fakeCollector");
        token.mint(address(agreementManager), 10_000 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringAgreementManagement.UnauthorizedCollector.selector, fakeCollector)
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca, IRecurringCollector(fakeCollector));
    }

    function test_Offer_Revert_WhenPaused() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        // Grant pause role and pause
        vm.startPrank(governor);
        agreementManager.grantRole(keccak256("PAUSE_ROLE"), governor);
        agreementManager.pause();
        vm.stopPrank();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(operator);
        agreementManager.offerAgreement(rca, _collector());
    }

    /* solhint-enable graph/func-name-mixedcase */
}
