// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IHorizonStakingMain } from "../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { ITAPCollector } from "../../contracts/interfaces/ITAPCollector.sol";
import { IPaymentsCollector } from "../../contracts/interfaces/IPaymentsCollector.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";
import { TAPCollector } from "../../contracts/payments/collectors/TAPCollector.sol";
import { PPMMath } from "../../contracts/libraries/PPMMath.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";
import { PaymentsEscrowSharedTest } from "../shared/payments-escrow/PaymentsEscrowShared.t.sol";

contract TAPCollectorTest is HorizonStakingSharedTest, PaymentsEscrowSharedTest {
    using PPMMath for uint256;

    address payer;
    uint256 payerPrivateKey;

    /*
     * HELPERS
     */

    function _getQueryFeeEncodedData(address indexer, address collector, uint128 tokens) private view returns (bytes memory) {
        ITAPCollector.ReceiptAggregateVoucher memory rav = _getRAV(indexer, collector, tokens);
        bytes32 messageHash = tapCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        ITAPCollector.SignedRAV memory signedRAV = ITAPCollector.SignedRAV(rav, signature);
        return abi.encode(signedRAV);
    }

    function _getRAV(
        address indexer,
        address collector,
        uint128 tokens
    ) private pure returns (ITAPCollector.ReceiptAggregateVoucher memory rav) {
        return
            ITAPCollector.ReceiptAggregateVoucher({
                dataService: collector,
                serviceProvider: indexer,
                timestampNs: 0,
                valueAggregate: tokens,
                metadata: abi.encode("")
            });
    }

    function _collect(IGraphPayments.PaymentTypes _paymentType, bytes memory _data) private {
        (ITAPCollector.SignedRAV memory signedRAV, uint256 dataServiceCut) = abi.decode(_data, (ITAPCollector.SignedRAV, uint256));
        bytes32 messageHash = tapCollector.encodeRAV(signedRAV.rav);
        address _payer = ECDSA.recover(messageHash, signedRAV.signature);
        uint256 tokensAlreadyCollected = tapCollector.tokensCollected(signedRAV.rav.dataService, signedRAV.rav.serviceProvider, _payer);
        uint256 tokensToCollect = signedRAV.rav.valueAggregate - tokensAlreadyCollected;
        uint256 tokensDataService = tokensToCollect.mulPPM(dataServiceCut);
        
        vm.expectEmit(address(tapCollector));
        emit IPaymentsCollector.PaymentCollected(
            _paymentType, 
            _payer,
            signedRAV.rav.serviceProvider,
            tokensToCollect,
            signedRAV.rav.dataService,
            tokensDataService
        );
        emit ITAPCollector.RAVCollected(
            _payer,
            signedRAV.rav.dataService,
            signedRAV.rav.serviceProvider,
            signedRAV.rav.timestampNs,
            signedRAV.rav.valueAggregate,
            signedRAV.rav.metadata,
            signedRAV.signature
        );
        
        uint256 tokensCollected = tapCollector.collect(_paymentType, _data);
        assertEq(tokensCollected, tokensToCollect);

        uint256 tokensCollectedAfter = tapCollector.tokensCollected(signedRAV.rav.dataService, signedRAV.rav.serviceProvider, _payer);
        assertEq(tokensCollectedAfter, signedRAV.rav.valueAggregate);
    }

    /*
     * SET UP
     */

    function setUp() public virtual override {
        super.setUp();
        (payer, payerPrivateKey) = makeAddrAndKey("payer");
        vm.label({ account: payer, newLabel: "payer" });
        deal({ token: address(token), to: payer, give: type(uint256).max });
    }

    /*
     * TESTS
     */

    function testCollect(uint256 tokens) public {
        tokens = bound(tokens, 1, type(uint128).max);
        
        resetPrank(payer);
        _approveCollector(address(tapCollector), tokens);
        _depositTokens(address(tapCollector), users.indexer, tokens);
        bytes memory data = _getQueryFeeEncodedData(users.indexer, users.verifier, uint128(tokens));

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testCollect_Multiple(uint256 tokens, uint8 steps) public {
        steps = uint8(bound(steps, 1, 100));
        tokens = bound(tokens, steps, type(uint128).max);
        
        resetPrank(payer);
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

    function testCollect_RevertWhen_CallerNotDataService(uint256 tokens) public {
        tokens = bound(tokens, 1, type(uint128).max);
        
        resetPrank(payer);
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

    function testCollect_RevertWhen_InconsistentRAVTokens(uint256 tokens) public {
        tokens = bound(tokens, 1, type(uint128).max);
        
        resetPrank(payer);
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
