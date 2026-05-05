// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import {
    IAgreementCollector,
    OFFER_TYPE_NONE,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    SCOPE_PENDING,
    VERSION_CURRENT,
    VERSION_NEXT
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

/// @notice Targeted coverage for the hash-keyed offer storage refactor.
contract RecurringCollectorOfferStorageLifecycleTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function _makeRca(address payer) internal returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return
            _recurringCollectorHelper.sensibleRCA(
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
    }

    function _makeRcau(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint32 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        return
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: rca.endsAt + 30 days,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond * 2,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: 0,
                nonce: nonce,
                metadata: ""
            });
    }

    // ──────────────────────────────────────────────────────────────────────
    // Hash-keyed offer storage lifecycle
    // ──────────────────────────────────────────────────────────────────────

    /// @notice offer(RCA) creates a storage entry at the EIP-712 hash and emits OfferStored.
    function test_OfferNew_StoresEntryAtHash_EmitsEvent() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.OfferStored(agreementId, rca.payer, OFFER_TYPE_NEW, rcaHash);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(
            agreementId,
            VERSION_CURRENT
        );
        assertEq(offerType, OFFER_TYPE_NEW, "stored entry at rcaHash");
        assertTrue(offerData.length > 0, "stored data non-empty");

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.activeTermsHash, rcaHash, "agreement.activeTermsHash points at offer hash");
        assertEq(agreement.pendingTermsHash, bytes32(0), "no pending before update");
    }

    /// @notice Re-offering the identical RCA is idempotent — no second OfferStored event, storage unchanged.
    function test_OfferNew_Idempotent_WhenResubmittedSameHash() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        // Second call with the same RCA must not emit OfferStored again
        vm.recordLogs();
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 offerStoredSig = keccak256("OfferStored(bytes16,address,uint8,bytes32)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0) {
                assertFalse(logs[i].topics[0] == offerStoredSig, "no duplicate OfferStored on re-offer");
            }
        }
    }

    /// @notice Accepting a stored offer preserves the offer entry — getAgreementOfferAt still returns it.
    function test_OfferNew_EntryPersistsAcrossAccept() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(
            agreementId,
            VERSION_CURRENT
        );
        assertEq(offerType, OFFER_TYPE_NEW, "accept does not delete the RCA offer entry");
        assertTrue(offerData.length > 0, "accept preserves stored data");
    }

    /// @notice A successful update deletes the prior active offer from storage; the new RCAU terms
    /// become VERSION_CURRENT (OFFER_TYPE_UPDATE) and the pending slot clears.
    function test_Update_DeletesPriorActiveOffer_PromotesRcauToCurrent() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRcau(agreementId, rca, 1);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
        bytes32 rcauHash = _recurringCollector.hashRCAU(rcau);

        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");

        // Prior active (RCA) offer deleted from storage — since activeTermsHash now points at rcauHash,
        // a fresh agreementId derived with mismatched hash should return empty at the rcaHash slot.
        // We assert via getAgreementDetails: rcaHash is no longer a current version.
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.activeTermsHash, rcauHash, "activeTermsHash = rcauHash after update");
        assertEq(agreement.pendingTermsHash, bytes32(0), "pendingTermsHash cleared after update");

        (uint8 currentType, ) = _recurringCollector.getAgreementOfferAt(agreementId, VERSION_CURRENT);
        assertEq(currentType, OFFER_TYPE_UPDATE, "current offer type now OFFER_TYPE_UPDATE");

        (uint8 nextType, bytes memory nextData) = _recurringCollector.getAgreementOfferAt(agreementId, VERSION_NEXT);
        assertEq(nextType, OFFER_TYPE_NONE, "no pending offer after update");
        assertEq(nextData.length, 0, "pending data empty after update");

        // Old RCA hash is no longer referenced; since getAgreementOfferAt only resolves via version
        // indices, confirm indirectly that no version maps to rcaHash.
        bytes32 currentHash = _recurringCollector.getAgreementDetails(agreementId, VERSION_CURRENT).versionHash;
        assertTrue(currentHash != rcaHash, "no version maps to old rcaHash");
    }

    /// @notice Offering a different pending update replaces the prior pending RCAU — the replaced
    /// entry is deleted from storage.
    function test_OfferUpdate_ReplacesPriorPending_DeletesReplaced() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcauA = _makeRcau(agreementId, rca, 1);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcauA), 0);
        bytes32 rcauAHash = _recurringCollector.hashRCAU(rcauA);

        // Second update with different terms (different maxInitialTokens) replaces the pending RCAU
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcauB = rcauA;
        rcauB.maxInitialTokens = rcauA.maxInitialTokens + 1;
        bytes32 rcauBHash = _recurringCollector.hashRCAU(rcauB);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcauB), 0);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.pendingTermsHash, rcauBHash, "pending now points to rcauB");

        // Replaced rcauA entry no longer referenced by any version — VERSION_NEXT is now rcauB.
        bytes32 pendingHash = _recurringCollector.getAgreementDetails(agreementId, VERSION_NEXT).versionHash;
        assertEq(pendingHash, rcauBHash, "VERSION_NEXT resolves to rcauB");
        assertTrue(pendingHash != rcauAHash, "old rcauA no longer reachable via version index");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Pre-acceptance cancel cascades deletion of any pending RCAU
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Pre-acceptance cancel of the RCA under SCOPE_PENDING deletes BOTH the RCA offer
    /// and any pending RCAU offer. After cascade, both slots are empty.
    function test_CancelPreAcceptanceRca_CascadesDeleteRcau() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory rcaDetails = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        bytes16 agreementId = rcaDetails.agreementId;

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRcau(agreementId, rca, 1);
        bytes32 rcauHash = _recurringCollector.hashRCAU(rcau);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Sanity: both slots populated before the cancel
        (uint8 preCurrentType, ) = _recurringCollector.getAgreementOfferAt(agreementId, VERSION_CURRENT);
        (uint8 preNextType, ) = _recurringCollector.getAgreementOfferAt(agreementId, VERSION_NEXT);
        assertEq(preCurrentType, OFFER_TYPE_NEW, "RCA stored before cancel");
        assertEq(preNextType, OFFER_TYPE_UPDATE, "RCAU stored before cancel");

        // Cancel the pre-acceptance RCA — one OfferCancelled event, both slots cleared
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.OfferCancelled(address(approver), agreementId, rcaHash);
        vm.prank(address(approver));
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_PENDING);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.activeTermsHash, bytes32(0), "activeTermsHash cleared");
        assertEq(agreement.pendingTermsHash, bytes32(0), "pendingTermsHash cascade-cleared");

        (uint8 currentType, bytes memory currentData) = _recurringCollector.getAgreementOfferAt(
            agreementId,
            VERSION_CURRENT
        );
        assertEq(currentType, OFFER_TYPE_NONE, "RCA offer deleted");
        assertEq(currentData.length, 0, "RCA data empty");

        (uint8 nextType, bytes memory nextData) = _recurringCollector.getAgreementOfferAt(agreementId, VERSION_NEXT);
        assertEq(nextType, OFFER_TYPE_NONE, "RCAU offer cascade-deleted");
        assertEq(nextData.length, 0, "RCAU data empty");

        // The original rcauHash stored-offer entry is no longer referenced. No version hash
        // resolves to it — confirmed above — so the cleanup is complete for view purposes.
        rcauHash; // silence unused warning; kept for clarity in the narrative
    }

    /// @notice After a pre-acceptance cascade delete, a follow-up cancel targeting the orphan RCAU
    /// hash must NOT revert: _requirePayerIfExists short-circuits because agreement.payer was
    /// zeroed when activeTermsHash was cleared — but the agreement struct still exists. The cancel
    /// is therefore a no-op targeting already-empty state.
    function test_CancelPreAcceptanceRca_SubsequentRcauCancel_DoesNotRevert() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory rcaDetails = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        bytes16 agreementId = rcaDetails.agreementId;

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRcau(agreementId, rca, 1);
        bytes32 rcauHash = _recurringCollector.hashRCAU(rcau);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Cancel the RCA — cascades the RCAU
        vm.prank(address(approver));
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_PENDING);

        // The approver can still cancel(rcauHash) without reverting — the payer slot on the
        // agreement is still set (clearing is by *termsHash*, not payer field), so the call
        // enters the pending-hash branch, observes pendingTermsHash == 0, and exits silently.
        vm.prank(address(approver));
        _recurringCollector.cancel(agreementId, rcauHash, SCOPE_PENDING);
    }

    /// @notice Pre-acceptance cancel with no pending RCAU still deletes the RCA offer and
    /// emits a single OfferCancelled.
    function test_CancelPreAcceptanceRca_NoPending_OnlyDeletesRca() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        bytes16 agreementId = details.agreementId;

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.OfferCancelled(address(approver), agreementId, rcaHash);
        vm.prank(address(approver));
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_PENDING);

        (uint8 currentType, ) = _recurringCollector.getAgreementOfferAt(agreementId, VERSION_CURRENT);
        assertEq(currentType, OFFER_TYPE_NONE, "RCA offer deleted");
        assertEq(_recurringCollector.getAgreement(agreementId).activeTermsHash, bytes32(0), "activeTermsHash cleared");
    }

    // ──────────────────────────────────────────────────────────────────────
    // OFFER_TYPE_NONE sentinel
    // ──────────────────────────────────────────────────────────────────────

    /// @notice The offer-type sentinel values: OFFER_TYPE_NONE must be 0 so callers can distinguish
    /// "no offer stored" (default mapping value) from OFFER_TYPE_NEW / OFFER_TYPE_UPDATE.
    function test_OfferTypeConstants_NoneIsZero_OthersNonZero() public pure {
        assertEq(OFFER_TYPE_NONE, uint8(0), "OFFER_TYPE_NONE must be 0");
        assertTrue(OFFER_TYPE_NEW != OFFER_TYPE_NONE, "OFFER_TYPE_NEW distinct from NONE");
        assertTrue(OFFER_TYPE_UPDATE != OFFER_TYPE_NONE, "OFFER_TYPE_UPDATE distinct from NONE");
        assertTrue(OFFER_TYPE_NEW != OFFER_TYPE_UPDATE, "NEW and UPDATE distinct");
    }

    /// @notice offer() rejects OFFER_TYPE_NONE as an offer type — the sentinel cannot be used to
    /// create a stored offer, so getAgreementOfferAt's OFFER_TYPE_NONE return unambiguously means
    /// "no offer stored".
    function test_Offer_Revert_WhenOfferTypeIsNone() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        bytes memory data = abi.encode(rca);

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorInvalidCollectData.selector, data)
        );
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NONE, data, 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
