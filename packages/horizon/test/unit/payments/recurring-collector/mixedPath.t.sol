// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { OFFER_TYPE_NEW, OFFER_TYPE_UPDATE } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

/// @notice Tests that ECDSA and contract-approved paths can be mixed for accept and update.
contract RecurringCollectorMixedPathTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    /// @notice Contract-approved accept, then contract-approved update works
    function test_MixedPath_UnsignedAccept_UnsignedUpdate_OK() public {
        MockAgreementOwner approver = new MockAgreementOwner();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(approver),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        // Accept via contract-approved path
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        // Update via contract-approved path (use sensibleRCAU to stay in valid ranges)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 50 ether,
                maxOngoingTokensPerSecond: 0.5 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(
            rca.dataService,
            address(approver),
            rca.serviceProvider,
            agreementId,
            uint64(block.timestamp),
            rcau.endsAt,
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection
        );

        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");

        // Verify updated terms
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.maxOngoingTokensPerSecond, rcau.maxOngoingTokensPerSecond);
        assertEq(agreement.maxSecondsPerCollection, rcau.maxSecondsPerCollection);
        assertEq(agreement.updateNonce, 1);
    }

    /// @notice ECDSA-accepted agreement with EOA payer → unsigned update fails (no stored offer for EOA).
    /// Restored negative test: verifies EOA payers accepted via ECDSA cannot be updated via unsigned path.
    function test_MixedPath_ECDSAAccept_UnsignedUpdate_RevertsForEOA() public {
        uint256 signerKey = 0xA11CE;
        address payer = vm.addr(signerKey);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: payer,
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        // Accept via ECDSA
        _recurringCollectorHelper.authorizeSignerWithChecks(payer, signerKey);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, signerKey);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, signature);

        // Try unsigned update — should revert because no offer is stored (EOA can't call offer())
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.RecurringCollectorInvalidSigner.selector));
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    /// @notice ECDSA-accepted agreement → ECDSA-signed update succeeds (both paths consistent)
    function test_MixedPath_ECDSAAccept_ECDSAUpdate_OK() public {
        uint256 signerKey = 0xA11CE;
        address payer = vm.addr(signerKey);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: payer,
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );

        // Accept via ECDSA
        _recurringCollectorHelper.authorizeSignerWithChecks(payer, signerKey);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, signerKey);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, signature);

        // Update via ECDSA — should succeed
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );
        (, bytes memory updateSig) = _recurringCollectorHelper.generateSignedRCAU(rcau, signerKey);

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(
            rca.dataService,
            payer,
            rca.serviceProvider,
            agreementId,
            uint64(block.timestamp),
            rcau.endsAt,
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection
        );

        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, updateSig);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.maxOngoingTokensPerSecond, rcau.maxOngoingTokensPerSecond);
        assertEq(agreement.updateNonce, 1);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
