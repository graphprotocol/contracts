// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IGraphTallyCollector } from "@graphprotocol/horizon/contracts/interfaces/IGraphTallyCollector.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

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

    function _getSignerProof(uint256 _proofDeadline, uint256 _signer) private returns (bytes memory) {
        (, address msgSender, ) = vm.readCallers();
        bytes32 messageHash = keccak256(
            abi.encodePacked(block.chainid, address(graphTallyCollector), _proofDeadline, msgSender)
        );
        bytes32 proofToDigest = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signer, proofToDigest);
        return abi.encodePacked(r, s, v);
    }

    function _getQueryFeeEncodedData(address indexer, uint128 tokens) private view returns (bytes memory) {
        IGraphTallyCollector.ReceiptAggregateVoucher memory rav = _getRAV(
            indexer,
            bytes32(uint256(uint160(allocationID))),
            tokens
        );
        bytes32 messageHash = graphTallyCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IGraphTallyCollector.SignedRAV memory signedRAV = IGraphTallyCollector.SignedRAV(rav, signature);
        return abi.encode(signedRAV);
    }

    function _getRAV(
        address indexer,
        bytes32 collectionId,
        uint128 tokens
    ) private view returns (IGraphTallyCollector.ReceiptAggregateVoucher memory rav) {
        return
            IGraphTallyCollector.ReceiptAggregateVoucher({
                collectionId: collectionId,
                payer: users.gateway,
                serviceProvider: indexer,
                dataService: address(subgraphService),
                timestampNs: 0,
                valueAggregate: tokens,
                metadata: ""
            });
    }

    function _deposit(uint256 tokens) private {
        token.approve(address(escrow), tokens);
        escrow.deposit(address(graphTallyCollector), users.indexer, tokens);
    }

    function _authorizeSigner() private {
        uint256 proofDeadline = block.timestamp + 1;
        bytes memory proof = _getSignerProof(proofDeadline, signerPrivateKey);
        graphTallyCollector.authorizeSigner(signer, proofDeadline, proof);
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
        uint256 tokensAllocated,
        uint256 tokensPayment
    ) public useIndexer useAllocation(tokensAllocated) {
        vm.assume(tokensAllocated > minimumProvisionTokens * stakeToFeesRatio);
        uint256 maxTokensPayment = tokensAllocated / stakeToFeesRatio > type(uint128).max
            ? type(uint128).max
            : tokensAllocated / stakeToFeesRatio;
        tokensPayment = bound(tokensPayment, minimumProvisionTokens, maxTokensPayment);

        resetPrank(users.gateway);
        _deposit(tokensPayment);
        _authorizeSigner();

        resetPrank(users.indexer);
        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokensPayment));
        _collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testCollect_MultipleQueryFees(
        uint256 tokensAllocated,
        uint8 numPayments
    ) public useIndexer useAllocation(tokensAllocated) {
        vm.assume(tokensAllocated > minimumProvisionTokens * stakeToFeesRatio);
        numPayments = uint8(bound(numPayments, 2, 10));
        uint256 tokensPayment = tokensAllocated / stakeToFeesRatio / numPayments;

        resetPrank(users.gateway);
        _deposit(tokensAllocated);
        _authorizeSigner();

        resetPrank(users.indexer);
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
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidRAV.selector, newIndexer, users.indexer)
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

    function testCollect_QueryFees_RevertWhen_CollectionIdTooLarge() public useIndexer useAllocation(1000 ether) {
        bytes32 collectionId = keccak256(abi.encodePacked("Large collection id, longer than 160 bits"));
        IGraphTallyCollector.ReceiptAggregateVoucher memory rav = _getRAV(users.indexer, collectionId, 1000 ether);
        bytes32 messageHash = graphTallyCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IGraphTallyCollector.SignedRAV memory signedRAV = IGraphTallyCollector.SignedRAV(rav, signature);
        bytes memory data = abi.encode(signedRAV);
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidCollectionId.selector, collectionId)
        );
        subgraphService.collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data);
    }
}
