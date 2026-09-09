// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorAcceptTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Accept(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(uint8(agreement.state), uint8(IRecurringCollector.AgreementState.Accepted));
    }

    function test_Accept_Revert_WhenAcceptanceDeadlineElapsed(
        IRecurringCollector.RecurringCollectionAgreement memory fuzzyRCA,
        bytes memory fuzzySignature,
        uint256 unboundedSkip
    ) public {
        // Ensure non-empty signature so the signed path is taken (which checks deadline first)
        vm.assume(fuzzySignature.length > 0);
        // Pranking as the proxy admin hits ProxyDeniedAdminAccess before the deadline check.
        vm.assume(fuzzyRCA.dataService != _proxyAdmin);
        // Generate deterministic agreement ID for validation
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            fuzzyRCA.payer,
            fuzzyRCA.dataService,
            fuzzyRCA.serviceProvider,
            fuzzyRCA.deadline,
            fuzzyRCA.nonce
        );
        vm.assume(agreementId != bytes16(0));
        skip(boundSkip(unboundedSkip, 1, type(uint64).max - block.timestamp));
        fuzzyRCA = _recurringCollectorHelper.withElapsedAcceptDeadline(fuzzyRCA);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
            block.timestamp,
            fuzzyRCA.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(fuzzyRCA.dataService);
        _recurringCollector.accept(fuzzyRCA, fuzzySignature);
    }

    function test_Accept_Idempotent_WhenAlreadyAccepted(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes memory signature,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        // Re-accepting the same RCA is a no-op — succeeds without reverting or re-emitting.
        vm.recordLogs();
        vm.prank(acceptedRca.dataService);
        bytes16 returnedId = _recurringCollector.accept(acceptedRca, signature);
        assertEq(returnedId, agreementId);
        assertEq(vm.getRecordedLogs().length, 0, "no event emitted on idempotent re-accept");
    }

    /// @notice Re-accepting an already-accepted RCA at the same hash must still succeed after
    /// the RCA's acceptance deadline has elapsed. The idempotent short-circuit runs before the
    /// deadline check so signature lifetime is not consumed — this is the path the SubgraphService
    /// relies on to rebind an agreement to a new allocation after the original acceptance window
    /// has closed.
    function test_Accept_Idempotent_AfterDeadline_SameHash(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes memory signature,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        // Warp past the RCA's deadline — a fresh accept would now revert with
        // RecurringCollectorAgreementDeadlineElapsed.
        vm.warp(uint256(acceptedRca.deadline) + 1);

        vm.recordLogs();
        vm.prank(acceptedRca.dataService);
        bytes16 returnedId = _recurringCollector.accept(acceptedRca, signature);
        assertEq(returnedId, agreementId, "returns the same agreementId");
        assertEq(vm.getRecordedLogs().length, 0, "no event emitted on idempotent re-accept after deadline");

        // Sanity: the collector-side agreement is still in Accepted state, unchanged by the no-op.
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(uint8(agreement.state), uint8(IRecurringCollector.AgreementState.Accepted));
    }

    /// @notice A fresh accept (no prior offer()) stores terms via _validateAndStoreTerms, which must
    /// emit OfferStored. AgreementAccepted follows. Both events observable in order.
    function test_Accept_EmitsOfferStored_WhenFreshTerms(FuzzyTestAccept calldata fuzzyTestAccept) public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        uint256 signerKey = boundKey(fuzzyTestAccept.unboundedSignerKey);
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, signerKey);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, signerKey);
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // OfferStored fires from _validateAndStoreTerms before _storeAgreement; AgreementAccepted
        // follows the state transition at the end of accept().
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.OfferStored(agreementId, rca.payer, OFFER_TYPE_NEW, rcaHash);
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementAccepted(
            rca.dataService,
            rca.payer,
            rca.serviceProvider,
            agreementId,
            rca.endsAt,
            rca.maxInitialTokens,
            rca.maxOngoingTokensPerSecond,
            rca.minSecondsPerCollection,
            rca.maxSecondsPerCollection
        );
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    /// @notice A second RCA sharing the same agreementId seed (payer, dataService, serviceProvider,
    /// deadline, nonce) but with different other fields — so different rcaHash — must not be
    /// accepted against an already-Accepted agreement. The idempotent short-circuit only fires on
    /// exact hash match; everything else must fall through to the state guard and revert. Proves
    /// the short-circuit can't be abused as an overwrite path even in an imagined 128-bit
    /// agreementId collision.
    function test_Accept_Revert_WhenDifferentHashSameAgreementId(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        // Snapshot the original hash before constructing the variant. `variant = acceptedRca` in
        // Solidity memory is a reference copy, so rebuild explicitly to vary one pricing field
        // while keeping the 5 agreementId-seed fields (payer, dataService, serviceProvider,
        // deadline, nonce) verbatim.
        bytes32 originalHash = _recurringCollector.hashRCA(acceptedRca);
        IRecurringCollector.RecurringCollectionAgreement memory variant = IRecurringCollector
            .RecurringCollectionAgreement({
                deadline: acceptedRca.deadline,
                endsAt: acceptedRca.endsAt,
                payer: acceptedRca.payer,
                dataService: acceptedRca.dataService,
                serviceProvider: acceptedRca.serviceProvider,
                maxInitialTokens: acceptedRca.maxInitialTokens + 1, // <-- vary
                maxOngoingTokensPerSecond: acceptedRca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: acceptedRca.minSecondsPerCollection,
                maxSecondsPerCollection: acceptedRca.maxSecondsPerCollection,
                conditions: acceptedRca.conditions,
                nonce: acceptedRca.nonce,
                metadata: acceptedRca.metadata
            });

        bytes32 variantHash = _recurringCollector.hashRCA(variant);
        assertTrue(originalHash != variantHash, "hashes must differ when any field differs");
        assertEq(
            _recurringCollector.generateAgreementId(
                variant.payer,
                variant.dataService,
                variant.serviceProvider,
                variant.deadline,
                variant.nonce
            ),
            agreementId,
            "same agreementId seed yields same id"
        );

        (, bytes memory variantSig) = _recurringCollectorHelper.generateSignedRCA(variant, signerKey);

        // Short-circuit doesn't fire (hash differs); falls through to _storeAgreement's state guard.
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
                agreementId,
                IRecurringCollector.AgreementState.Accepted
            )
        );
        vm.prank(acceptedRca.dataService);
        _recurringCollector.accept(variant, variantSig);

        // Post-revert sanity: storage reflects the original, not the variant.
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.activeTermsHash, originalHash, "activeTermsHash unchanged");
    }

    /// @notice After a cancellation, re-accepting the same RCA at the same hash must revert — the
    /// short-circuit only fires when state == Accepted, so a cancelled agreement falls through to
    /// the NotAccepted state guard. Proves cancelled is terminal and the short-circuit cannot
    /// resurrect it.
    function test_Accept_Revert_AfterCancellation_SameHash(FuzzyTestAccept calldata fuzzyTestAccept) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes memory signature,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestAccept);

        vm.prank(acceptedRca.dataService);
        _recurringCollector.cancel(agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        assertEq(
            uint8(_recurringCollector.getAgreement(agreementId).state),
            uint8(IRecurringCollector.AgreementState.CanceledByServiceProvider),
            "precondition: cancelled"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
                agreementId,
                IRecurringCollector.AgreementState.CanceledByServiceProvider
            )
        );
        vm.prank(acceptedRca.dataService);
        _recurringCollector.accept(acceptedRca, signature);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
