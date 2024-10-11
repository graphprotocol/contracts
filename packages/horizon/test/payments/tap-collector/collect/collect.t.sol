// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ITAPCollector } from "../../../../contracts/interfaces/ITAPCollector.sol";
import { IGraphPayments } from "../../../../contracts/interfaces/IGraphPayments.sol";

import { TAPCollectorTest } from "../TAPCollector.t.sol";

contract TAPCollectorCollectTest is TAPCollectorTest {

    /*
    * HELPERS
    */

    function _getQueryFeeEncodedData(
        uint256 _signerPrivateKey,
        address _indexer,
        address _collector,
        uint128 _tokens
    ) private view returns (bytes memory) {
        ITAPCollector.ReceiptAggregateVoucher memory rav = _getRAV(_indexer, _collector, _tokens);
        bytes32 messageHash = tapCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        ITAPCollector.SignedRAV memory signedRAV = ITAPCollector.SignedRAV(rav, signature);
        return abi.encode(signedRAV);
    }

    function _getRAV(
        address _indexer,
        address _collector,
        uint128 _tokens
    ) private pure returns (ITAPCollector.ReceiptAggregateVoucher memory rav) {
        return
            ITAPCollector.ReceiptAggregateVoucher({
                dataService: _collector,
                serviceProvider: _indexer,
                timestampNs: 0,
                valueAggregate: _tokens,
                metadata: abi.encode("")
            });
    }

    /*
     * TESTS
     */

    function testTAPCollector_Collect(uint256 tokens) public useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);
        
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testTAPCollector_Collect_Multiple(uint256 tokens, uint8 steps) public useGateway useSigner {
        steps = uint8(bound(steps, 1, 100));
        tokens = bound(tokens, steps, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);

        resetPrank(users.verifier);
        uint256 payed = 0;
        uint256 tokensPerStep = tokens / steps;
        for (uint256 i = 0; i < steps; i++) {
            bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, users.indexer, users.verifier, uint128(payed + tokensPerStep));
            _collect(IGraphPayments.PaymentTypes.QueryFee, data);
            payed += tokensPerStep;
        }
    }

    function testTAPCollector_Collect_RevertWhen_CallerNotDataService(uint256 tokens) public useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        
        resetPrank(users.gateway);
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);

        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.indexer);
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorCallerNotDataService.selector,
            users.indexer,
            users.verifier
        );
        vm.expectRevert(expectedError);
        tapCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testTAPCollector_Collect_RevertWhen_InconsistentRAVTokens(uint256 tokens) public useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);

        // Attempt to collect again
        vm.expectRevert(abi.encodeWithSelector(
            ITAPCollector.TAPCollectorInconsistentRAVTokens.selector, 
            tokens,
            tokens
        ));
        tapCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testTAPCollector_Collect_RevertWhen_SignerNotAuthorized(uint256 tokens) public useGateway {
        tokens = bound(tokens, 1, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);
        
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.verifier);
        vm.expectRevert(abi.encodeWithSelector(ITAPCollector.TAPCollectorInvalidRAVSigner.selector));
        tapCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testTAPCollector_Collect_ThawingSigner(uint256 tokens) public useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);

        // Start thawing signer
        _thawSigner(signer);
        skip(revokeSignerThawingPeriod + 1);
        
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testTAPCollector_Collect_RevertIf_SignerWasRevoked(uint256 tokens) public useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);

        // Start thawing signer
        _thawSigner(signer);
        skip(revokeSignerThawingPeriod + 1);
        _revokeAuthorizedSigner(signer);
        
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.verifier);
        vm.expectRevert(abi.encodeWithSelector(ITAPCollector.TAPCollectorInvalidRAVSigner.selector));
        tapCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testTAPCollector_Collect_ThawingSignerCanceled(uint256 tokens) public useGateway useSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);

        // Start thawing signer
        _thawSigner(signer);
        skip(revokeSignerThawingPeriod + 1);
        _cancelThawSigner(signer);
        
        bytes memory data = _getQueryFeeEncodedData(signerPrivateKey, users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }
}
