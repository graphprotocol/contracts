// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

contract RecurringAgreementManagerMultiCollectorTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    MockRecurringCollector internal collector2;

    function setUp() public override {
        super.setUp();
        collector2 = new MockRecurringCollector();
        vm.label(address(collector2), "RecurringCollector2");

        vm.prank(governor);
        agreementManager.grantRole(COLLECTOR_ROLE, address(collector2));
    }

    // -- Helpers --

    function _makeRCAForCollector(
        MockRecurringCollector collector,
        uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond,
        uint32 maxSecondsPerCollection,
        uint64 endsAt,
        uint256 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) {
        rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: endsAt,
            payer: address(agreementManager),
            dataService: dataService,
            serviceProvider: indexer,
            maxInitialTokens: maxInitialTokens,
            maxOngoingTokensPerSecond: maxOngoingTokensPerSecond,
            minSecondsPerCollection: 60,
            maxSecondsPerCollection: maxSecondsPerCollection,
            nonce: nonce,
            metadata: ""
        });
        agreementId = collector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
    }

    // -- Tests --

    function test_MultiCollector_RequiredEscrowIsolation() public {
        // Offer agreement via collector1 (the default recurringCollector)
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForCollector(
            recurringCollector,
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days),
            1
        );
        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        agreementManager.offerAgreement(rca1, _collector());

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;

        // Offer agreement via collector2 with different terms
        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForCollector(
            collector2,
            200 ether,
            2 ether,
            7200,
            uint64(block.timestamp + 365 days),
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, IRecurringCollector(address(collector2)));

        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // Required escrow is independent per collector
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim1);
        assertEq(agreementManager.getSumMaxNextClaim(IRecurringCollector(address(collector2)), indexer), maxClaim2);
    }

    function test_MultiCollector_BeforeCollectionOnlyOwnAgreements() public {
        // Offer agreement via collector1
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, bytes16 agreementId1) = _makeRCAForCollector(
            recurringCollector,
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days),
            1
        );
        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        agreementManager.offerAgreement(rca1, _collector());

        // collector2 cannot call beforeCollection on collector1's agreement
        vm.prank(address(collector2));
        vm.expectRevert(IRecurringAgreementManagement.OnlyAgreementCollector.selector);
        agreementManager.beforeCollection(agreementId1, 100 ether);

        // collector1 can call beforeCollection on its own agreement
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId1, 100 ether);
    }

    function test_MultiCollector_AfterCollectionOnlyOwnAgreements() public {
        // Offer agreement via collector1
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, bytes16 agreementId1) = _makeRCAForCollector(
            recurringCollector,
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days),
            1
        );
        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        agreementManager.offerAgreement(rca1, _collector());

        // collector2 cannot call afterCollection on collector1's agreement
        vm.prank(address(collector2));
        vm.expectRevert(IRecurringAgreementManagement.OnlyAgreementCollector.selector);
        agreementManager.afterCollection(agreementId1, 100 ether);
    }

    function test_MultiCollector_SeparateEscrowAccounts() public {
        // Offer via collector1
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForCollector(
            recurringCollector,
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days),
            1
        );
        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        // Fund with surplus so Full mode stays active (deficit < balance required)
        token.mint(address(agreementManager), maxClaim1 + 1);
        vm.prank(operator);
        agreementManager.offerAgreement(rca1, _collector());

        // Offer via collector2
        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForCollector(
            collector2,
            200 ether,
            2 ether,
            7200,
            uint64(block.timestamp + 365 days),
            2
        );
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;
        // Fund with surplus so Full mode stays active (deficit < balance required)
        token.mint(address(agreementManager), maxClaim2 + 1);
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, IRecurringCollector(address(collector2)));

        // Escrow accounts are separate per (collector, provider)
        (uint256 collector1Balance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(collector1Balance, maxClaim1);
        (uint256 collector2Balance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(collector2),
            indexer
        );
        assertEq(collector2Balance, maxClaim2);
    }

    function test_MultiCollector_RevokeOnlyAffectsOwnCollectorEscrow() public {
        // Offer via both collectors
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, bytes16 agreementId1) = _makeRCAForCollector(
            recurringCollector,
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days),
            1
        );
        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        agreementManager.offerAgreement(rca1, _collector());

        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForCollector(
            collector2,
            200 ether,
            2 ether,
            7200,
            uint64(block.timestamp + 365 days),
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, IRecurringCollector(address(collector2)));

        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // Revoke collector1's agreement
        vm.prank(operator);
        agreementManager.revokeOffer(agreementId1);

        // Collector1 escrow cleared, collector2 unaffected
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(IRecurringCollector(address(collector2)), indexer), maxClaim2);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
