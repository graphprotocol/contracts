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
        assertEq(agreement.activeTermsHash, _recurringCollector.hashRCAU(rcau));
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
            rcau.endsAt,
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection
        );

        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, updateSig);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.activeTermsHash, _recurringCollector.hashRCAU(rcau));
        assertEq(agreement.updateNonce, 1);
    }

    /// @notice Replacing the active offer preserves an independent pending RCAU. The update is
    /// still a valid signed offer against the same agreementId; the payer may cancel it
    /// explicitly if they don't want it. The contract shouldn't silently invalidate it.
    function test_MixedPath_OfferNew_PreservesPendingRcau() public {
        MockAgreementOwner approver = new MockAgreementOwner();

        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: 0,
                endsAt: 0,
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
        // Derive the deterministic agreement ID from rca1's post-sensible fields.
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca1.payer,
            rca1.dataService,
            rca1.serviceProvider,
            rca1.deadline,
            rca1.nonce
        );

        // Step 1: offer RCA → active = hashRCA(rca1)
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca1), 0);
        bytes32 rca1Hash = _recurringCollector.hashRCA(rca1);

        // Step 2: offer RCAU → pending = hashRCAU(rcau)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0,
                endsAt: 0,
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
        bytes32 rcauHash = _recurringCollector.hashRCAU(rcau);

        // Pre-check: pending is set
        IRecurringCollector.AgreementData memory before = _recurringCollector.getAgreement(agreementId);
        assertEq(before.activeTermsHash, rca1Hash, "active should be rca1Hash after offer");
        assertEq(before.pendingTermsHash, rcauHash, "pending should be rcauHash after offer UPDATE");

        // Step 3: offer different RCA with same primary fields (same agreementId, different terms)
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = rca1;
        rca2.maxInitialTokens = 999 ether; // different terms → different hash, same agreementId
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca2), 0);
        bytes32 rca2Hash = _recurringCollector.hashRCA(rca2);

        // Post-check: active replaced, pending preserved (still the original RCAU)
        IRecurringCollector.AgreementData memory afterOffer = _recurringCollector.getAgreement(agreementId);
        assertEq(afterOffer.activeTermsHash, rca2Hash, "active should be rca2Hash");
        assertEq(afterOffer.pendingTermsHash, rcauHash, "pending RCAU should still be queued");

        // The pending offer's $.terms entry must still be retrievable — payer can still accept it
        (uint8 pendingType, bytes memory pendingData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        assertEq(pendingType, OFFER_TYPE_UPDATE, "pending slot should still hold update offer");
        assertEq(keccak256(pendingData), keccak256(abi.encode(rcau)), "pending data should be the original RCAU");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
