// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

// import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { ITAPCollector } from "@graphprotocol/horizon/contracts/interfaces/ITAPCollector.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../../SubgraphService.t.sol";

contract SubgraphServiceRegisterTest is SubgraphServiceTest {
    using PPMMath for uint128;
    using PPMMath for uint256;

    address signer;
    uint256 signerPrivateKey;

    /*
     * HELPERS
     */

    function _getQueryFeeEncodedData(address indexer, uint128 tokens) private view returns (bytes memory) {
        ITAPCollector.ReceiptAggregateVoucher memory rav = _getRAV(indexer, tokens);
        bytes32 messageHash = tapCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        ITAPCollector.SignedRAV memory signedRAV = ITAPCollector.SignedRAV(rav, signature);
        return abi.encode(signedRAV);
    }

    function _getRAV(
        address indexer,
        uint128 tokens
    ) private view returns (ITAPCollector.ReceiptAggregateVoucher memory rav) {
        return
            ITAPCollector.ReceiptAggregateVoucher({
                dataService: address(subgraphService),
                serviceProvider: indexer,
                timestampNs: 0,
                valueAggregate: tokens,
                metadata: abi.encode(allocationID)
            });
    }

    function _approveCollector(uint256 tokens) private {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        resetPrank(signer);
        mint(signer, tokens);
        escrow.approveCollector(address(tapCollector), tokens);
        token.approve(address(escrow), tokens);
        escrow.deposit(address(tapCollector), users.indexer, tokens);
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

    function testCollect_QueryFees_ONLY_THIS(
        uint256 tokensAllocated,
        uint256 tokensPayment
    ) public useIndexer useAllocation(tokensAllocated) {
        vm.assume(tokensAllocated > minimumProvisionTokens * stakeToFeesRatio);
        uint256 maxTokensPayment = tokensAllocated / stakeToFeesRatio > type(uint128).max
            ? type(uint128).max
            : tokensAllocated / stakeToFeesRatio;
        tokensPayment = bound(tokensPayment, minimumProvisionTokens, maxTokensPayment);

        _approveCollector(tokensPayment);

        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokensPayment));
        _collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testCollect_MultipleQueryFees(
        uint256 tokensAllocated,
        uint256 numPayments
    ) public useIndexer useAllocation(tokensAllocated) {
        vm.assume(tokensAllocated > minimumProvisionTokens * stakeToFeesRatio);
        numPayments = bound(numPayments, 1, 10);
        uint256 tokensPayment = tokensAllocated / stakeToFeesRatio / numPayments;

        _approveCollector(tokensAllocated);

        uint256 accTokensPayment = 0;
        for (uint i = 0; i < numPayments; i++) {
            accTokensPayment = accTokensPayment + tokensPayment;
            bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(accTokensPayment));
            _collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data);
        }
    }

    function testCollect_RevertWhen_NotAuthorized(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.QueryFee;
        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokens));
        resetPrank(users.operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerNotAuthorized.selector,
                users.indexer,
                users.operator
            )
        );
        subgraphService.collect(users.indexer, paymentType, data);
    }

    function testCollect_QueryFees_RevertWhen_IndexerIsNotAllocationOwner(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.QueryFee;
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);

        // This data is for user.indexer allocationId
        bytes memory data = _getQueryFeeEncodedData(newIndexer, uint128(tokens));

        resetPrank(newIndexer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceInvalidRAV.selector,
                newIndexer,
                users.indexer
            )
        );
        subgraphService.collect(newIndexer, paymentType, data);
    }

    function testCollect_QueryFees_RevertWhen_CollectingOtherIndexersFees(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.QueryFee;
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);
        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokens));
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceIndexerMismatch.selector, users.indexer, newIndexer)
        );
        subgraphService.collect(newIndexer, paymentType, data);
    }
}
