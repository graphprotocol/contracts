// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    UPDATE,
    NOTICE_GIVEN,
    SETTLED,
    BY_PAYER,
    BY_PROVIDER,
    BY_DATA_SERVICE,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
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
    function afterAgreementStateChange(bytes16, bytes32, uint16) external override {}

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
    // Gap 1 — Line 228: revert InvalidOfferType(offerType)
    // ══════════════════════════════════════════════════════════════════════

    function test_Offer_Revert_WhenOfferTypeInvalid_Two() public {
        // OFFER_TYPE_NEW=0, OFFER_TYPE_UPDATE=1, so offerType=2 is invalid
        address payer = makeAddr("payer");
        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.InvalidOfferType.selector, uint8(2)));
        vm.prank(payer);
        _recurringCollector.offer(2, bytes(""), 0);
    }

    function test_Offer_Revert_WhenOfferTypeInvalid_Three() public {
        address payer = makeAddr("payer");
        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.InvalidOfferType.selector, uint8(3)));
        vm.prank(payer);
        _recurringCollector.offer(3, bytes(""), 0);
    }

    function test_Offer_Revert_WhenOfferTypeInvalid_MaxUint8() public {
        address payer = makeAddr("payer");
        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.InvalidOfferType.selector, uint8(255)));
        vm.prank(payer);
        _recurringCollector.offer(255, bytes(""), 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 2 — Lines 464-468: getAgreementVersionCount()
    // ══════════════════════════════════════════════════════════════════════

    function test_GetAgreementVersionCount_Empty() public view {
        bytes16 fakeId = bytes16(keccak256("nonexistent"));
        uint256 count = _recurringCollector.getAgreementVersionCount(fakeId);
        assertEq(count, 0, "Empty agreement should return 0 versions");
    }

    function test_GetAgreementVersionCount_Accepted(FuzzyTestAccept calldata fuzzy) public {
        (, bytes16 agreementId) = _sensibleAccept(fuzzy);
        uint256 count = _recurringCollector.getAgreementVersionCount(agreementId);
        assertEq(count, 1, "Accepted agreement with no pending should return 1");
    }

    function test_GetAgreementVersionCount_WithPendingUpdate(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Submit an update (creates pendingTerms)
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
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        uint256 count = _recurringCollector.getAgreementVersionCount(agreementId);
        assertEq(count, 2, "Agreement with pending update should return 2");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 3 — Lines 472-482: getAgreementVersionAt()
    // ══════════════════════════════════════════════════════════════════════

    function test_GetAgreementVersionAt_Index0(FuzzyTestAccept calldata fuzzy) public {
        (, bytes16 agreementId) = _sensibleAccept(fuzzy);

        IAgreementCollector.AgreementVersion memory version = _recurringCollector.getAgreementVersionAt(agreementId, 0);
        assertTrue(version.versionHash != bytes32(0), "Index 0 should return non-zero active terms hash");
        assertEq(version.state, REGISTERED | ACCEPTED, "Index 0 state should be REGISTERED | ACCEPTED");
    }

    function test_GetAgreementVersionAt_Index1_WithPending(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Submit an update (creates pendingTerms)
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
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        IAgreementCollector.AgreementVersion memory version = _recurringCollector.getAgreementVersionAt(agreementId, 1);
        assertTrue(version.versionHash != bytes32(0), "Index 1 should return non-zero pending terms hash");
        assertEq(version.state, REGISTERED | ACCEPTED | UPDATE, "Index 1 state should include UPDATE flag");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 4 — getAgreementOfferAt round-trip (replaces getAgreementTermsAt tests)
    // ══════════════════════════════════════════════════════════════════════

    function test_GetAgreementOfferAt_Index0(FuzzyTestAccept calldata fuzzy) public {
        (, bytes16 agreementId) = _sensibleAccept(fuzzy);

        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);

        assertEq(offerType, OFFER_TYPE_NEW, "Index 0 should be OFFER_TYPE_NEW");
        IRecurringCollector.RecurringCollectionAgreement memory rca = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreement)
        );
        assertEq(_recurringCollector.hashRCA(rca), activeHash, "Reconstructed hash should match active terms");
    }

    function test_GetAgreementOfferAt_Index1_WithPending(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Submit an update
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
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);

        assertEq(offerType, OFFER_TYPE_UPDATE, "Index 1 should be OFFER_TYPE_UPDATE");
        IRecurringCollector.RecurringCollectionAgreementUpdate memory decoded = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreementUpdate)
        );
        assertEq(_recurringCollector.hashRCAU(decoded), pendingHash, "Reconstructed hash should match pending terms");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 5 — Lines 517-518: getMaxNextClaim(agreementId, claimScope)
    // ══════════════════════════════════════════════════════════════════════

    function test_GetMaxNextClaim_ScopeActiveOnly(FuzzyTestAccept calldata fuzzy) public {
        (, bytes16 agreementId) = _sensibleAccept(fuzzy);

        uint256 maxClaimActive = _recurringCollector.getMaxNextClaim(
            agreementId,
            _recurringCollector.CLAIM_SCOPE_ACTIVE()
        );
        uint256 maxClaimBoth = _recurringCollector.getMaxNextClaim(agreementId);

        // With no pending terms, active-only should equal both-scopes
        assertEq(maxClaimActive, maxClaimBoth, "Active-only scope should match full scope when no pending terms");
    }

    function test_GetMaxNextClaim_ScopePendingOnly(FuzzyTestAccept calldata fuzzy) public {
        (, bytes16 agreementId) = _sensibleAccept(fuzzy);

        uint256 maxClaimPending = _recurringCollector.getMaxNextClaim(
            agreementId,
            _recurringCollector.CLAIM_SCOPE_PENDING()
        );

        // With no pending terms, pending-only scope should return 0
        assertEq(maxClaimPending, 0, "Pending-only scope should return 0 when no pending terms");
    }

    function test_GetMaxNextClaim_ScopePendingOnly_WithPending(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Submit an update to create pending terms
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
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        uint256 maxClaimPending = _recurringCollector.getMaxNextClaim(
            agreementId,
            _recurringCollector.CLAIM_SCOPE_PENDING()
        );

        // Pending terms exist and have non-zero endsAt, so pending scope should be > 0
        assertTrue(0 < maxClaimPending, "Pending-only scope should be > 0 when pending terms exist");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 6 — Line 634: emit PayerCallbackFailed(...EligibilityCheck)
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
                conditions: 1, // CONDITION_ELIGIBILITY_CHECK
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            })
        );

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Payer calls offer (isEligible works correctly at this point)
        vm.prank(address(payer));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Service provider accepts
        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);

        // Now make the payer return malformed (< 32 bytes) from isEligible
        payer.setReturnMalformed(true);

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(
            _generateCollectParams(rca, agreementId, bytes32("col-malformed"), tokens, 0)
        );

        // Should emit PayerCallbackFailed with EligibilityCheck stage, but still collect
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.PayerCallbackFailed(
            agreementId,
            address(payer),
            IAgreementCollector.PayerCallbackStage.EligibilityCheck
        );

        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens, "Collection should proceed despite malformed eligibility response");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 7 — Line 850: agreement.activeTerms = terms (update on REGISTERED-only)
    // ══════════════════════════════════════════════════════════════════════

    function test_Update_OverwritesActiveTerms_WhenNotYetAccepted() public {
        address payer = address(0x1111);
        address dataService = address(0x2222);
        address serviceProvider = address(0x3333);

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: payer,
            dataService: dataService,
            serviceProvider: serviceProvider,
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 0,
            minSecondsPayerCancellationNotice: 0,
            nonce: 1,
            metadata: ""
        });

        // Offer but do NOT accept — stays in REGISTERED state
        bytes16 agreementId = _offer(rca);

        IRecurringCollector.AgreementData memory beforeUpdate = _recurringCollector.getAgreementData(agreementId);
        assertEq(beforeUpdate.state, REGISTERED, "Should be REGISTERED only");

        // Now submit OFFER_TYPE_UPDATE to overwrite activeTerms (line 850)
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
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        IRecurringCollector.AgreementData memory afterUpdate = _recurringCollector.getAgreementData(agreementId);
        assertEq(afterUpdate.state, REGISTERED | UPDATE, "Should be REGISTERED | UPDATE after pre-accept overwrite");
        {
            (, bytes memory activeOfferData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
            IRecurringCollector.RecurringCollectionAgreementUpdate memory activeRcau = abi.decode(
                activeOfferData,
                (IRecurringCollector.RecurringCollectionAgreementUpdate)
            );
            assertEq(activeRcau.maxInitialTokens, newMaxInitial, "activeTerms should be overwritten with new values");
        }
        // pendingTerms should remain empty
        assertEq(_recurringCollector.getAgreementVersionCount(agreementId), 1, "pendingTerms should remain empty");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 8 — Line 977: return (false, 0, ZeroCollectionSeconds)
    // ══════════════════════════════════════════════════════════════════════

    function test_GetAgreementData_ZeroCollectionSeconds(FuzzyTestAccept calldata fuzzy) public {
        (, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Read agreement in the same block as accept — collectionStart == collectionEnd == block.timestamp
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);

        assertFalse(agreement.isCollectable, "Should not be collectable with zero elapsed time");
        assertEq(agreement.collectionSeconds, 0, "Collection seconds should be 0");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 9 — Lines 1011-1012: _maxClaimForTerms when REGISTERED only
    // ══════════════════════════════════════════════════════════════════════

    function test_GetMaxNextClaim_OfferedButNotAccepted() public {
        address payer = address(0x1111);
        address dataService = address(0x2222);
        address serviceProvider = address(0x3333);

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 100_000),
            payer: payer,
            dataService: dataService,
            serviceProvider: serviceProvider,
            maxInitialTokens: 5000,
            maxOngoingTokensPerSecond: 100,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 0,
            minSecondsPayerCancellationNotice: 0,
            nonce: 1,
            metadata: ""
        });

        // Offer but do NOT accept
        bytes16 agreementId = _offer(rca);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // For REGISTERED-only: collectionStart = block.timestamp, collectionEnd = endsAt
        // windowSeconds = endsAt - block.timestamp = 100_000
        // effectiveSeconds = min(100_000, maxSecondsPerCollection=3600) = 3600
        // maxClaim = 100 * 3600 + 5000 = 365_000
        uint256 windowSeconds = rca.endsAt - block.timestamp;
        uint256 effectiveSeconds = windowSeconds < rca.maxSecondsPerCollection
            ? windowSeconds
            : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * effectiveSeconds + rca.maxInitialTokens;

        assertEq(maxClaim, expected, "Offered-but-not-accepted maxClaim should use block.timestamp as proxy");
        assertTrue(0 < maxClaim, "maxClaim should be non-zero for valid offered agreement");
    }

    // Line 252 (AgreementIncorrectState in accept) is unreachable: it requires state without
    // REGISTERED or ACCEPTED, but _getAgreementStorage returns state=0 for non-existent
    // agreements where serviceProvider=address(0), making the require on line 243 fail first.
    // It is a defensive guard.

    // -- Line 407: cancel a pending update specifically --

    function test_Cancel_PendingUpdate_ClearsPendingTerms(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

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
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Cancel specifically the pending update (using pending version hash)
        bytes32 pendingHash = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        assertTrue(pendingHash != bytes32(0), "Should have pending terms");

        vm.prank(rca.payer);
        _recurringCollector.cancel(agreementId, pendingHash, 0);

        // Pending terms cleared, active terms intact
        assertEq(_recurringCollector.getAgreementVersionCount(agreementId), 1, "Pending terms should be cleared");
        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        assertTrue(activeHash != bytes32(0), "Active terms should remain");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 10 — Line 261: cancel() by data service
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_ByDataService(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        bytes32 vHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(
            agreementId,
            vHash,
            REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_DATA_SERVICE
        );
        vm.prank(rca.dataService);
        _recurringCollector.cancel(agreementId, vHash, 0);

        IRecurringCollector.AgreementData memory data = _recurringCollector.getAgreementData(agreementId);
        assertTrue(data.state & BY_DATA_SERVICE != 0, "Should have BY_DATA_SERVICE flag");
        assertTrue(data.state & NOTICE_GIVEN != 0, "Should have NOTICE_GIVEN flag");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 11 — Line 290: cancel() on unaccepted (REGISTERED-only) agreement
    //          adds SETTLED flag immediately
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_UnacceptedAgreement_SettlesImmediately() public {
        address payer = address(0x1111);
        address dataService = address(0x2222);
        address serviceProvider = address(0x3333);

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: payer,
            dataService: dataService,
            serviceProvider: serviceProvider,
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 0,
            minSecondsPayerCancellationNotice: 0,
            nonce: 1,
            metadata: ""
        });

        // Offer but do NOT accept
        bytes16 agreementId = _offer(rca);

        IRecurringCollector.AgreementData memory before = _recurringCollector.getAgreementData(agreementId);
        assertEq(before.state, REGISTERED, "Should be REGISTERED only before cancel");

        // Cancel by payer (any party works, using payer)
        bytes32 vHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(agreementId, vHash, REGISTERED | NOTICE_GIVEN | SETTLED | BY_PAYER);
        vm.prank(payer);
        _recurringCollector.cancel(agreementId, vHash, 0);

        IRecurringCollector.AgreementData memory after_ = _recurringCollector.getAgreementData(agreementId);
        assertTrue(after_.state & SETTLED != 0, "Unaccepted cancel should set SETTLED immediately");
        assertTrue(after_.state & NOTICE_GIVEN != 0, "Should have NOTICE_GIVEN");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 12 — Line 271: cancel() with active terms hash (else branch of
    //          pendingTerms check) when pending terms also exist
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_ActiveTerms_WhenPendingExists(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Submit an update to create pending terms
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
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Cancel using the ACTIVE terms hash (not pendingTerms hash)
        // This hits the else branch at line 271
        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.cancel(agreementId, activeHash, 0);

        IRecurringCollector.AgreementData memory data = _recurringCollector.getAgreementData(agreementId);
        assertTrue(data.state & NOTICE_GIVEN != 0, "Should have NOTICE_GIVEN");
        assertTrue(data.state & BY_PROVIDER != 0, "Should have BY_PROVIDER");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 13 — Line 276: cancel() revert on unregistered agreement
    // ══════════════════════════════════════════════════════════════════════

    // ══════════════════════════════════════════════════════════════════════
    // Gap 13a — Line 271: cancel() revert when hash matches neither
    //           pending nor active terms
    // ══════════════════════════════════════════════════════════════════════

    function test_Cancel_Revert_WhenHashMatchesNeither(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        bytes32 bogusHash = bytes32(uint256(0xdead));
        vm.assume(bogusHash != activeHash);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.AgreementHashMismatch.selector,
                agreementId,
                activeHash,
                bogusHash
            )
        );
        vm.prank(rca.payer);
        _recurringCollector.cancel(agreementId, bogusHash, 0);
    }

    // Line 276: require(oldState & REGISTERED != 0) in cancel()
    // This branch is a defensive guard. A state without REGISTERED can only be 0 (non-existent),
    // but non-existent agreements have payer/serviceProvider/dataService == address(0),
    // so the caller authorization check at line 259-262 always reverts first.

    // ══════════════════════════════════════════════════════════════════════
    // Gap 14 — Lines 356/360/368: getAgreementOfferAt edge cases
    // ══════════════════════════════════════════════════════════════════════

    function test_GetAgreementOfferAt_Index2_ReturnsEmpty(FuzzyTestAccept calldata fuzzy) public {
        (, bytes16 agreementId) = _sensibleAccept(fuzzy);

        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 2);
        assertEq(offerType, 0, "Out-of-range index should return 0 offerType");
        assertEq(offerData.length, 0, "Out-of-range index should return empty data");
    }

    function test_GetAgreementOfferAt_EmptyAgreement() public view {
        bytes16 fakeId = bytes16(keccak256("nonexistent"));

        // Index 0 on non-existent agreement: terms.hash == bytes32(0)
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(fakeId, 0);
        assertEq(offerType, 0, "Empty agreement index 0 should return 0 offerType");
        assertEq(offerData.length, 0, "Empty agreement index 0 should return empty data");
    }

    function test_GetAgreementOfferAt_Index1_NoPending(FuzzyTestAccept calldata fuzzy) public {
        (, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Index 1 with no pending terms: terms.hash == bytes32(0)
        (uint8 offerType, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        assertEq(offerType, 0, "No pending terms should return 0 offerType");
        assertEq(offerData.length, 0, "No pending terms should return empty data");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 15 — Line 801: _validateAndStoreOffer revert on expired deadline
    // ══════════════════════════════════════════════════════════════════════

    function test_Offer_Revert_WhenDeadlineExpired() public {
        address payer = address(0x1111);

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp - 1), // already expired
            endsAt: uint64(block.timestamp + 365 days),
            payer: payer,
            dataService: address(0x2222),
            serviceProvider: address(0x3333),
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 600,
            maxSecondsPerCollection: 3600,
            conditions: 0,
            minSecondsPayerCancellationNotice: 0,
            nonce: 1,
            metadata: ""
        });

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.AgreementDeadlineElapsed.selector, block.timestamp, rca.deadline)
        );
        vm.prank(payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gap 16 — Line 864: _validateAndStoreUpdate revert on unregistered
    // ══════════════════════════════════════════════════════════════════════

    // Line 864: require(state & REGISTERED != 0) in _validateAndStoreUpdate()
    // This branch is a defensive guard. For a non-existent agreement, payer == address(0),
    // so the auth check (require msg.sender == agreement.payer) reverts first.
    // No normal flow can produce a state where REGISTERED is cleared on an existing agreement.

    // ══════════════════════════════════════════════════════════════════════
    // Gap 17 — Line 1205: _maxClaimForTerms with s == 0 (empty state)
    // ══════════════════════════════════════════════════════════════════════

    function test_GetMaxNextClaim_EmptyState_ReturnsZero() public view {
        // Non-existent agreement has state == 0 and terms.endsAt == 0
        // Both conditions return 0
        bytes16 fakeId = bytes16(keccak256("nonexistent"));
        uint256 maxClaim = _recurringCollector.getMaxNextClaim(fakeId);
        assertEq(maxClaim, 0, "Empty state agreement should return 0");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
