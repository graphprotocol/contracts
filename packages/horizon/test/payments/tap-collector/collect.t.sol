// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { ITAPCollector } from "../../../contracts/interfaces/ITAPCollector.sol";
import { IPaymentsCollector } from "../../../contracts/interfaces/IPaymentsCollector.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { TAPCollector } from "../../../contracts/payments/collectors/TAPCollector.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";

import { TAPCollectorTest } from "./TAPCollector.t.sol";

contract TAPCollectorCollectTest is TAPCollectorTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function testCollect(uint256 tokens) public useGateway usePayerSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);
        
        bytes memory data = _getQueryFeeEncodedData(users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testCollect_Multiple(uint256 tokens, uint8 steps) public useGateway usePayerSigner {
        steps = uint8(bound(steps, 1, 100));
        tokens = bound(tokens, steps, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);

        resetPrank(users.verifier);
        uint256 payed = 0;
        uint256 tokensPerStep = tokens / steps;
        for (uint256 i = 0; i < steps; i++) {
            bytes memory data = _getQueryFeeEncodedData(users.indexer, users.verifier, uint128(payed + tokensPerStep));
            _collect(IGraphPayments.PaymentTypes.QueryFee, data);
            payed += tokensPerStep;
        }
    }

    function testCollect_RevertWhen_CallerNotDataService(uint256 tokens) public useGateway usePayerSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        
        resetPrank(users.gateway);
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);

        bytes memory data = _getQueryFeeEncodedData(users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.indexer);
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorCallerNotDataService.selector,
            users.indexer,
            users.verifier
        );
        vm.expectRevert(expectedError);
        tapCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testCollect_RevertWhen_InconsistentRAVTokens(uint256 tokens) public useGateway usePayerSigner {
        tokens = bound(tokens, 1, type(uint128).max);
        
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);
        bytes memory data = _getQueryFeeEncodedData(users.indexer, users.verifier, uint128(tokens));

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
}
