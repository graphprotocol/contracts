// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";

import { IRecurringCollector } from "../../../contracts/interfaces/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorCollectTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Collect_Revert_WhenInvalidPaymentType(uint8 unboundedPaymentType, bytes memory data) public {
        uint256 lastPaymentType = uint256(IGraphPayments.PaymentTypes.IndexingRewards);

        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes(
            bound(unboundedPaymentType, 0, lastPaymentType)
        );
        vm.assume(paymentType != IGraphPayments.PaymentTypes.IndexingFee);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidPaymentType.selector,
            paymentType
        );
        vm.expectRevert(expectedErr);
        _recurringCollector.collect(paymentType, data);

        // If I move this to the top of the function, the rest of the test does not run. Not sure why...
        {
            vm.expectRevert();
            IGraphPayments.PaymentTypes(lastPaymentType + 1);
        }
    }

    function test_Collect_Revert_WhenInvalidData(address caller, bytes memory data) public {
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidCollectData.selector,
            data
        );
        vm.expectRevert(expectedErr);
        vm.prank(caller);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCallerNotDataService(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory params,
        uint256 unboundedKey,
        address notDataService
    ) public {
        vm.assume(rca.dataService != notDataService);
        rca = _sensibleRCA(rca);
        params.agreementId = rca.agreementId;
        bytes memory data = _generateCollectData(params);

        _authorizeAndAccept(rca, boundKey(unboundedKey));
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            params.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenUnknownAgreement(TestCollectParams memory params) public {
        bytes memory data = _generateCollectData(params.collectData);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNeverAccepted.selector,
            params.collectData.agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCanceledAgreement(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        TestCollectParams memory testCollectParams,
        uint256 unboundedKey
    ) public {
        rca = _sensibleRCA(rca);
        _authorizeAndAccept(rca, boundKey(unboundedKey));
        _cancel(rca);
        IRecurringCollector.CollectParams memory fuzzyParams = testCollectParams.collectData;
        fuzzyParams.tokens = bound(fuzzyParams.tokens, 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementCanceled.selector,
            collectParams.agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenAgreementElapsed(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedAcceptAt,
        uint256 unboundedCollectAt
    ) public {
        rca = _sensibleRCA(rca);
        // ensure agreement is short lived
        rca.duration = bound(rca.duration, rca.minSecondsPerCollection + 7200, rca.maxSecondsPerCollection * 100);
        // skip to sometime in the future when there is still plenty of time after the agreement elapsed
        skip(boundSkipCeil(unboundedAcceptAt, type(uint256).max - (rca.duration * 10)));
        uint256 agreementEnd = block.timestamp + rca.duration;
        _authorizeAndAccept(rca, boundKey(unboundedKey));
        // skip to sometime after agreement elapsed
        skip(boundSkip(unboundedCollectAt, rca.duration + 1, orTillEndOfTime(type(uint256).max)));

        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementElapsed.selector,
            collectParams.agreementId,
            agreementEnd
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooSoon(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedAcceptAt,
        uint256 unboundedSkip
    ) public {
        rca = _sensibleRCA(rca);
        // skip to sometime in the future when there are still plenty of collections left
        skip(boundSkipCeil(unboundedAcceptAt, type(uint256).max - (rca.maxSecondsPerCollection * 10)));
        _authorizeAndAccept(rca, boundKey(unboundedKey));

        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(
            _generateCollectParams(rca, fuzzyParams.collectionId, 1, fuzzyParams.dataServiceCut)
        );
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);

        uint256 collectionSeconds = boundSkipCeil(unboundedSkip, rca.minSecondsPerCollection - 1);
        skip(collectionSeconds);
        fuzzyParams.tokens = bound(fuzzyParams.tokens, 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectionTooSoon.selector,
            collectParams.agreementId,
            collectionSeconds,
            rca.minSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooLate(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedAcceptAt,
        uint256 unboundedFirstCollectionSkip,
        uint256 unboundedSkip
    ) public {
        rca = _sensibleRCA(rca);
        // skip to sometime in the future when there are still plenty of collections left
        skip(boundSkipCeil(unboundedAcceptAt, type(uint256).max - (rca.maxSecondsPerCollection * 10)));
        uint256 acceptedAt = block.timestamp;
        _authorizeAndAccept(rca, boundKey(unboundedKey));

        // skip to collectable time
        skip(boundSkip(unboundedFirstCollectionSkip, rca.minSecondsPerCollection, rca.maxSecondsPerCollection));
        bytes memory data = _generateCollectData(
            _generateCollectParams(rca, fuzzyParams.collectionId, 1, fuzzyParams.dataServiceCut)
        );
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);

        uint256 durationLeft = orTillEndOfTime(rca.duration - (block.timestamp - acceptedAt));
        // skip beyond collectable time but still within the agreement duration
        uint256 collectionSeconds = boundSkip(unboundedSkip, rca.maxSecondsPerCollection + 1, durationLeft);
        skip(collectionSeconds);

        fuzzyParams.tokens = bound(fuzzyParams.tokens, 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectionTooLate.selector,
            collectParams.agreementId,
            collectionSeconds,
            rca.maxSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooMuch(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedInitialCollectionSkip,
        uint256 unboundedCollectionSkip,
        uint256 unboundedTokens,
        bool testInitialCollection
    ) public {
        rca = _sensibleRCA(rca);
        _authorizeAndAccept(rca, boundKey(unboundedKey));

        if (!testInitialCollection) {
            // skip to collectable time
            skip(boundSkip(unboundedInitialCollectionSkip, rca.minSecondsPerCollection, rca.maxSecondsPerCollection));
            bytes memory initialData = _generateCollectData(
                _generateCollectParams(rca, fuzzyParams.collectionId, 1, fuzzyParams.dataServiceCut)
            );
            vm.prank(rca.dataService);
            _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, initialData);
        }

        // skip to collectable time
        uint256 collectionSeconds = boundSkip(
            unboundedCollectionSkip,
            rca.minSecondsPerCollection,
            rca.maxSecondsPerCollection
        );
        skip(collectionSeconds);
        uint256 maxTokens = rca.maxOngoingTokensPerSecond * collectionSeconds;
        maxTokens += testInitialCollection ? rca.maxInitialTokens : 0;
        uint256 tokens = bound(unboundedTokens, maxTokens + 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            tokens,
            fuzzyParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectAmountTooHigh.selector,
            collectParams.agreementId,
            tokens,
            maxTokens
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_OK(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedCollectionSkip,
        uint256 unboundedTokens
    ) public {
        rca = _sensibleRCA(rca);
        _authorizeAndAccept(rca, boundKey(unboundedKey));

        (bytes memory data, uint256 collectionSeconds, uint256 tokens) = _generateValidCollection(
            rca,
            fuzzyParams,
            unboundedCollectionSkip,
            unboundedTokens
        );
        skip(collectionSeconds);
        _expectCollectCallAndEmit(rca, fuzzyParams, tokens);
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
