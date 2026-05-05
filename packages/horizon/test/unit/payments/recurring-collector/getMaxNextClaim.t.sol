// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { OFFER_TYPE_NEW, OFFER_TYPE_UPDATE } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

contract RecurringCollectorGetMaxNextClaimTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- Test 1: NotAccepted agreement returns 0 --

    function test_GetMaxNextClaim_NotAccepted() public view {
        bytes16 fakeId = bytes16(keccak256("nonexistent"));
        assertEq(_recurringCollector.getMaxNextClaim(fakeId), 0, "NotAccepted agreement should return 0");
    }

    // -- Pre-acceptance stored-offer tests --

    /// @notice After offer(OFFER_TYPE_NEW), getMaxNextClaim returns expected value before accept
    function test_GetMaxNextClaim_StoredOffer_BeforeAccept() public {
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

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // Pre-acceptance: window = endsAt - now, capped at maxSecondsPerCollection
        uint256 windowSeconds = rca.endsAt - block.timestamp;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds + rca.maxInitialTokens;
        assertEq(maxClaim, expected, "Stored RCA offer should return expected maxNextClaim before accept");
        assertTrue(maxClaim > 0, "Stored offer maxNextClaim should be non-zero");
    }

    /// @notice After offer(OFFER_TYPE_NEW), getMaxNextClaim returns 0 if deadline has passed
    function test_GetMaxNextClaim_StoredOffer_ExpiredDeadline() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 100),
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

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        // Warp past deadline
        vm.warp(rca.deadline + 1);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);
        assertEq(maxClaim, 0, "Stored offer past deadline should return 0");
    }

    /// @notice After offer(OFFER_TYPE_UPDATE), getMaxNextClaim reflects pending update
    function test_GetMaxNextClaim_StoredUpdate_PendingScope() public {
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

        // Accept via unsigned path
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        // Store a pending update with higher rates
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

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Check pending scope
        uint256 pendingClaim = _recurringCollector.getMaxNextClaim(agreementId, 2); // SCOPE_PENDING

        // Pending: window = rcau.endsAt - now, capped at rcau.maxSecondsPerCollection
        // Never collected so includes maxInitialTokens
        uint256 windowSeconds = rcau.endsAt - block.timestamp;
        uint256 maxSeconds = windowSeconds < rcau.maxSecondsPerCollection
            ? windowSeconds
            : rcau.maxSecondsPerCollection;
        uint256 expected = rcau.maxOngoingTokensPerSecond * maxSeconds + rcau.maxInitialTokens;
        assertEq(pendingClaim, expected, "Pending RCAU should return expected maxNextClaim");
        assertTrue(pendingClaim > 0, "Pending maxNextClaim should be non-zero");
    }

    /// @notice getMaxNextClaim (no scope) returns max(active, pending) when both exist
    function test_GetMaxNextClaim_MaxOfActiveAndPending() public {
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

        // Accept
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        // Store a pending update with higher rates
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

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        uint256 activeClaim = _recurringCollector.getMaxNextClaim(agreementId, 1); // SCOPE_ACTIVE
        uint256 pendingClaim = _recurringCollector.getMaxNextClaim(agreementId, 2); // SCOPE_PENDING
        uint256 combinedClaim = _recurringCollector.getMaxNextClaim(agreementId); // max of both

        uint256 expectedMax = activeClaim < pendingClaim ? pendingClaim : activeClaim;
        assertEq(combinedClaim, expectedMax, "Combined should be max(active, pending)");
        // With higher rates on pending, pending should dominate
        assertGe(pendingClaim, activeClaim, "Higher-rate pending should be >= active");
    }

    // -- Test 2: CanceledByServiceProvider agreement returns 0 --

    function test_GetMaxNextClaim_CanceledByServiceProvider(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        assertEq(_recurringCollector.getMaxNextClaim(agreementId), 0, "CanceledByServiceProvider should return 0");
    }

    // -- Test 3: Active agreement, never collected --
    // Returns maxOngoingTokensPerSecond * min(windowSeconds, maxSecondsPerCollection) + maxInitialTokens

    function test_GetMaxNextClaim_Accepted_NeverCollected(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // Never collected: window = endsAt - acceptedAt, capped at maxSecondsPerCollection
        // Also includes maxInitialTokens
        uint256 windowSeconds = rca.endsAt - block.timestamp;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds + rca.maxInitialTokens;
        assertEq(maxClaim, expected, "Never-collected active agreement mismatch");
    }

    // -- Test 4: Active agreement, already collected once --
    // Returns maxOngoingTokensPerSecond * min(windowSeconds, maxSecondsPerCollection) (no initial bonus)

    function test_GetMaxNextClaim_Accepted_AfterCollection(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Perform a first collection so lastCollectionAt is set
        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, keccak256("col"), 1, 0));
        vm.prank(rca.dataService);
        _recurringCollector.collect(_paymentType(0), data);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // After collection: no initial tokens, window from lastCollectionAt to endsAt
        uint256 windowSeconds = rca.endsAt - block.timestamp;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds;
        assertEq(maxClaim, expected, "Post-collection active agreement should exclude initial tokens");
    }

    // -- Test 5: CanceledByPayer agreement --

    // 5a: Canceled in the same block as accepted (window = 0)
    function test_GetMaxNextClaim_CanceledByPayer_SameBlock(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // canceledAt == acceptedAt (same block), so window = 0, maxClaim = 0
        assertEq(maxClaim, 0, "CanceledByPayer in same block should return 0");
    }

    // 5b: Canceled after time has elapsed (canceledAt < endsAt)
    function test_GetMaxNextClaim_CanceledByPayer_WithWindow(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Advance time, then cancel (still before endsAt due to sensible bounds)
        skip(rca.minSecondsPerCollection + 100);

        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // collectionEnd = min(canceledAt, endsAt) = canceledAt (since canceledAt < endsAt)
        // collectionStart = acceptedAt (never collected)
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        uint256 windowSeconds = agreement.canceledAt - agreement.acceptedAt;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds + rca.maxInitialTokens;
        assertEq(maxClaim, expected, "CanceledByPayer with elapsed time mismatch");
    }

    // 5c: CanceledByPayer after a collection (no initial tokens)
    function test_GetMaxNextClaim_CanceledByPayer_AfterCollection(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Perform a first collection
        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, keccak256("col"), 1, 0));
        vm.prank(rca.dataService);
        _recurringCollector.collect(_paymentType(0), data);

        // Advance more time, then cancel
        skip(rca.minSecondsPerCollection + 100);
        _cancel(rca, agreementId, IRecurringCollector.CancelAgreementBy.Payer);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // lastCollectionAt is set, so no initial bonus
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        uint256 windowSeconds = agreement.canceledAt - agreement.lastCollectionAt;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds;
        assertEq(maxClaim, expected, "CanceledByPayer post-collection should exclude initial tokens");
    }

    // -- Test 6: Agreement past endsAt --
    // For an active (Accepted) agreement that has gone past endsAt, the window
    // is capped at endsAt, so returns maxOngoingTokensPerSecond * min(remaining, maxSecondsPerCollection)

    function test_GetMaxNextClaim_Accepted_PastEndsAt(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        // Perform a first collection so we have a lastCollectionAt
        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, keccak256("col"), 1, 0));
        vm.prank(rca.dataService);
        _recurringCollector.collect(_paymentType(0), data);

        uint256 lastCollectionAt = block.timestamp;

        // Warp past endsAt
        vm.warp(rca.endsAt + 1000);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // collectionEnd = endsAt (active, capped), collectionStart = lastCollectionAt
        // remaining = endsAt - lastCollectionAt, capped by maxSecondsPerCollection
        uint256 remaining = rca.endsAt - lastCollectionAt;
        uint256 maxSeconds = remaining < rca.maxSecondsPerCollection ? remaining : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds;
        assertEq(maxClaim, expected, "Past-endsAt active agreement should cap at endsAt");
    }

    // Also test past endsAt when never collected (includes initial tokens)
    function test_GetMaxNextClaim_Accepted_PastEndsAt_NeverCollected(FuzzyTestAccept calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy);

        uint256 acceptedAt = block.timestamp;

        // Warp past endsAt without ever collecting
        vm.warp(rca.endsAt + 1000);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // collectionEnd = endsAt, collectionStart = acceptedAt
        // window = endsAt - acceptedAt, capped by maxSecondsPerCollection
        // Never collected so includes maxInitialTokens
        uint256 windowSeconds = rca.endsAt - acceptedAt;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds + rca.maxInitialTokens;
        assertEq(maxClaim, expected, "Past-endsAt never-collected should include initial tokens");
    }

    // -- Test 7: maxSecondsPerCollection caps the window --

    function test_GetMaxNextClaim_MaxSecondsPerCollectionCaps() public {
        // Use deterministic values to precisely verify the cap behavior
        uint256 signerKey = 0xBEEF;
        address payer = address(0x1111);
        address dataService = address(0x2222);
        address serviceProvider = address(0x3333);

        uint32 minSecondsPerCollection = 1000;
        uint32 maxSecondsPerCollection = 3600; // 1 hour cap
        uint256 maxOngoingTokensPerSecond = 100;
        uint256 maxInitialTokens = 5000;

        // Accept the agreement
        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1000),
            endsAt: uint64(block.timestamp + 100_000), // much larger than maxSecondsPerCollection
            payer: payer,
            dataService: dataService,
            serviceProvider: serviceProvider,
            maxInitialTokens: maxInitialTokens,
            maxOngoingTokensPerSecond: maxOngoingTokensPerSecond,
            minSecondsPerCollection: minSecondsPerCollection,
            maxSecondsPerCollection: maxSecondsPerCollection,
            conditions: 0,
            nonce: 1,
            metadata: ""
        });

        // Authorize signer and accept
        _recurringCollectorHelper.authorizeSignerWithChecks(payer, signerKey);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, signerKey);
        _setupValidProvision(serviceProvider, dataService);
        vm.prank(dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, signature);

        // Window = endsAt - acceptedAt = 100_000 seconds, which is > maxSecondsPerCollection (3600)
        // So the window should be capped at maxSecondsPerCollection
        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // maxSeconds = min(100_000, 3600) = 3600
        uint256 expectedCapped = maxOngoingTokensPerSecond * maxSecondsPerCollection + maxInitialTokens;
        assertEq(maxClaim, expectedCapped, "Window should be capped at maxSecondsPerCollection");

        // Verify the cap actually applies by checking it is less than the uncapped value
        uint256 uncappedWindow = rca.endsAt - block.timestamp;
        uint256 expectedUncapped = maxOngoingTokensPerSecond * uncappedWindow + maxInitialTokens;
        assertLt(expectedCapped, expectedUncapped, "Capped value should be less than uncapped value");
    }

    function test_GetMaxNextClaim_WindowSmallerThanMaxSecondsPerCollection() public {
        // Test the case where the window is smaller than maxSecondsPerCollection (no cap)
        uint256 signerKey = 0xBEEF;
        address payer = address(0x1111);
        address dataService = address(0x2222);
        address serviceProvider = address(0x3333);

        uint32 minSecondsPerCollection = 1000;
        uint32 maxSecondsPerCollection = 100_000; // very large cap
        uint256 maxOngoingTokensPerSecond = 100;
        uint256 maxInitialTokens = 5000;

        // endsAt is set so window (endsAt - acceptedAt) < maxSecondsPerCollection
        uint64 endsAt = uint64(block.timestamp + 10_000);

        IRecurringCollector.RecurringCollectionAgreement memory rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1000),
            endsAt: endsAt,
            payer: payer,
            dataService: dataService,
            serviceProvider: serviceProvider,
            maxInitialTokens: maxInitialTokens,
            maxOngoingTokensPerSecond: maxOngoingTokensPerSecond,
            minSecondsPerCollection: minSecondsPerCollection,
            maxSecondsPerCollection: maxSecondsPerCollection,
            conditions: 0,
            nonce: 1,
            metadata: ""
        });

        _recurringCollectorHelper.authorizeSignerWithChecks(payer, signerKey);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, signerKey);
        _setupValidProvision(serviceProvider, dataService);
        vm.prank(dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, signature);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // Window = 10_000, maxSecondsPerCollection = 100_000
        // min(10_000, 100_000) = 10_000 (window is the limiting factor, not the cap)
        uint256 windowSeconds = endsAt - block.timestamp;
        uint256 expected = maxOngoingTokensPerSecond * windowSeconds + maxInitialTokens;
        assertEq(maxClaim, expected, "When window < maxSecondsPerCollection, window should be used directly");
        // Confirm that the window was indeed smaller
        assertLt(windowSeconds, maxSecondsPerCollection, "Window should be smaller than maxSecondsPerCollection");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
