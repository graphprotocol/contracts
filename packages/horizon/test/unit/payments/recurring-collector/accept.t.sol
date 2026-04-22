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

    /* solhint-enable graph/func-name-mixedcase */
}
