// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    UPDATE,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    WITH_NOTICE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

/// @notice Round-trip hash verification: reconstruct offers from on-chain data and verify hashes.
contract RecurringCollectorHashRoundTripTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== RCA round-trip ====================

    function test_HashRoundTrip_RCA(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        _verifyVersionHash(agreementId, 0);

        // Also verify the reconstructed RCA matches the original
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        assertEq(offerType, OFFER_TYPE_NEW, "Offer type should be NEW");
        IRecurringCollector.RecurringCollectionAgreement memory reconstructed = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreement)
        );
        assertEq(reconstructed.payer, rca.payer, "payer mismatch");
        assertEq(reconstructed.dataService, rca.dataService, "dataService mismatch");
        assertEq(reconstructed.serviceProvider, rca.serviceProvider, "serviceProvider mismatch");
        assertEq(reconstructed.nonce, rca.nonce, "nonce mismatch");
        assertEq(reconstructed.endsAt, rca.endsAt, "endsAt mismatch");
    }

    // ==================== RCAU round-trip (pending) ====================

    function test_HashRoundTrip_RCAU_Pending(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Offer update (creates pending terms)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeUpdate(rca, agreementId, 1);
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Verify pending version hash round-trips
        _verifyVersionHash(agreementId, 1);

        // Active version should still round-trip
        _verifyVersionHash(agreementId, 0);
    }

    // ==================== RCAU round-trip (accepted) ====================

    function test_HashRoundTrip_RCAU_Accepted(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Offer and accept update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeUpdate(rca, agreementId, 1);
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        // Active version is now from RCAU — verify round-trip
        _verifyVersionHash(agreementId, 0);

        // Verify offer type is UPDATE
        (uint8 offerType, ) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        assertEq(offerType, OFFER_TYPE_UPDATE, "Active offer type should be UPDATE after accept");
    }

    // ==================== RCAU pre-acceptance overwrite ====================

    function test_HashRoundTrip_RCAU_PreAcceptOverwrite(FuzzyTestAccept calldata fuzzy) public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(fuzzy.rca);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Offer RCA
        vm.prank(rca.payer);
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Overwrite with RCAU before acceptance
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeUpdate(rca, agreementId, 1);
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Active terms are from RCAU now — verify hash round-trip
        _verifyVersionHash(agreementId, 0);

        (uint8 offerType, ) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        assertEq(offerType, OFFER_TYPE_UPDATE, "Active offer type should be UPDATE after pre-accept overwrite");
    }

    // ==================== Cancel pending, active stays RCA ====================

    function test_HashRoundTrip_CancelPending_ActiveStaysRCA(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Offer update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeUpdate(rca, agreementId, 1);
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Cancel the pending update
        bytes32 pendingCancelHash = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        vm.prank(rca.payer);
        _recurringCollector.cancel(agreementId, pendingCancelHash, 0);

        // Active terms should still be from RCA and round-trip
        _verifyVersionHash(agreementId, 0);

        (uint8 offerType, ) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        assertEq(offerType, OFFER_TYPE_NEW, "Active offer type should still be NEW after cancel pending");
    }

    // ==================== WITH_NOTICE deadline=0 round-trip ====================

    function test_HashRoundTrip_WithNotice_DeadlineZero(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Offer update with WITH_NOTICE and deadline=0
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeUpdate(rca, agreementId, 1);
        rcau.deadline = 0; // auto-compute notice cutoff
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), WITH_NOTICE);

        // Pending terms should round-trip with the ORIGINAL deadline (0)
        _verifyVersionHash(agreementId, 1);

        // Verify the stored deadline is 0 (not the derived notice cutoff)
        (, bytes memory pendingData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory storedRcau = abi.decode(
            pendingData,
            (IRecurringCollector.RecurringCollectionAgreementUpdate)
        );
        assertEq(storedRcau.deadline, 0, "Stored deadline should be original (0), not derived cutoff");
    }

    // ==================== Helpers ====================

    /// @notice Verify that getAgreementOfferAt round-trips to the stored version hash
    function _verifyVersionHash(bytes16 agreementId, uint256 index) internal view {
        bytes32 storedHash = _recurringCollector.getAgreementVersionAt(agreementId, index).versionHash;
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, index);

        bytes32 reconstructedHash;
        if (offerType == OFFER_TYPE_NEW) {
            IRecurringCollector.RecurringCollectionAgreement memory rca = abi.decode(
                offerData,
                (IRecurringCollector.RecurringCollectionAgreement)
            );
            reconstructedHash = _recurringCollector.hashRCA(rca);
        } else {
            IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = abi.decode(
                offerData,
                (IRecurringCollector.RecurringCollectionAgreementUpdate)
            );
            reconstructedHash = _recurringCollector.hashRCAU(rcau);
        }

        assertEq(reconstructedHash, storedHash, "Reconstructed hash must match stored version hash");
    }

    /// @notice Build a sensible RCAU from an accepted RCA
    function _makeUpdate(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        bytes16 agreementId,
        uint32 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        return
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 30 days),
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: rca.conditions,
                minSecondsPayerCancellationNotice: rca.minSecondsPayerCancellationNotice,
                nonce: nonce,
                metadata: rca.metadata
            });
    }

    /* solhint-enable graph/func-name-mixedcase */
}
