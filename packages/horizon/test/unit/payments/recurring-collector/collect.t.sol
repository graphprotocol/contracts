// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorCollectTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Collect_Revert_WhenInvalidData(address caller, uint8 unboundedPaymentType, bytes memory data) public {
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidCollectData.selector,
            data
        );
        vm.expectRevert(expectedErr);
        vm.prank(caller);
        _recurringCollector.collect(_paymentType(unboundedPaymentType), data);
    }

    function test_Collect_Revert_WhenCallerNotDataService(
        FuzzyTestCollect calldata fuzzy,
        address notDataService
    ) public {
        vm.assume(fuzzy.fuzzyTestAccept.rca.dataService != notDataService);

        (, , , bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);
        IRecurringCollector.CollectParams memory collectParams = fuzzy.collectParams;

        skip(1);
        collectParams.agreementId = agreementId;
        bytes memory data = _generateCollectData(collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            collectParams.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
    }

    function test_Collect_Revert_WhenUnauthorizedDataService(FuzzyTestCollect calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);
        IRecurringCollector.CollectParams memory collectParams = fuzzy.collectParams;
        collectParams.agreementId = agreementId;
        collectParams.tokens = bound(collectParams.tokens, 1, type(uint256).max);
        bytes memory data = _generateCollectData(collectParams);

        skip(1);

        // Set up the scenario where service provider has no tokens staked with data service
        // This simulates an unauthorized data service attack
        _horizonStaking.setProvision(
            acceptedRca.serviceProvider,
            acceptedRca.dataService,
            IHorizonStakingTypes.Provision({
                tokens: 0, // No tokens staked - this triggers the vulnerability
                tokensThawing: 0,
                sharesThawing: 0,
                maxVerifierCut: 100000,
                thawingPeriod: 604800,
                createdAt: uint64(block.timestamp),
                maxVerifierCutPending: 100000,
                thawingPeriodPending: 604800,
                lastParametersStagedAt: 0,
                thawingNonce: 0
            })
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorUnauthorizedDataService.selector,
            acceptedRca.dataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
    }

    function test_Collect_Revert_WhenUnknownAgreement(FuzzyTestCollect memory fuzzy, address dataService) public {
        bytes memory data = _generateCollectData(fuzzy.collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNotCollectable.selector,
            fuzzy.collectParams.agreementId,
            IRecurringCollector.AgreementNotCollectableReason.InvalidAgreementState
        );
        vm.expectRevert(expectedErr);
        vm.prank(dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
    }

    function test_Collect_Revert_WhenCanceledAgreementByServiceProvider(FuzzyTestCollect calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);
        _cancel(acceptedRca, agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);
        IRecurringCollector.CollectParams memory collectData = fuzzy.collectParams;
        collectData.tokens = bound(collectData.tokens, 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            acceptedRca,
            agreementId,
            collectData.collectionId,
            collectData.tokens,
            collectData.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNotCollectable.selector,
            collectParams.agreementId,
            IRecurringCollector.AgreementNotCollectableReason.InvalidAgreementState
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
    }

    function test_Collect_Revert_WhenCollectingTooSoon(
        FuzzyTestCollect calldata fuzzy,
        uint256 unboundedCollectionSeconds
    ) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        skip(acceptedRca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(
            _generateCollectParams(
                acceptedRca,
                agreementId,
                fuzzy.collectParams.collectionId,
                1,
                fuzzy.collectParams.dataServiceCut
            )
        );
        vm.prank(acceptedRca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);

        uint256 collectionSeconds = boundSkip(unboundedCollectionSeconds, 1, acceptedRca.minSecondsPerCollection - 1);
        skip(collectionSeconds);

        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            acceptedRca,
            agreementId,
            fuzzy.collectParams.collectionId,
            bound(fuzzy.collectParams.tokens, 1, type(uint256).max),
            fuzzy.collectParams.dataServiceCut
        );
        data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectionTooSoon.selector,
            collectParams.agreementId,
            collectionSeconds,
            acceptedRca.minSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
    }

    function test_Collect_OK_WhenCollectingPastMaxSeconds(
        FuzzyTestCollect calldata fuzzy,
        uint256 unboundedFirstCollectionSeconds,
        uint256 unboundedSecondCollectionSeconds
    ) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        // First valid collection to establish lastCollectionAt
        skip(
            boundSkip(
                unboundedFirstCollectionSeconds,
                acceptedRca.minSecondsPerCollection,
                acceptedRca.maxSecondsPerCollection
            )
        );
        bytes memory firstData = _generateCollectData(
            _generateCollectParams(
                acceptedRca,
                agreementId,
                fuzzy.collectParams.collectionId,
                1,
                fuzzy.collectParams.dataServiceCut
            )
        );
        vm.prank(acceptedRca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), firstData);

        // Skip PAST maxSecondsPerCollection (but still within agreement endsAt)
        uint256 collectionSeconds = boundSkip(
            unboundedSecondCollectionSeconds,
            acceptedRca.maxSecondsPerCollection + 1,
            acceptedRca.endsAt - block.timestamp
        );
        skip(collectionSeconds);

        // Request more tokens than the cap allows
        uint256 cappedMaxTokens = acceptedRca.maxOngoingTokensPerSecond * acceptedRca.maxSecondsPerCollection;
        uint256 requestedTokens = cappedMaxTokens + 1;

        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            acceptedRca,
            agreementId,
            fuzzy.collectParams.collectionId,
            requestedTokens,
            fuzzy.collectParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);

        // Collection should SUCCEED with tokens capped at maxSecondsPerCollection worth
        _expectCollectCallAndEmit(
            acceptedRca,
            agreementId,
            _paymentType(fuzzy.unboundedPaymentType),
            collectParams,
            cappedMaxTokens
        );
        vm.prank(acceptedRca.dataService);
        uint256 collected = _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
        assertEq(collected, cappedMaxTokens, "Tokens should be capped at maxSecondsPerCollection worth");
    }

    function test_Collect_OK_WhenCollectingTooMuch(
        FuzzyTestCollect calldata fuzzy,
        uint256 unboundedInitialCollectionSeconds,
        uint256 unboundedCollectionSeconds,
        uint256 unboundedTokens,
        bool testInitialCollection
    ) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        if (!testInitialCollection) {
            // skip to collectable time
            skip(
                boundSkip(
                    unboundedInitialCollectionSeconds,
                    acceptedRca.minSecondsPerCollection,
                    acceptedRca.maxSecondsPerCollection
                )
            );
            bytes memory initialData = _generateCollectData(
                _generateCollectParams(
                    acceptedRca,
                    agreementId,
                    fuzzy.collectParams.collectionId,
                    1,
                    fuzzy.collectParams.dataServiceCut
                )
            );
            vm.prank(acceptedRca.dataService);
            _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), initialData);
        }

        // skip to collectable time
        uint256 collectionSeconds = boundSkip(
            unboundedCollectionSeconds,
            acceptedRca.minSecondsPerCollection,
            acceptedRca.maxSecondsPerCollection
        );
        skip(collectionSeconds);
        uint256 maxTokens = acceptedRca.maxOngoingTokensPerSecond * collectionSeconds;
        maxTokens += testInitialCollection ? acceptedRca.maxInitialTokens : 0;
        uint256 tokens = bound(unboundedTokens, maxTokens + 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            acceptedRca,
            agreementId,
            fuzzy.collectParams.collectionId,
            tokens,
            fuzzy.collectParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);
        vm.prank(acceptedRca.dataService);
        uint256 collected = _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
        assertEq(collected, maxTokens);
    }

    function test_Collect_OK(
        FuzzyTestCollect calldata fuzzy,
        uint256 unboundedCollectionSeconds,
        uint256 unboundedTokens
    ) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        (bytes memory data, uint256 collectionSeconds, uint256 tokens) = _generateValidCollection(
            acceptedRca,
            fuzzy.collectParams,
            unboundedCollectionSeconds,
            unboundedTokens
        );

        skip(collectionSeconds);
        _expectCollectCallAndEmit(
            acceptedRca,
            agreementId,
            _paymentType(fuzzy.unboundedPaymentType),
            fuzzy.collectParams,
            tokens
        );
        vm.prank(acceptedRca.dataService);
        uint256 collected = _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
        assertEq(collected, tokens);
    }

    function test_Collect_RevertWhen_ExceedsMaxSlippage() public {
        // Setup: Create agreement with known parameters
        IRecurringCollector.RecurringCollectionAgreement memory rca;
        rca.deadline = uint64(block.timestamp + 1000);
        rca.endsAt = uint64(block.timestamp + 2000);
        rca.payer = address(0x123);
        rca.dataService = address(0x456);
        rca.serviceProvider = address(0x789);
        rca.maxInitialTokens = 0; // No initial tokens to keep calculation simple
        rca.maxOngoingTokensPerSecond = 1 ether; // 1 token per second
        rca.minSecondsPerCollection = 60; // 1 minute
        rca.maxSecondsPerCollection = 3600; // 1 hour
        rca.nonce = 1;
        rca.metadata = "";

        // Accept the agreement
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, 1);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, 1);
        bytes16 agreementId = _accept(rca, signature);

        // Do a first collection to use up initial tokens allowance
        skip(rca.minSecondsPerCollection);
        IRecurringCollector.CollectParams memory firstCollection = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: keccak256("first"),
            tokens: 1 ether, // Small amount
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, _generateCollectData(firstCollection));

        // Wait minimum collection time again for second collection
        skip(rca.minSecondsPerCollection);

        // Calculate expected narrowing: max allowed is 60 tokens (60 seconds * 1 token/second)
        uint256 maxAllowed = rca.maxOngoingTokensPerSecond * rca.minSecondsPerCollection; // 60 tokens
        uint256 requested = maxAllowed + 50 ether; // Request 110 tokens
        uint256 expectedSlippage = requested - maxAllowed; // 50 tokens
        uint256 maxSlippage = expectedSlippage - 1; // Allow up to 49 tokens slippage

        // Create collect params with slippage protection
        IRecurringCollector.CollectParams memory collectParams = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: keccak256("test"),
            tokens: requested,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: maxSlippage
        });

        bytes memory data = _generateCollectData(collectParams);

        // Expect revert due to excessive slippage (50 > 49)
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorExcessiveSlippage.selector,
                requested,
                maxAllowed,
                maxSlippage
            )
        );
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_OK_WithMaxSlippageDisabled() public {
        // Setup: Create agreement with known parameters
        IRecurringCollector.RecurringCollectionAgreement memory rca;
        rca.deadline = uint64(block.timestamp + 1000);
        rca.endsAt = uint64(block.timestamp + 2000);
        rca.payer = address(0x123);
        rca.dataService = address(0x456);
        rca.serviceProvider = address(0x789);
        rca.maxInitialTokens = 0; // No initial tokens to keep calculation simple
        rca.maxOngoingTokensPerSecond = 1 ether; // 1 token per second
        rca.minSecondsPerCollection = 60; // 1 minute
        rca.maxSecondsPerCollection = 3600; // 1 hour
        rca.nonce = 1;
        rca.metadata = "";

        // Accept the agreement
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, 1);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, 1);
        bytes16 agreementId = _accept(rca, signature);

        // Do a first collection to use up initial tokens allowance
        skip(rca.minSecondsPerCollection);
        IRecurringCollector.CollectParams memory firstCollection = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: keccak256("first"),
            tokens: 1 ether, // Small amount
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, _generateCollectData(firstCollection));

        // Wait minimum collection time again for second collection
        skip(rca.minSecondsPerCollection);

        // Calculate expected narrowing: max allowed is 60 tokens (60 seconds * 1 token/second)
        uint256 maxAllowed = rca.maxOngoingTokensPerSecond * rca.minSecondsPerCollection; // 60 tokens
        uint256 requested = maxAllowed + 50 ether; // Request 110 tokens (will be narrowed to 60)

        // Create collect params with slippage disabled (type(uint256).max)
        IRecurringCollector.CollectParams memory collectParams = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: keccak256("test"),
            tokens: requested,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });

        bytes memory data = _generateCollectData(collectParams);

        // Should succeed despite slippage when maxSlippage is disabled
        _expectCollectCallAndEmit(
            rca,
            agreementId,
            IGraphPayments.PaymentTypes.IndexingFee,
            collectParams,
            maxAllowed // Will collect the narrowed amount
        );

        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, maxAllowed);
    }
    function test_Collect_Revert_WhenZeroTokensBypassesTemporalValidation(FuzzyTestCollect calldata fuzzy) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        // First valid collection to establish lastCollectionAt
        skip(acceptedRca.minSecondsPerCollection);
        bytes memory firstData = _generateCollectData(
            _generateCollectParams(
                acceptedRca,
                agreementId,
                fuzzy.collectParams.collectionId,
                1,
                fuzzy.collectParams.dataServiceCut
            )
        );
        vm.prank(acceptedRca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), firstData);

        // Attempt zero-token collection immediately (before minSecondsPerCollection).
        // This MUST revert with CollectionTooSoon — zero tokens should NOT bypass
        // the temporal validation that guards minSecondsPerCollection.
        skip(1);
        IRecurringCollector.CollectParams memory zeroParams = _generateCollectParams(
            acceptedRca,
            agreementId,
            fuzzy.collectParams.collectionId,
            0, // zero tokens
            fuzzy.collectParams.dataServiceCut
        );
        bytes memory zeroData = _generateCollectData(zeroParams);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorCollectionTooSoon.selector,
                agreementId,
                uint32(1), // only 1 second elapsed
                acceptedRca.minSecondsPerCollection
            )
        );
        vm.prank(acceptedRca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), zeroData);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
