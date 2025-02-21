// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphTallyCollector } from "../../../../contracts/interfaces/IGraphTallyCollector.sol";
import { IGraphPayments } from "../../../../contracts/interfaces/IGraphPayments.sol";

import { GraphTallyTest } from "../GraphTallyCollector.t.sol";

contract GraphTallyCollectTest is GraphTallyTest {
    /*
     * HELPERS
     */

    struct CollectTestParams {
        uint256 tokens;
        address allocationId;
        address payer;
        address indexer;
        address collector;
    }

    function _getQueryFeeEncodedData(
        uint256 _signerPrivateKey,
        CollectTestParams memory params
    ) private view returns (bytes memory) {
        IGraphTallyCollector.ReceiptAggregateVoucher memory rav = _getRAV(
            params.allocationId,
            params.payer,
            params.indexer,
            params.collector,
            uint128(params.tokens)
        );
        bytes32 messageHash = graphTallyCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IGraphTallyCollector.SignedRAV memory signedRAV = IGraphTallyCollector.SignedRAV(rav, signature);
        return abi.encode(signedRAV);
    }

    function _getRAV(
        address _allocationId,
        address _payer,
        address _indexer,
        address _dataService,
        uint128 _tokens
    ) private pure returns (IGraphTallyCollector.ReceiptAggregateVoucher memory rav) {
        return
            IGraphTallyCollector.ReceiptAggregateVoucher({
                collectionId: bytes32(uint256(uint160(_allocationId))),
                payer: _payer,
                dataService: _dataService,
                serviceProvider: _indexer,
                timestampNs: 0,
                valueAggregate: _tokens,
                metadata: abi.encode("")
            });
    }

    /*
     * TESTS
     */

    function testGraphTally_Collect(
        uint256 tokens
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });

        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_Multiple(
        uint256 tokens,
        uint8 steps
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        steps = uint8(bound(steps, 1, 100));
        tokens = bound(tokens, steps, type(uint128).max);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        resetPrank(users.verifier);
        uint256 payed = 0;
        uint256 tokensPerStep = tokens / steps;
        for (uint256 i = 0; i < steps; i++) {
            CollectTestParams memory params = CollectTestParams({
                tokens: payed + tokensPerStep,
                allocationId: _allocationId,
                payer: users.gateway,
                indexer: users.indexer,
                collector: users.verifier
            });
            bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);
            _collect(IGraphPayments.PaymentTypes.QueryFee, data);
            payed += tokensPerStep;
        }
    }

    function testGraphTally_Collect_RevertWhen_NoProvision(uint256 tokens) public useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorUnauthorizedDataService.selector,
            users.verifier
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_RevertWhen_ProvisionEmpty(
        uint256 tokens
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        // thaw tokens from the provision
        resetPrank(users.indexer);
        staking.thaw(users.indexer, users.verifier, 100);

        tokens = bound(tokens, 1, type(uint128).max);

        resetPrank(users.gateway);
        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorUnauthorizedDataService.selector,
            users.verifier
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_PreventSignerAttack(
        uint256 tokens
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);

        resetPrank(users.gateway);
        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        // The sender authorizes another signer
        (address anotherSigner, uint256 anotherSignerPrivateKey) = makeAddrAndKey("anotherSigner");
        {
            uint256 proofDeadline = block.timestamp + 1;
            bytes memory anotherSignerProof = _getSignerProof(proofDeadline, anotherSignerPrivateKey);
            _authorizeSigner(anotherSigner, proofDeadline, anotherSignerProof);
        }

        // And crafts a RAV using the new signer as the data service
        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: anotherSigner
        });
        bytes memory data = _getQueryFeeEncodedData(anotherSignerPrivateKey, params);

        // the call should revert because the service provider has no provision with the "data service"
        resetPrank(anotherSigner);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorUnauthorizedDataService.selector,
            anotherSigner
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_RevertWhen_CallerNotDataService(uint256 tokens) public useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);

        resetPrank(users.gateway);
        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.indexer);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorCallerNotDataService.selector,
            users.indexer,
            users.verifier
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_RevertWhen_PayerMismatch(
        uint256 tokens
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);

        resetPrank(users.gateway);
        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        (address anotherPayer, ) = makeAddrAndKey("anotherPayer");
        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: anotherPayer,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        vm.expectRevert(IGraphTallyCollector.GraphTallyCollectorInvalidRAVSigner.selector);
        graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_RevertWhen_InconsistentRAVTokens(
        uint256 tokens
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);
        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);

        // Attempt to collect again
        vm.expectRevert(
            abi.encodeWithSelector(
                IGraphTallyCollector.GraphTallyCollectorInconsistentRAVTokens.selector,
                tokens,
                tokens
            )
        );
        graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_RevertWhen_SignerNotAuthorized(uint256 tokens) public useGateway {
        tokens = bound(tokens, 1, type(uint128).max);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        vm.expectRevert(abi.encodeWithSelector(IGraphTallyCollector.GraphTallyCollectorInvalidRAVSigner.selector));
        graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_ThawingSigner(
        uint256 tokens
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        // Start thawing signer
        _thawSigner(signer);
        skip(revokeSignerThawingPeriod + 1);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_RevertIf_SignerWasRevoked(uint256 tokens) public useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        // Start thawing signer
        _thawSigner(signer);
        skip(revokeSignerThawingPeriod + 1);
        _revokeAuthorizedSigner(signer);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        vm.expectRevert(abi.encodeWithSelector(IGraphTallyCollector.GraphTallyCollectorInvalidRAVSigner.selector));
        graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_Collect_ThawingSignerCanceled(
        uint256 tokens
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        // Start thawing signer
        _thawSigner(signer);
        skip(revokeSignerThawingPeriod + 1);
        _cancelThawSigner(signer);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testGraphTally_CollectPartial(
        uint256 tokens,
        uint256 tokensToCollect
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        tokensToCollect = bound(tokensToCollect, 1, tokens);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data, tokensToCollect);
    }

    function testGraphTally_CollectPartial_RevertWhen_AmountTooHigh(
        uint256 tokens,
        uint256 tokensToCollect
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max - 1);

        _depositTokens(address(graphTallyCollector), users.indexer, tokens);

        CollectTestParams memory params = CollectTestParams({
            tokens: tokens,
            allocationId: _allocationId,
            payer: users.gateway,
            indexer: users.indexer,
            collector: users.verifier
        });
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, params);

        resetPrank(users.verifier);
        uint256 tokensAlreadyCollected = graphTallyCollector.tokensCollected(
            users.verifier,
            bytes32(uint256(uint160(_allocationId))),
            users.indexer,
            users.gateway
        );
        tokensToCollect = bound(tokensToCollect, tokens - tokensAlreadyCollected + 1, type(uint128).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGraphTallyCollector.GraphTallyCollectorInvalidTokensToCollectAmount.selector,
                tokensToCollect,
                tokens - tokensAlreadyCollected
            )
        );
        graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data, tokensToCollect);
    }

    function testGraphTally_Collect_SeparateAllocationTracking(
        uint256 tokens
    ) public useIndexer useProvisionDataService(users.verifier, 100, 0, 0) useGateway useSigner {
        tokens = bound(tokens, 1, type(uint64).max);
        uint8 numAllocations = 10;

        _depositTokens(address(graphTallyCollector), users.indexer, tokens * numAllocations);
        // Array with collectTestParams for each allocation
        CollectTestParams[] memory collectTestParams = new CollectTestParams[](numAllocations);

        // Collect tokens for each allocation
        resetPrank(users.verifier);
        for (uint256 i = 0; i < numAllocations; i++) {
            address allocationId = makeAddr(string.concat("allocation", vm.toString(i)));
            collectTestParams[i] = CollectTestParams({
                tokens: tokens,
                allocationId: allocationId,
                payer: users.gateway,
                indexer: users.indexer,
                collector: users.verifier
            });
            bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, collectTestParams[i]);
            _collect(IGraphPayments.PaymentTypes.QueryFee, data);
        }

        for (uint256 i = 0; i < numAllocations; i++) {
            assertEq(
                graphTallyCollector.tokensCollected(
                    collectTestParams[i].collector,
                    bytes32(uint256(uint160(collectTestParams[i].allocationId))),
                    collectTestParams[i].indexer,
                    collectTestParams[i].payer
                ),
                collectTestParams[i].tokens,
                "Incorrect tokens collected for allocation"
            );

            // Try to collect again with the same allocation - should revert
            bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, collectTestParams[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGraphTallyCollector.GraphTallyCollectorInconsistentRAVTokens.selector,
                    tokens,
                    tokens
                )
            );
            graphTallyCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
        }

        // Increase tokens for allocation 0 by 1000 ether and collect again
        resetPrank(users.gateway);
        _depositTokens(address(graphTallyCollector), users.indexer, 1000 ether);

        resetPrank(users.verifier);
        collectTestParams[0].tokens = tokens + 1000 ether;
        bytes memory allocation0Data = _getQueryFeeEncodedData(signerPrivateKey, collectTestParams[0]);
        _collect(IGraphPayments.PaymentTypes.QueryFee, allocation0Data);
    }
}
