// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    SCOPE_PENDING,
    IAgreementCollector
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

/// @notice Round-trip hash verification: reconstruct offers from on-chain data and verify hashes.
/// Uses the offer() + accept() path so that offers are stored in rcaOffers/rcauOffers.
contract RecurringCollectorHashRoundTripTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    MockAgreementOwner internal _approver;

    function setUp() public override {
        super.setUp();
        _approver = new MockAgreementOwner();
    }

    // ==================== Helpers ====================

    function _makeRCA() internal returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return
            _recurringCollectorHelper.sensibleRCA(
                IRecurringCollector.RecurringCollectionAgreement({
                    deadline: uint64(block.timestamp + 1 hours),
                    endsAt: uint64(block.timestamp + 365 days),
                    payer: address(_approver),
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
    }

    function _offerRCA(IRecurringCollector.RecurringCollectionAgreement memory rca) internal returns (bytes16) {
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(address(_approver));
        return _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
    }

    function _offerAndAcceptRCA(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16) {
        bytes16 agreementId = _offerRCA(rca);
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
        return agreementId;
    }

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
                nonce: nonce,
                metadata: rca.metadata
            });
    }

    /// @notice Verify that getAgreementOfferAt round-trips: decode and rehash matches expected hash
    function _verifyOfferRoundTrip(bytes16 agreementId, uint256 index, bytes32 expectedHash) internal view {
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, index);
        require(offerData.length > 0, "Offer data should not be empty");

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

        assertEq(reconstructedHash, expectedHash, "Reconstructed hash must match expected hash");
    }

    // ==================== RCA round-trip (pending, before accept) ====================

    /// @notice Stored RCA offer round-trips before acceptance
    function test_HashRoundTrip_RCA_Pending() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA();
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        bytes16 agreementId = _offerRCA(rca);

        // Verify stored offer round-trips before acceptance
        _verifyOfferRoundTrip(agreementId, 0, rcaHash);

        // Verify reconstructed RCA fields match original
        (, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
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

    /// @notice Stored RCA offer persists after acceptance
    function test_HashRoundTrip_RCA_PersistsAfterAccept() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA();
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        bytes16 agreementId = _offerAndAcceptRCA(rca);

        // activeTermsHash matches
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.activeTermsHash, rcaHash, "activeTermsHash should match RCA hash");

        // Stored offer persists after accept
        _verifyOfferRoundTrip(agreementId, 0, rcaHash);
    }

    // ==================== RCAU round-trip (pending) ====================

    function test_HashRoundTrip_RCAU_Pending() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA();
        bytes16 agreementId = _offerAndAcceptRCA(rca);

        // Offer update (creates pending terms)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeUpdate(rca, agreementId, 1);
        bytes32 rcauHash = _recurringCollector.hashRCAU(rcau);
        vm.prank(address(_approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Verify pending update round-trips
        _verifyOfferRoundTrip(agreementId, 1, rcauHash);
    }

    // ==================== RCAU round-trip (accepted → persists) ====================

    function test_HashRoundTrip_RCAU_PersistsAfterUpdate() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA();
        bytes16 agreementId = _offerAndAcceptRCA(rca);

        // Offer and accept update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeUpdate(rca, agreementId, 1);
        bytes32 rcauHash = _recurringCollector.hashRCAU(rcau);
        vm.prank(address(_approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");

        // After update, activeTermsHash should be the RCAU hash
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.activeTermsHash, rcauHash, "activeTermsHash should be RCAU hash after update");

        // After update, RCAU becomes the active version (VERSION_CURRENT = 0)
        _verifyOfferRoundTrip(agreementId, 0, rcauHash);
    }

    // ==================== Cancel pending, active stays ====================

    function test_HashRoundTrip_CancelPending_ActiveStays() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA();
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        bytes16 agreementId = _offerAndAcceptRCA(rca);

        // Offer update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeUpdate(rca, agreementId, 1);
        bytes32 rcauHash = _recurringCollector.hashRCAU(rcau);
        vm.prank(address(_approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Cancel the pending update using its hash
        vm.prank(address(_approver));
        _recurringCollector.cancel(agreementId, rcauHash, SCOPE_PENDING);

        // RCA offer persists after accept
        _verifyOfferRoundTrip(agreementId, 0, rcaHash);

        // Pending update should be gone
        (, bytes memory pendingData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        assertEq(pendingData.length, 0, "Pending update should be cleared after cancel");

        // activeTermsHash should still be the RCA hash
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.activeTermsHash, rcaHash, "activeTermsHash should still be RCA hash");
    }

    // ==================== Pre-acceptance overwrite ====================

    function test_HashRoundTrip_RCAU_PreAcceptOverwrite() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA();
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Offer RCA
        vm.prank(address(_approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Overwrite with RCAU before acceptance
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeUpdate(rca, agreementId, 1);
        bytes32 rcauHash = _recurringCollector.hashRCAU(rcau);
        vm.prank(address(_approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Update offer should be stored at index 1 and round-trip
        _verifyOfferRoundTrip(agreementId, 1, rcauHash);

        // Original RCA offer should still be at index 0
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        _verifyOfferRoundTrip(agreementId, 0, rcaHash);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
