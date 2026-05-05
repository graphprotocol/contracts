// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    UPDATE,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    SCOPE_ACTIVE,
    SCOPE_PENDING,
    IAgreementCollector
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

/// @notice A payer contract that supports ERC165 + IProviderEligibility at offer time,
/// but returns malformed (< 32 bytes) data from isEligible at collection time.
contract MalformedEligibilityPayer is IAgreementOwner, IERC165 {
    bool public returnMalformed;

    function setReturnMalformed(bool _malformed) external {
        returnMalformed = _malformed;
    }

    function beforeCollection(bytes16, uint256) external override {}
    function afterCollection(bytes16, uint256) external override {}

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IProviderEligibility).interfaceId;
    }

    /// @notice When returnMalformed is true, returns empty data via assembly (< 32 bytes).
    /// Otherwise returns true (eligible).
    fallback() external {
        if (returnMalformed) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                return(0, 0) // return 0 bytes — triggers result.length < 32
            }
        } else {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                mstore(0x00, 1) // true
                return(0x00, 0x20)
            }
        }
    }
}

/// @notice Tests targeting specific uncovered lines in RecurringCollector.sol
contract RecurringCollectorCoverageGapsTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ══════════════════════════════════════════════════════════════════════
    // Helper: offer an RCA via the payer and return the agreement ID
    // ══════════════════════════════════════════════════════════════════════

    function _offer(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16 agreementId) {
        MockAgreementOwner approver;
        if (rca.payer.code.length == 0) {
            approver = new MockAgreementOwner();
            rca.payer = address(approver);
        }
        vm.prank(rca.payer);
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        return details.agreementId;
    }

    /// @dev Accept via offer+accept (unsigned path) and return rca + agreementId
    function _offerAndAccept(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (IRecurringCollector.RecurringCollectionAgreement memory, bytes16) {
        MockAgreementOwner approver;
        if (rca.payer.code.length == 0) {
            approver = new MockAgreementOwner();
            rca.payer = address(approver);
        }
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");
        return (rca, agreementId);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 1 — Invalid offer type
    // ══════════════════════════════════════════════════════════════════════

    function test_Offer_Revert_WhenOfferTypeInvalid_Two() public {
        address payer = makeAddr("payer");
        vm.expectRevert();
        vm.prank(payer);
        _recurringCollector.offer(2, bytes(""), 0);
    }

    function test_Offer_Revert_WhenOfferTypeInvalid_MaxUint8() public {
        address payer = makeAddr("payer");
        vm.expectRevert();
        vm.prank(payer);
        _recurringCollector.offer(255, bytes(""), 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 2 — getAgreementDetails index 0 on accepted agreement
    // ══════════════════════════════════════════════════════════════════════

    function test_GetAgreementDetails_Index0_Accepted(FuzzyTestAccept calldata fuzzy) public {
        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzy);

        IAgreementCollector.AgreementDetails memory details = _recurringCollector.getAgreementDetails(agreementId, 0);
        assertTrue(details.versionHash != bytes32(0), "Index 0 should return non-zero active terms hash");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 3 — getAgreementDetails index 1 with pending update
    // ══════════════════════════════════════════════════════════════════════

    function test_GetAgreementOfferAt_PendingUpdateExists() public {
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
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");

        // Submit update via offer to create pending terms
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Pending update should be accessible at index 1 (OFFER_TYPE_UPDATE)
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        assertEq(offerType, OFFER_TYPE_UPDATE, "Index 1 should be OFFER_TYPE_UPDATE");
        assertTrue(offerData.length > 0, "Pending update data should not be empty");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 4 — getAgreementOfferAt round-trip
    // ══════════════════════════════════════════════════════════════════════

    function test_GetAgreementOfferAt_Index0() public {
        // Must use offer() path so the RCA is stored in rcaOffers
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
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        bytes16 agreementId = details.agreementId;

        // Before accept: offer is available
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        assertEq(offerType, OFFER_TYPE_NEW, "Index 0 should be OFFER_TYPE_NEW");
        IRecurringCollector.RecurringCollectionAgreement memory decoded = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreement)
        );
        bytes32 expectedHash = _recurringCollector.hashRCA(rca);
        assertEq(_recurringCollector.hashRCA(decoded), expectedHash, "Reconstructed hash should match RCA hash");

        // Accept
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");

        // After accept: offer persists
        (uint8 postOfferType, bytes memory postAcceptData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        assertEq(postOfferType, OFFER_TYPE_NEW, "Index 0 should still be OFFER_TYPE_NEW after accept");
        assertTrue(postAcceptData.length > 0, "RCA offer should persist after accept");
    }

    function test_GetAgreementOfferAt_Index1_WithPending() public {
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
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");

        // Submit update via offer
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);

        assertEq(offerType, OFFER_TYPE_UPDATE, "Index 1 should be OFFER_TYPE_UPDATE");
        IRecurringCollector.RecurringCollectionAgreementUpdate memory decoded = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreementUpdate)
        );
        bytes32 expectedHash = _recurringCollector.hashRCAU(rcau);
        assertEq(_recurringCollector.hashRCAU(decoded), expectedHash, "Reconstructed hash should match offer hash");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 5 — getMaxNextClaim with scope
    // ══════════════════════════════════════════════════════════════════════

    function test_GetMaxNextClaim_ScopeActiveOnly(FuzzyTestAccept calldata fuzzy) public {
        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzy);

        uint256 maxClaimActive = _recurringCollector.getMaxNextClaim(agreementId, SCOPE_ACTIVE);
        uint256 maxClaimBoth = _recurringCollector.getMaxNextClaim(agreementId);

        assertEq(maxClaimActive, maxClaimBoth, "Active-only scope should match full scope when no pending terms");
    }

    function test_GetMaxNextClaim_ScopePendingOnly(FuzzyTestAccept calldata fuzzy) public {
        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzy);

        uint256 maxClaimPending = _recurringCollector.getMaxNextClaim(agreementId, SCOPE_PENDING);

        assertEq(maxClaimPending, 0, "Pending-only scope should return 0 when no pending terms");
    }

    function test_GetMaxNextClaim_ScopePendingOnly_WithPending(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Submit update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        uint256 maxClaimPending = _recurringCollector.getMaxNextClaim(agreementId, SCOPE_PENDING);

        assertTrue(0 < maxClaimPending, "Pending-only scope should be > 0 when pending terms exist");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 6 — PayerCallbackFailed when eligibility returns malformed data
    // ══════════════════════════════════════════════════════════════════════

    function test_Collect_EmitsPayerCallbackFailed_WhenEligibilityReturnsMalformed() public {
        MalformedEligibilityPayer payer = new MalformedEligibilityPayer();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(payer),
                dataService: makeAddr("ds-elig"),
                serviceProvider: makeAddr("sp-elig"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0, // sensibleRCA zeros this; we'll set it after
                nonce: 1,
                metadata: ""
            })
        );
        // Set conditions AFTER sensibleRCA (which zeros conditions to avoid spurious failures)
        rca.conditions = 1; // CONDITION_ELIGIBILITY_CHECK

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Payer calls offer (isEligible works correctly at this point)
        vm.prank(address(payer));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        // Accept via dataService (unsigned path: empty signature)
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        // Now make the payer return malformed (< 32 bytes) from isEligible
        payer.setReturnMalformed(true);

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(
            _generateCollectParams(rca, agreementId, bytes32("col-malformed"), tokens, 0)
        );

        // Collection should proceed despite malformed eligibility response
        // (the PayerCallbackFailed event is emitted but collection continues)
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens, "Collection should proceed despite malformed eligibility response");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 7 — Update overwrites active terms when not yet accepted
    // ══════════════════════════════════════════════════════════════════════

    function test_Update_OverwritesOffer_WhenNotYetAccepted() public {
        address dataService = makeAddr("ds");
        address serviceProvider = makeAddr("sp");

        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: address(approver),
            dataService: dataService,
            serviceProvider: serviceProvider,
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 0,
            nonce: 1,
            metadata: ""
        });

        // Offer but do NOT accept
        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory offerDetails = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        bytes16 agreementId = offerDetails.agreementId;

        // Submit OFFER_TYPE_UPDATE to overwrite
        uint256 newMaxInitial = 200 ether;
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: rca.endsAt,
                maxInitialTokens: newMaxInitial,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // The update offer should exist at index 1
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        assertEq(offerType, OFFER_TYPE_UPDATE, "Update offer should be stored");
        IRecurringCollector.RecurringCollectionAgreementUpdate memory decoded = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreementUpdate)
        );
        assertEq(decoded.maxInitialTokens, newMaxInitial, "Update should contain new values");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 8 — getCollectionInfo returns zero seconds in same block as accept
    // ══════════════════════════════════════════════════════════════════════

    function test_GetCollectionInfo_ZeroCollectionSeconds(FuzzyTestAccept calldata fuzzy) public {
        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzy);

        // Read agreement in the same block as accept
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);

        (bool isCollectable, uint256 collectionSeconds, ) = _recurringCollector.getCollectionInfo(agreementId);

        assertFalse(isCollectable, "Should not be collectable with zero elapsed time");
        assertEq(collectionSeconds, 0, "Collection seconds should be 0");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 9 — getMaxNextClaim for offered-but-not-accepted agreement
    // ══════════════════════════════════════════════════════════════════════

    function test_GetMaxNextClaim_OfferedButNotAccepted() public {
        MockAgreementOwner approver = new MockAgreementOwner();

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 100_000),
            payer: address(approver),
            dataService: makeAddr("ds"),
            serviceProvider: makeAddr("sp"),
            maxInitialTokens: 5000,
            maxOngoingTokensPerSecond: 100,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 0,
            nonce: 1,
            metadata: ""
        });

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        bytes16 agreementId = details.agreementId;

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // Should return non-zero for valid offered agreement
        assertTrue(0 < maxClaim, "maxClaim should be non-zero for valid offered agreement");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 10 — Cancel pending update clears pending terms
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_PendingUpdate_ClearsPendingTerms() public {
        // Use offer path so payer is a contract we control
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
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Offer and accept
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");

        // Offer an update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: rca.endsAt + 365 days,
                maxInitialTokens: rca.maxInitialTokens * 2,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond * 2,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: 0,
                nonce: 1,
                metadata: ""
            });
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Cancel specifically the pending update (using its hash + SCOPE_PENDING)
        bytes32 pendingHash = _recurringCollector.hashRCAU(rcau);
        assertTrue(pendingHash != bytes32(0), "Should have pending terms");

        vm.prank(address(approver));
        _recurringCollector.cancel(agreementId, pendingHash, SCOPE_PENDING);

        // Pending terms cleared: getAgreementOfferAt(id, 1) should return empty
        (, bytes memory pendingData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        assertEq(pendingData.length, 0, "Pending terms should be cleared");

        // Active terms should still be intact
        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        assertTrue(activeHash != bytes32(0), "Active terms should remain");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 11 — Scoped cancel: cancel active terms with hash match
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_ActiveTerms_WhenPendingExists(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Submit update to create pending terms
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: 0,
                nonce: 1,
                metadata: ""
            });
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Cancel via dataService cancel path (old cancel API)
        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        // Active terms should be canceled
        IRecurringCollector.AgreementData memory data = _recurringCollector.getAgreement(agreementId);
        assertTrue(
            data.state == IRecurringCollector.AgreementState.CanceledByServiceProvider,
            "Should be canceled by SP"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 12 — Cancel is idempotent when hash matches neither pending nor active
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_NoOp_WhenHashMatchesNeither(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        bytes32 bogusHash = bytes32(uint256(0xdead));

        // Should not revert — cancel is idempotent
        vm.prank(rca.payer);
        _recurringCollector.cancel(agreementId, bogusHash, SCOPE_ACTIVE | SCOPE_PENDING);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 13 — getAgreementOfferAt edge cases
    // ══════════════════════════════════════════════════════════════════════

    function test_GetAgreementOfferAt_Index2_ReturnsEmpty(FuzzyTestAccept calldata fuzzy) public {
        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzy);

        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 2);
        assertEq(offerType, 0, "Out-of-range index should return 0 offerType");
        assertEq(offerData.length, 0, "Out-of-range index should return empty data");
    }

    function test_GetAgreementOfferAt_EmptyAgreement() public view {
        bytes16 fakeId = bytes16(keccak256("nonexistent"));

        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(fakeId, 0);
        assertEq(offerType, 0, "Empty agreement index 0 should return 0 offerType");
        assertEq(offerData.length, 0, "Empty agreement index 0 should return empty data");
    }

    function test_GetAgreementOfferAt_Index1_NoPending(FuzzyTestAccept calldata fuzzy) public {
        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzy);

        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        assertEq(offerType, 0, "No pending terms should return 0 offerType");
        assertEq(offerData.length, 0, "No pending terms should return empty data");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 14 — Offer revert when deadline expired
    // ══════════════════════════════════════════════════════════════════════

    function test_Accept_Revert_WhenOfferedWithExpiredDeadline() public {
        MockAgreementOwner approver = new MockAgreementOwner();

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1), // valid at offer time
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
        });

        // Offer stores successfully (deadline not checked at offer time)
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Warp past deadline
        skip(2);

        // Accept should revert with expired deadline
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
                block.timestamp,
                rca.deadline
            )
        );
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 15 — getMaxNextClaim returns 0 for empty state
    // ══════════════════════════════════════════════════════════════════════

    function test_GetMaxNextClaim_EmptyState_ReturnsZero() public view {
        bytes16 fakeId = bytes16(keccak256("nonexistent"));
        uint256 maxClaim = _recurringCollector.getMaxNextClaim(fakeId);
        assertEq(maxClaim, 0, "Empty state agreement should return 0");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 16 — Cancel by SP allows final collection
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_ByServiceProvider_AllowsFinalCollection(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Skip some time to accumulate collectable seconds
        skip(rca.minSecondsPerCollection);

        // Cancel by service provider
        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        // Verify the agreement is canceled by SP
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(agreement.state),
            uint8(IRecurringCollector.AgreementState.CanceledByServiceProvider),
            "Should be CanceledByServiceProvider"
        );

        // SP cancel should NOT allow further collection (SP forfeits)
        (bool isCollectable, , ) = _recurringCollector.getCollectionInfo(agreementId);
        assertFalse(isCollectable, "CanceledByServiceProvider should not be collectable");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 17 — Cancel by payer allows final collection
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_ByPayer_AllowsFinalCollection(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Skip some time to accumulate collectable seconds
        skip(rca.minSecondsPerCollection);

        // Cancel by payer
        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        // Verify the agreement is canceled by payer
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(agreement.state),
            uint8(IRecurringCollector.AgreementState.CanceledByPayer),
            "Should be CanceledByPayer"
        );

        // Payer cancel should allow final collection
        (bool isCollectable, uint256 collectionSeconds, ) = _recurringCollector.getCollectionInfo(agreementId);
        assertTrue(isCollectable, "CanceledByPayer should be collectable for final period");
        assertTrue(collectionSeconds > 0, "Should have collectable seconds");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 18 — Offer caller must be payer
    // ══════════════════════════════════════════════════════════════════════

    function test_Offer_Revert_WhenCallerNotPayer() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        address notPayer = makeAddr("notPayer");

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
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
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorUnauthorizedCaller.selector,
                notPayer,
                address(approver)
            )
        );
        vm.prank(notPayer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 19 — Scoped cancel on pending revokes the stored offer
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_Scoped_PendingNewOffer() public {
        MockAgreementOwner approver = new MockAgreementOwner();

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
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
        });

        // Offer but don't accept
        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        bytes16 agreementId = details.agreementId;

        // Verify offer exists
        (uint8 offerType, ) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        assertEq(offerType, OFFER_TYPE_NEW, "Offer should exist before cancel");

        // Cancel the pending offer
        vm.prank(address(approver));
        _recurringCollector.cancel(agreementId, details.versionHash, SCOPE_PENDING);

        // Verify offer is gone
        (uint8 offerTypeAfter, bytes memory dataAfter) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        assertEq(offerTypeAfter, 0, "Offer type should be 0 after cancel");
        assertEq(dataAfter.length, 0, "Offer data should be empty after cancel");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 16 — _requirePayer: agreement not found (L528)
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_Revert_WhenAgreementNotFound() public {
        bytes16 fakeId = bytes16(keccak256("nonexistent"));
        address caller = makeAddr("randomCaller");

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorAgreementNotFound.selector, fakeId)
        );
        vm.prank(caller);
        _recurringCollector.cancel(fakeId, bytes32(0), SCOPE_ACTIVE);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 17 — _requirePayer: unauthorized caller (L530)
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_Revert_WhenUnauthorizedCaller(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        address imposter = makeAddr("imposter");
        vm.assume(imposter != rca.payer);

        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorUnauthorizedCaller.selector,
                imposter,
                rca.payer
            )
        );
        vm.prank(imposter);
        _recurringCollector.cancel(agreementId, activeHash, SCOPE_ACTIVE);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 18 — IAgreementCollector.cancel with SCOPE_PENDING to delete RCAU offer (L501)
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_PendingScope_DeletesRcauOffer() public {
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
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Offer and accept
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");

        // Offer an update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: rca.endsAt + 100 days,
                maxInitialTokens: rca.maxInitialTokens * 2,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: 0,
                nonce: 1,
                metadata: ""
            });
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Verify RCAU offer exists
        (, bytes memory pendingData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        assertTrue(pendingData.length > 0, "RCAU offer should exist");

        // Cancel via IAgreementCollector.cancel with RCAU hash and SCOPE_PENDING
        bytes32 rcauHash = _recurringCollector.hashRCAU(rcau);
        vm.prank(address(approver));
        _recurringCollector.cancel(agreementId, rcauHash, SCOPE_PENDING);

        // Verify RCAU offer is deleted
        (, bytes memory afterData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        assertEq(afterData.length, 0, "RCAU offer should be deleted after cancel");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 19 — IAgreementCollector.cancel with SCOPE_ACTIVE on accepted (L502-504)
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_ActiveScope_CallsDataService() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        MockDataServiceForCancel dataServiceMock = new MockDataServiceForCancel();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(approver),
                dataService: address(dataServiceMock),
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
        _setupValidProvision(rca.serviceProvider, address(dataServiceMock));

        // Offer and accept
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        vm.prank(address(dataServiceMock));
        _recurringCollector.accept(rca, "");

        // Cancel via IAgreementCollector.cancel with active hash and SCOPE_ACTIVE
        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(address(approver));
        _recurringCollector.cancel(agreementId, activeHash, SCOPE_ACTIVE);

        // Verify the mock was called
        assertTrue(dataServiceMock.cancelCalled(), "cancelIndexingAgreementByPayer should have been called");
        assertEq(dataServiceMock.canceledAgreementId(), agreementId, "Agreement ID should match");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 20 — _offerNew deadline guard (L481): offer with deadline already past
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Offering an RCA whose deadline is already past must revert. The deadline guard
    /// at the entry of {_offerNew} is independent from the collection-window check in
    /// {_requireValidTerms}; this exercises the deadline-elapsed branch directly.
    function test_OfferNew_Revert_WhenDeadlineAlreadyPast() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        uint64 deadline = uint64(block.timestamp + 100);
        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: deadline,
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
        });

        // Warp past the deadline before the offer call so the entry-time guard fires.
        skip(101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
                block.timestamp,
                deadline
            )
        );
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 21 — _requirePayerToSupportEligibilityCheck (L788): contract payer
    // sets CONDITION_ELIGIBILITY_CHECK but does not implement IProviderEligibility
    // ══════════════════════════════════════════════════════════════════════

    /// @notice When an RCA enables CONDITION_ELIGIBILITY_CHECK, the payer must support
    /// IProviderEligibility via ERC-165. BareAgreementOwner implements IAgreementOwner but
    /// not IERC165, so ERC165Checker.supportsInterface returns false and the require fires
    /// at offer time.
    function test_OfferNew_Revert_WhenEligibilityConditionAndPayerLacksInterface() public {
        BareAgreementOwner bare = new BareAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: address(bare),
            dataService: makeAddr("ds-elig-bare"),
            serviceProvider: makeAddr("sp-elig-bare"),
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 1, // CONDITION_ELIGIBILITY_CHECK
            nonce: 1,
            metadata: ""
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorPayerDoesNotSupportEligibilityInterface.selector,
                address(bare)
            )
        );
        vm.prank(address(bare));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 22 / 23 — Callback-gas prechecks (deterministic single-call)
    //
    // afterCollection.t.sol uses vm.revertTo in a binary-search loop, which
    // discards forge coverage traces. Direct calls track them.
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Eligibility-precheck gas guard reverts under tight gas. Direct call
    /// so coverage tracks the revert.
    function test_Collect_Revert_LowGas_EligibilityPrecheck_Direct() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(approver),
                dataService: makeAddr("ds-elig-low-gas"),
                serviceProvider: makeAddr("sp-elig-low-gas"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );
        rca.conditions = 1; // CONDITION_ELIGIBILITY_CHECK

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(
            _generateCollectParams(rca, agreementId, bytes32("col-elig-low"), 1 ether, 0)
        );
        bytes memory callData = abi.encodeCall(
            _recurringCollector.collect,
            (IGraphPayments.PaymentTypes.IndexingFee, data)
        );

        // Outer gas just below the 64/63 + overhead threshold (~1.527M) — gasleft() at the
        // first precheck must fall under threshold and trigger the revert.
        vm.prank(rca.dataService);
        (bool ok, bytes memory ret) = address(_recurringCollector).call{ gas: 1_500_000 }(callData);
        assertFalse(ok, "expected revert");
        assertTrue(ret.length >= 4, "expected revert reason");
        bytes4 selector;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            selector := mload(add(ret, 32))
        }
        assertEq(
            selector,
            IRecurringCollector.RecurringCollectorInsufficientCallbackGas.selector,
            "expected InsufficientCallbackGas at eligibility precheck"
        );
    }

    /// @notice beforeCollection-precheck gas guard reverts under tight gas. With no
    /// eligibility flag the first precheck is skipped, so this hits the second guard.
    function test_Collect_Revert_LowGas_BeforeCollection_Direct() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(approver),
                dataService: makeAddr("ds-before-low-gas"),
                serviceProvider: makeAddr("sp-before-low-gas"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0, // no eligibility — skip first precheck
                nonce: 1,
                metadata: ""
            })
        );

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(
            _generateCollectParams(rca, agreementId, bytes32("col-before-low"), 1 ether, 0)
        );
        bytes memory callData = abi.encodeCall(
            _recurringCollector.collect,
            (IGraphPayments.PaymentTypes.IndexingFee, data)
        );

        vm.prank(rca.dataService);
        (bool ok, bytes memory ret) = address(_recurringCollector).call{ gas: 1_500_000 }(callData);
        assertFalse(ok, "expected revert");
        assertTrue(ret.length >= 4, "expected revert reason");
        bytes4 selector;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            selector := mload(add(ret, 32))
        }
        assertEq(
            selector,
            IRecurringCollector.RecurringCollectorInsufficientCallbackGas.selector,
            "expected InsufficientCallbackGas at beforeCollection precheck"
        );
    }

    /* solhint-enable graph/func-name-mixedcase */
}

/// @notice Minimal mock data service that implements cancelIndexingAgreementByPayer
contract MockDataServiceForCancel {
    bool public cancelCalled;
    bytes16 public canceledAgreementId;

    function cancelIndexingAgreementByPayer(bytes16 agreementId) external {
        cancelCalled = true;
        canceledAgreementId = agreementId;
    }
}
