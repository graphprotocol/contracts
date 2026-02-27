// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IGraphTallyCollector } from "@graphprotocol/interfaces/contracts/horizon/IGraphTallyCollector.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { SubgraphServiceTest } from "../../SubgraphService.t.sol";

contract SubgraphServiceRegisterTest is SubgraphServiceTest {
    using PPMMath for uint128;
    using PPMMath for uint256;

    address signer;
    uint256 signerPrivateKey;

    /*
     * HELPERS
     */

    function _getSignerProof(uint256 _proofDeadline, uint256 _signer) private view returns (bytes memory) {
        (, address msgSender, ) = vm.readCallers();
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                block.chainid,
                address(graphTallyCollector),
                "authorizeSignerProof",
                _proofDeadline,
                msgSender
            )
        );
        bytes32 proofToDigest = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signer, proofToDigest);
        return abi.encodePacked(r, s, v);
    }

    function _getQueryFeeEncodedData(
        address indexer,
        uint128 tokens,
        uint256 tokensToCollect
    ) private view returns (bytes memory) {
        IGraphTallyCollector.ReceiptAggregateVoucher memory rav = _getRav(
            indexer,
            bytes32(uint256(uint160(allocationId))),
            tokens
        );
        bytes32 messageHash = graphTallyCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IGraphTallyCollector.SignedRAV memory signedRav = IGraphTallyCollector.SignedRAV(rav, signature);
        return abi.encode(signedRav, tokensToCollect);
    }

    function _getRav(
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
        vm.assume(tokensAllocated > MINIMUM_PROVISION_TOKENS * STAKE_TO_FEES_RATIO);
        uint256 maxTokensPayment = tokensAllocated / STAKE_TO_FEES_RATIO > type(uint128).max
            ? type(uint128).max
            : tokensAllocated / STAKE_TO_FEES_RATIO;
        tokensPayment = bound(tokensPayment, MINIMUM_PROVISION_TOKENS, maxTokensPayment);

        resetPrank(users.gateway);
        _deposit(tokensPayment);
        _authorizeSigner();

        resetPrank(users.indexer);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokensPayment), 0);
        _collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testCollect_QueryFees_WithRewardsDestination(
        uint256 tokensAllocated,
        uint256 tokensPayment
    ) public useIndexer useAllocation(tokensAllocated) {
        vm.assume(tokensAllocated > MINIMUM_PROVISION_TOKENS * STAKE_TO_FEES_RATIO);
        uint256 maxTokensPayment = tokensAllocated / STAKE_TO_FEES_RATIO > type(uint128).max
            ? type(uint128).max
            : tokensAllocated / STAKE_TO_FEES_RATIO;
        tokensPayment = bound(tokensPayment, MINIMUM_PROVISION_TOKENS, maxTokensPayment);

        resetPrank(users.gateway);
        _deposit(tokensPayment);
        _authorizeSigner();

        resetPrank(users.indexer);
        subgraphService.setPaymentsDestination(users.indexer);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokensPayment), 0);
        _collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testCollect_MultipleQueryFees(
        uint256 tokensAllocated,
        uint8 numPayments
    ) public useIndexer useAllocation(tokensAllocated) {
        vm.assume(tokensAllocated > MINIMUM_PROVISION_TOKENS * STAKE_TO_FEES_RATIO);
        numPayments = uint8(bound(numPayments, 2, 10));
        uint256 tokensPayment = tokensAllocated / STAKE_TO_FEES_RATIO / numPayments;

        resetPrank(users.gateway);
        _deposit(tokensAllocated);
        _authorizeSigner();

        resetPrank(users.indexer);
        uint256 accTokensPayment = 0;
        for (uint i = 0; i < numPayments; i++) {
            accTokensPayment = accTokensPayment + tokensPayment;
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(accTokensPayment), 0);
            _collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data);
        }
    }

    function testCollect_RevertWhen_NotAuthorized(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.QueryFee;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokens), 0);
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
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = _getQueryFeeEncodedData(newIndexer, uint128(tokens), 0);

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
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokens), 0);
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceIndexerMismatch.selector, users.indexer, newIndexer)
        );
        subgraphService.collect(newIndexer, paymentType, data);
    }

    function testCollect_QueryFees_RevertWhen_CollectionIdTooLarge() public useIndexer useAllocation(1000 ether) {
        bytes32 collectionId = keccak256(abi.encodePacked("Large collection id, longer than 160 bits"));
        IGraphTallyCollector.ReceiptAggregateVoucher memory rav = _getRav(users.indexer, collectionId, 1000 ether);
        bytes32 messageHash = graphTallyCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IGraphTallyCollector.SignedRAV memory signedRav = IGraphTallyCollector.SignedRAV(rav, signature);
        bytes memory data = abi.encode(signedRav);
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidCollectionId.selector, collectionId)
        );
        subgraphService.collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data);
    }

    function testCollect_QueryFees_PartialCollect(
        uint256 tokensAllocated,
        uint256 tokensPayment
    ) public useIndexer useAllocation(tokensAllocated) {
        vm.assume(tokensAllocated > MINIMUM_PROVISION_TOKENS * STAKE_TO_FEES_RATIO);
        uint256 maxTokensPayment = tokensAllocated / STAKE_TO_FEES_RATIO > type(uint128).max
            ? type(uint128).max
            : tokensAllocated / STAKE_TO_FEES_RATIO;
        tokensPayment = bound(tokensPayment, MINIMUM_PROVISION_TOKENS, maxTokensPayment);

        resetPrank(users.gateway);
        _deposit(tokensPayment);
        _authorizeSigner();

        uint256 beforeGatewayBalance = escrow
            .getEscrowAccount(users.gateway, address(graphTallyCollector), users.indexer)
            .balance;
        uint256 beforeTokensCollected = graphTallyCollector.tokensCollected(
            address(subgraphService),
            bytes32(uint256(uint160(allocationId))),
            users.indexer,
            users.gateway
        );

        // Collect the RAV in two steps
        resetPrank(users.indexer);
        uint256 tokensToCollect = tokensPayment / 2;
        bool oddTokensPayment = tokensPayment % 2 == 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = _getQueryFeeEncodedData(users.indexer, uint128(tokensPayment), tokensToCollect);
        _collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data);

        uint256 intermediateGatewayBalance = escrow
            .getEscrowAccount(users.gateway, address(graphTallyCollector), users.indexer)
            .balance;
        assertEq(intermediateGatewayBalance, beforeGatewayBalance - tokensToCollect);
        uint256 intermediateTokensCollected = graphTallyCollector.tokensCollected(
            address(subgraphService),
            bytes32(uint256(uint160(allocationId))),
            users.indexer,
            users.gateway
        );
        assertEq(intermediateTokensCollected, beforeTokensCollected + tokensToCollect);

        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 tokensPayment128 = uint128(tokensPayment);
        bytes memory data2 = _getQueryFeeEncodedData(
            users.indexer,
            tokensPayment128,
            oddTokensPayment ? tokensToCollect + 1 : tokensToCollect
        );
        _collect(users.indexer, IGraphPayments.PaymentTypes.QueryFee, data2);

        // Check the indexer received the correct amount of tokens
        uint256 afterGatewayBalance = escrow
            .getEscrowAccount(users.gateway, address(graphTallyCollector), users.indexer)
            .balance;
        assertEq(afterGatewayBalance, beforeGatewayBalance - tokensPayment);
        uint256 afterTokensCollected = graphTallyCollector.tokensCollected(
            address(subgraphService),
            bytes32(uint256(uint160(allocationId))),
            users.indexer,
            users.gateway
        );
        assertEq(afterTokensCollected, intermediateTokensCollected + tokensToCollect + (oddTokensPayment ? 1 : 0));
    }
}
