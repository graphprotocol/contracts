// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { ITAPCollector } from "@graphprotocol/horizon/contracts/interfaces/ITAPCollector.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceRegisterTest is SubgraphServiceTest {
    using PPMMath for uint128;
    using PPMMath for uint256;

    address signer;
    uint256 signerPrivateKey;

    /*
     * HELPERS
     */

    function _getQueryFeeEncodedData(
        address indexer,
        uint128 tokens
    ) private view returns (bytes memory) {
        ITAPCollector.ReceiptAggregateVoucher memory rav = _getRAV(indexer, tokens);
        bytes32 messageHash = tapCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        ITAPCollector.SignedRAV memory signedRAV = ITAPCollector.SignedRAV(rav, signature);
        return abi.encode(signedRAV);
    }

    function _getRAV(address indexer, uint128 tokens) private view returns (ITAPCollector.ReceiptAggregateVoucher memory rav) {
        return ITAPCollector.ReceiptAggregateVoucher({
            dataService: address(subgraphService),
            serviceProvider: indexer,
            timestampNs: 0,
            valueAggregate: tokens,
            metadata: abi.encode(allocationID)
        });
    }

    function _approveCollector(uint128 tokens) private {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        resetPrank(signer);
        mint(signer, tokens);
        escrow.approveCollector(address(tapCollector), tokens);
        token.approve(address(escrow), tokens);
        escrow.deposit(users.indexer, tokens);
        resetPrank(msgSender);
    }

    /*
     * SET UP
     */

    function setUp() public virtual override {
        super.setUp();
        (signer, signerPrivateKey) = makeAddrAndKey("signer");
        vm.label({ account: signer, newLabel: "signer" });
    }

    /*
     * TESTS
     */

    function testCollect_QueryFees(
        uint256 tokens,
        uint256 tokensPayment
    ) public useIndexer useAllocation(tokens) {
        vm.assume(tokens > minimumProvisionTokens * stakeToFeesRatio);
        uint256 maxTokensPayment = tokens / stakeToFeesRatio > type(uint128).max ? type(uint128).max : tokens / stakeToFeesRatio;
        tokensPayment = bound(tokensPayment, minimumProvisionTokens, maxTokensPayment);
        uint128 tokensPayment128 = uint128(tokensPayment);
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.QueryFee;
        bytes memory data = _getQueryFeeEncodedData(users.indexer, tokensPayment128);
        
        uint256 indexerPreviousBalance = token.balanceOf(users.indexer);
        
        _approveCollector(tokensPayment128);
        subgraphService.collect(users.indexer, paymentType, data);
        
        uint256 indexerBalance = token.balanceOf(users.indexer);
        uint256 tokensProtocol = tokensPayment128.mulPPM(protocolPaymentCut);
        uint256 curationTokens = tokensPayment128.mulPPMRoundUp(curationCut);
        uint256 dataServiceTokens = tokensPayment128.mulPPM(serviceCut + curationCut) - curationTokens;

        uint256 expectedIndexerTokensPayment = tokensPayment128 - tokensProtocol - dataServiceTokens - curationTokens;
        assertEq(indexerBalance, indexerPreviousBalance + expectedIndexerTokensPayment);
    }

    function testCollect_IndexingFees(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI1"));

        uint256 indexerPreviousProvisionBalance = staking.getProviderTokensAvailable(users.indexer, address(subgraphService));
        subgraphService.collect(users.indexer, paymentType, data);

        uint256 indexerProvisionBalance = staking.getProviderTokensAvailable(users.indexer, address(subgraphService));
        assertEq(indexerProvisionBalance, indexerPreviousProvisionBalance + tokens.mulPPM(rewardsPerSignal));
    }

    function testCollect_RevertWhen_InvalidPayment(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes invalidPaymentType = IGraphPayments.PaymentTypes.IndexingFee;
        vm.expectRevert(abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceInvalidPaymentType.selector,
            invalidPaymentType
        ));
        subgraphService.collect(users.indexer, invalidPaymentType, "");
    }

    function testCollect_RevertWhen_NotAuthorized(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.QueryFee;
        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokens));
        resetPrank(users.operator);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            users.operator,
            users.indexer
        ));
        subgraphService.collect(users.indexer, paymentType, data);
    }

    function testCollect_QueryFees_RevertWhen_IndexerIsNotAllocationOwner(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.QueryFee;
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);
        bytes memory data = _getQueryFeeEncodedData(newIndexer, uint128(tokens));
        // Attempt to collect from other indexer's allocation
        vm.expectRevert(abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotAuthorized.selector,
            newIndexer,
            allocationID
        ));
        subgraphService.collect(newIndexer, paymentType, data);
    }

    function testCollect_IndexingFees_RevertWhen_IndexerIsNotAllocationOwner(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);
        bytes memory data = abi.encode(allocationID, bytes32("POI1"));
        // Attempt to collect from other indexer's allocation
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerIndexerNotAuthorized.selector,
            newIndexer,
            allocationID
        ));
        subgraphService.collect(newIndexer, paymentType, data);
    }
}
