// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "../../../../contracts/interfaces/IRecurringCollector.sol";

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

        (IRecurringCollector.SignedRCA memory accepted, ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);
        IRecurringCollector.CollectParams memory collectParams = fuzzy.collectParams;

        collectParams.agreementId = accepted.rca.agreementId;
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

    function test_Collect_Revert_WhenUnknownAgreement(FuzzyTestCollect memory fuzzy, address dataService) public {
        bytes memory data = _generateCollectData(fuzzy.collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            fuzzy.collectParams.agreementId,
            IRecurringCollector.AgreementState.NotAccepted
        );
        vm.expectRevert(expectedErr);
        vm.prank(dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
    }

    function test_Collect_Revert_WhenCanceledAgreementByServiceProvider(FuzzyTestCollect calldata fuzzy) public {
        (IRecurringCollector.SignedRCA memory accepted, ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);
        _cancel(accepted.rca, IRecurringCollector.CancelAgreementBy.ServiceProvider);
        IRecurringCollector.CollectParams memory collectData = fuzzy.collectParams;
        collectData.tokens = bound(collectData.tokens, 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            accepted.rca,
            collectData.collectionId,
            collectData.tokens,
            collectData.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            collectParams.agreementId,
            IRecurringCollector.AgreementState.CanceledByServiceProvider
        );
        vm.expectRevert(expectedErr);
        vm.prank(accepted.rca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
    }

    function test_Collect_Revert_WhenCollectingTooSoon(
        FuzzyTestCollect calldata fuzzy,
        uint256 unboundedCollectionSeconds
    ) public {
        (IRecurringCollector.SignedRCA memory accepted, ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        skip(accepted.rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(
            _generateCollectParams(
                accepted.rca,
                fuzzy.collectParams.collectionId,
                1,
                fuzzy.collectParams.dataServiceCut
            )
        );
        vm.prank(accepted.rca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);

        uint256 collectionSeconds = boundSkip(unboundedCollectionSeconds, 1, accepted.rca.minSecondsPerCollection - 1);
        skip(collectionSeconds);

        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            accepted.rca,
            fuzzy.collectParams.collectionId,
            bound(fuzzy.collectParams.tokens, 1, type(uint256).max),
            fuzzy.collectParams.dataServiceCut
        );
        data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectionTooSoon.selector,
            collectParams.agreementId,
            collectionSeconds,
            accepted.rca.minSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(accepted.rca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
    }

    function test_Collect_Revert_WhenCollectingTooLate(
        FuzzyTestCollect calldata fuzzy,
        uint256 unboundedFirstCollectionSeconds,
        uint256 unboundedSecondCollectionSeconds
    ) public {
        (IRecurringCollector.SignedRCA memory accepted, ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        // skip to collectable time
        skip(
            boundSkip(
                unboundedFirstCollectionSeconds,
                accepted.rca.minSecondsPerCollection,
                accepted.rca.maxSecondsPerCollection
            )
        );
        bytes memory data = _generateCollectData(
            _generateCollectParams(
                accepted.rca,
                fuzzy.collectParams.collectionId,
                1,
                fuzzy.collectParams.dataServiceCut
            )
        );
        vm.prank(accepted.rca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);

        // skip beyond collectable time but still within the agreement endsAt
        uint256 collectionSeconds = boundSkip(
            unboundedSecondCollectionSeconds,
            accepted.rca.maxSecondsPerCollection + 1,
            accepted.rca.endsAt - block.timestamp
        );
        skip(collectionSeconds);

        data = _generateCollectData(
            _generateCollectParams(
                accepted.rca,
                fuzzy.collectParams.collectionId,
                bound(fuzzy.collectParams.tokens, 1, type(uint256).max),
                fuzzy.collectParams.dataServiceCut
            )
        );
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectionTooLate.selector,
            accepted.rca.agreementId,
            collectionSeconds,
            accepted.rca.maxSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(accepted.rca.dataService);
        _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
    }

    function test_Collect_OK_WhenCollectingTooMuch(
        FuzzyTestCollect calldata fuzzy,
        uint256 unboundedInitialCollectionSeconds,
        uint256 unboundedCollectionSeconds,
        uint256 unboundedTokens,
        bool testInitialCollection
    ) public {
        (IRecurringCollector.SignedRCA memory accepted, ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        if (!testInitialCollection) {
            // skip to collectable time
            skip(
                boundSkip(
                    unboundedInitialCollectionSeconds,
                    accepted.rca.minSecondsPerCollection,
                    accepted.rca.maxSecondsPerCollection
                )
            );
            bytes memory initialData = _generateCollectData(
                _generateCollectParams(
                    accepted.rca,
                    fuzzy.collectParams.collectionId,
                    1,
                    fuzzy.collectParams.dataServiceCut
                )
            );
            vm.prank(accepted.rca.dataService);
            _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), initialData);
        }

        // skip to collectable time
        uint256 collectionSeconds = boundSkip(
            unboundedCollectionSeconds,
            accepted.rca.minSecondsPerCollection,
            accepted.rca.maxSecondsPerCollection
        );
        skip(collectionSeconds);
        uint256 maxTokens = accepted.rca.maxOngoingTokensPerSecond * collectionSeconds;
        maxTokens += testInitialCollection ? accepted.rca.maxInitialTokens : 0;
        uint256 tokens = bound(unboundedTokens, maxTokens + 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            accepted.rca,
            fuzzy.collectParams.collectionId,
            tokens,
            fuzzy.collectParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);
        vm.prank(accepted.rca.dataService);
        uint256 collected = _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
        assertEq(collected, maxTokens);
    }

    function test_Collect_OK(
        FuzzyTestCollect calldata fuzzy,
        uint256 unboundedCollectionSeconds,
        uint256 unboundedTokens
    ) public {
        (IRecurringCollector.SignedRCA memory accepted, ) = _sensibleAuthorizeAndAccept(fuzzy.fuzzyTestAccept);

        (bytes memory data, uint256 collectionSeconds, uint256 tokens) = _generateValidCollection(
            accepted.rca,
            fuzzy.collectParams,
            unboundedCollectionSeconds,
            unboundedTokens
        );
        skip(collectionSeconds);
        _expectCollectCallAndEmit(accepted.rca, _paymentType(fuzzy.unboundedPaymentType), fuzzy.collectParams, tokens);
        vm.prank(accepted.rca.dataService);
        uint256 collected = _recurringCollector.collect(_paymentType(fuzzy.unboundedPaymentType), data);
        assertEq(collected, tokens);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
