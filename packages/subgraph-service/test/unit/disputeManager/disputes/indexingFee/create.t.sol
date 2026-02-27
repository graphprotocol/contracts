// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsCollector } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "../../../subgraphService/indexing-agreement/shared.t.sol";

contract DisputeManagerIndexingFeeCreateDisputeTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * HELPERS
     */

    /// @dev Sets up an indexer with an accepted indexing agreement that has been collected on.
    /// Returns the agreement ID and indexer state needed to create a dispute.
    function _setupCollectedAgreement(
        Seed memory seed,
        uint256 unboundedTokensCollected
    ) internal returns (bytes16 agreementId, IndexerState memory indexerState) {
        Context storage ctx = _newCtx(seed);
        indexerState = _withIndexer(ctx);
        (, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);
        agreementId = acceptedAgreementId;

        // Set payments destination
        resetPrank(indexerState.addr);
        subgraphService.setPaymentsDestination(indexerState.addr);

        // Mock the collect call to succeed with some tokens
        uint256 tokensCollected = bound(unboundedTokensCollected, 1, indexerState.tokens / STAKE_TO_FEES_RATIO);
        bytes memory data = abi.encode(
            IRecurringCollector.CollectParams({
                agreementId: acceptedAgreementId,
                collectionId: bytes32(uint256(uint160(indexerState.allocationId))),
                tokens: 0,
                dataServiceCut: 0,
                receiverDestination: indexerState.addr,
                maxSlippage: type(uint256).max
            })
        );
        vm.mockCall(
            address(recurringCollector),
            abi.encodeWithSelector(IPaymentsCollector.collect.selector, IGraphPayments.PaymentTypes.IndexingFee, data),
            abi.encode(tokensCollected)
        );

        skip(1); // Make agreement collectable

        // Collect to set lastCollectionAt > 0
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(
                acceptedAgreementId,
                100, // entities
                bytes32("POI1"),
                epochManager.currentEpochBlock(),
                bytes("")
            )
        );

        // The collect mock prevented the real RecurringCollector from updating lastCollectionAt.
        // Mock getAgreement to return lastCollectionAt > 0 so the dispute can be created.
        IRecurringCollector.AgreementData memory agreementData = recurringCollector.getAgreement(acceptedAgreementId);
        agreementData.lastCollectionAt = uint64(block.timestamp);
        vm.mockCall(
            address(recurringCollector),
            abi.encodeWithSelector(recurringCollector.getAgreement.selector, acceptedAgreementId),
            abi.encode(agreementData)
        );
    }

    /*
     * TESTS
     */

    function test_IndexingFee_Create_Dispute(Seed memory seed, uint256 unboundedTokensCollected) public {
        (bytes16 agreementId, IndexerState memory indexerState) = _setupCollectedAgreement(
            seed,
            unboundedTokensCollected
        );

        // Create dispute as fisherman
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), disputeManager.disputeDeposit());

        bytes32 disputeId = disputeManager.createIndexingFeeDisputeV1(
            agreementId,
            bytes32("disputePOI"),
            200,
            block.number
        );

        assertTrue(disputeManager.isDisputeCreated(disputeId));

        // Verify dispute fields
        (
            address indexer,
            address fisherman,
            uint256 deposit,
            ,
            IDisputeManager.DisputeType disputeType,
            IDisputeManager.DisputeStatus status,
            ,
            ,
            uint256 stakeSnapshot
        ) = disputeManager.disputes(disputeId);

        assertEq(indexer, indexerState.addr);
        assertEq(fisherman, users.fisherman);
        assertEq(deposit, disputeManager.disputeDeposit());
        assertEq(uint8(disputeType), uint8(IDisputeManager.DisputeType.IndexingFeeDispute));
        assertEq(uint8(status), uint8(IDisputeManager.DisputeStatus.Pending));
        assertTrue(stakeSnapshot > 0);
    }

    function test_IndexingFee_Create_Dispute_RevertWhen_NotCollected(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Attempt to create dispute without collecting first (lastCollectionAt == 0)
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), disputeManager.disputeDeposit());

        vm.expectRevert(
            abi.encodeWithSelector(
                IDisputeManager.DisputeManagerIndexingAgreementNotDisputable.selector,
                acceptedAgreementId
            )
        );
        disputeManager.createIndexingFeeDisputeV1(acceptedAgreementId, bytes32("POI"), 100, block.number);
    }

    function test_IndexingFee_Create_Dispute_RevertWhen_AlreadyCreated(
        Seed memory seed,
        uint256 unboundedTokensCollected
    ) public {
        (bytes16 agreementId, ) = _setupCollectedAgreement(seed, unboundedTokensCollected);

        // Create first dispute
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), disputeManager.disputeDeposit() * 2);

        bytes32 disputeId = disputeManager.createIndexingFeeDisputeV1(agreementId, bytes32("POI"), 100, block.number);

        // Attempt to create a duplicate dispute
        vm.expectRevert(
            abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputeAlreadyCreated.selector, disputeId)
        );
        disputeManager.createIndexingFeeDisputeV1(agreementId, bytes32("POI"), 100, block.number);
    }
}
