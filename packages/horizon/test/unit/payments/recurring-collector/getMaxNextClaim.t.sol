// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorGetMaxNextClaimTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- Test 1: NotAccepted agreement returns 0 --

    function test_GetMaxNextClaim_NotAccepted() public view {
        bytes16 fakeId = bytes16(keccak256("nonexistent"));
        assertEq(_recurringCollector.getMaxNextClaim(fakeId), 0, "NotAccepted agreement should return 0");
    }

    // -- Test 2: CanceledByServiceProvider agreement returns 0 --

    function test_GetMaxNextClaim_CanceledByServiceProvider(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        _cancelByProvider(rca, agreementId);

        assertEq(_recurringCollector.getMaxNextClaim(agreementId), 0, "CanceledByServiceProvider should return 0");
    }

    // -- Test 3: Active agreement, never collected --
    // Returns maxOngoingTokensPerSecond * min(windowSeconds, maxSecondsPerCollection) + maxInitialTokens

    function test_GetMaxNextClaim_Accepted_NeverCollected(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

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
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

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

    // 5a: Canceled in the same block as accepted — with min notice, collectableUntil is in the future
    function test_GetMaxNextClaim_CanceledByPayer_SameBlock(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        _cancelByPayer(rca, agreementId);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        if (rca.minSecondsPayerCancellationNotice > 0) {
            // With notice: collectableUntil > acceptedAt, so there IS a claimable window
            assertTrue(maxClaim > 0, "CanceledByPayer with notice should have claimable window");
        } else {
            // Zero notice: collectableUntil == acceptedAt, window = 0
            assertEq(maxClaim, 0, "CanceledByPayer with zero notice should return 0");
        }
    }

    // 5b: Canceled after time has elapsed (collectableUntil < endsAt)
    function test_GetMaxNextClaim_CanceledByPayer_WithWindow(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Advance time, then cancel (still before endsAt due to sensible bounds)
        skip(rca.minSecondsPerCollection + 100);

        _cancelByPayer(rca, agreementId);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // collectionEnd = min(collectableUntil, endsAt) = collectableUntil (since collectableUntil < endsAt)
        // collectionStart = acceptedAt (never collected)
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        uint256 windowSeconds = agreement.collectableUntil - agreement.acceptedAt;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds + rca.maxInitialTokens;
        assertEq(maxClaim, expected, "CanceledByPayer with elapsed time mismatch");
    }

    // 5c: CanceledByPayer after a collection (no initial tokens)
    function test_GetMaxNextClaim_CanceledByPayer_AfterCollection(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

        // Perform a first collection
        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, keccak256("col"), 1, 0));
        vm.prank(rca.dataService);
        _recurringCollector.collect(_paymentType(0), data);

        // Advance more time, then cancel
        skip(rca.minSecondsPerCollection + 100);
        _cancelByPayer(rca, agreementId);

        uint256 maxClaim = _recurringCollector.getMaxNextClaim(agreementId);

        // lastCollectionAt is set, so no initial bonus
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        uint256 windowSeconds = agreement.collectableUntil - agreement.lastCollectionAt;
        uint256 maxSeconds = windowSeconds < rca.maxSecondsPerCollection ? windowSeconds : rca.maxSecondsPerCollection;
        uint256 expected = rca.maxOngoingTokensPerSecond * maxSeconds;
        assertEq(maxClaim, expected, "CanceledByPayer post-collection should exclude initial tokens");
    }

    // -- Test 6: Agreement past endsAt --
    // For an active (Accepted) agreement that has gone past endsAt, the window
    // is capped at endsAt, so returns maxOngoingTokensPerSecond * min(remaining, maxSecondsPerCollection)

    function test_GetMaxNextClaim_Accepted_PastEndsAt(FuzzyTestAccept calldata fuzzy) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

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
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(fuzzy);

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
            minSecondsPayerCancellationNotice: 0,
            nonce: 1,
            metadata: ""
        });

        // Offer and accept
        _setupValidProvision(serviceProvider, dataService);
        vm.prank(payer);
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);

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
            minSecondsPayerCancellationNotice: 0,
            nonce: 1,
            metadata: ""
        });

        _setupValidProvision(serviceProvider, dataService);
        vm.prank(payer);
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);

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
