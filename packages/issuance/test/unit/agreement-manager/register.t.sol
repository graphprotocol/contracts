// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IServiceAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IServiceAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { ServiceAgreementManagerSharedTest } from "./shared.t.sol";

contract ServiceAgreementManagerOfferTest is ServiceAgreementManagerSharedTest {
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
        assertEq(agreementManager.getRequiredEscrow(indexer), expectedMaxClaim);
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

        // Fund and register
        token.mint(address(agreementManager), expectedMaxClaim);
        vm.prank(operator);
        agreementManager.offerAgreement(rca);

        // Verify escrow was funded
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer).balance,
            expectedMaxClaim
        );
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
        agreementManager.offerAgreement(rca);

        // Escrow should have the available amount, not the full required
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer).balance,
            available
        );
        // Deficit should be the remainder
        assertEq(agreementManager.getDeficit(indexer), expectedMaxClaim - available);
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
        emit IServiceAgreementManager.AgreementOffered(expectedId, indexer, expectedMaxClaim);

        vm.prank(operator);
        agreementManager.offerAgreement(rca);
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

        // The agreement hash should be authorized for the IContractApprover callback
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
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim1 + maxClaim2);
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
                IServiceAgreementManager.PayerMustBeManager.selector,
                address(0xdead),
                address(agreementManager)
            )
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca);
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

        vm.expectRevert(abi.encodeWithSelector(IServiceAgreementManager.AgreementAlreadyOffered.selector, agreementId));
        vm.prank(operator);
        agreementManager.offerAgreement(rca);
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
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, nonOperator, OPERATOR_ROLE)
        );
        vm.prank(nonOperator);
        agreementManager.offerAgreement(rca);
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
        agreementManager.offerAgreement(rca);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
