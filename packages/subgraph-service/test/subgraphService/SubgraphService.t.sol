// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { IGraphTallyCollector } from "@graphprotocol/horizon/contracts/interfaces/IGraphTallyCollector.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { LinkedList } from "@graphprotocol/horizon/contracts/libraries/LinkedList.sol";
import { IDataServiceFees } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataServiceFees.sol";
import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingTypes.sol";

import { Allocation } from "../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../contracts/interfaces/ISubgraphService.sol";
import { LegacyAllocation } from "../../contracts/libraries/LegacyAllocation.sol";
import { SubgraphServiceSharedTest } from "../shared/SubgraphServiceShared.t.sol";

contract SubgraphServiceTest is SubgraphServiceSharedTest {
    using PPMMath for uint256;
    using Allocation for Allocation.State;
    using LinkedList for LinkedList.List;

    /*
     * MODIFIERS
     */

    modifier useGovernor() {
        vm.startPrank(users.governor);
        _;
        vm.stopPrank();
    }

    modifier useOperator() {
        resetPrank(users.indexer);
        staking.setOperator(address(subgraphService), users.operator, true);
        resetPrank(users.operator);
        _;
        vm.stopPrank();
    }

    modifier useRewardsDestination() {
        _setRewardsDestination(users.rewardsDestination);
        _;
    }

    /*
     * SET UP
     */

    function setUp() public virtual override {
        super.setUp();
    }

    /*
     * ACTIONS
     */

    function _setRewardsDestination(address _rewardsDestination) internal {
        (, address indexer, ) = vm.readCallers();

        vm.expectEmit(address(subgraphService));
        emit AllocationManager.RewardsDestinationSet(indexer, _rewardsDestination);

        // Set rewards destination
        subgraphService.setRewardsDestination(_rewardsDestination);

        // Check rewards destination
        assertEq(subgraphService.rewardsDestination(indexer), _rewardsDestination);
    }

    function _acceptProvision(address _indexer, bytes memory _data) internal {
        IHorizonStakingTypes.Provision memory provision = staking.getProvision(_indexer, address(subgraphService));
        uint32 maxVerifierCut = provision.maxVerifierCut;
        uint64 thawingPeriod = provision.thawingPeriod;
        uint32 maxVerifierCutPending = provision.maxVerifierCutPending;
        uint64 thawingPeriodPending = provision.thawingPeriodPending;

        vm.expectEmit(address(subgraphService));
        emit IDataService.ProvisionPendingParametersAccepted(_indexer);

        // Accept provision
        subgraphService.acceptProvisionPendingParameters(_indexer, _data);

        // Update provision after acceptance
        provision = staking.getProvision(_indexer, address(subgraphService));

        // Check that max verifier cut updated to pending value if needed
        if (maxVerifierCut != maxVerifierCutPending) {
            assertEq(provision.maxVerifierCut, maxVerifierCutPending);
        }

        // Check that thawing period updated to pending value if needed
        if (thawingPeriod != thawingPeriodPending) {
            assertEq(provision.thawingPeriod, thawingPeriodPending);
        }
    }

    function _resizeAllocation(address _indexer, address _allocationId, uint256 _tokens) internal {
        // before state
        Allocation.State memory beforeAllocation = subgraphService.getAllocation(_allocationId);
        bytes32 subgraphDeploymentId = beforeAllocation.subgraphDeploymentId;
        uint256 beforeSubgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(subgraphDeploymentId);
        uint256 beforeAllocatedTokens = subgraphService.allocationProvisionTracker(_indexer);

        uint256 allocatedTokensDelta;
        if (_tokens > beforeAllocation.tokens) {
            allocatedTokensDelta = _tokens - beforeAllocation.tokens;
        } else {
            allocatedTokensDelta = beforeAllocation.tokens - _tokens;
        }

        vm.expectEmit(address(subgraphService));
        emit AllocationManager.AllocationResized(
            _indexer,
            _allocationId,
            subgraphDeploymentId,
            _tokens,
            beforeSubgraphAllocatedTokens
        );

        // resize allocation
        subgraphService.resizeAllocation(_indexer, _allocationId, _tokens);

        // after state
        uint256 afterSubgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(subgraphDeploymentId);
        uint256 afterAllocatedTokens = subgraphService.allocationProvisionTracker(_indexer);
        Allocation.State memory afterAllocation = subgraphService.getAllocation(_allocationId);
        uint256 accRewardsPerAllocatedTokenDelta = afterAllocation.accRewardsPerAllocatedToken -
            beforeAllocation.accRewardsPerAllocatedToken;
        uint256 afterAccRewardsPending = rewardsManager.calcRewards(
            beforeAllocation.tokens,
            accRewardsPerAllocatedTokenDelta
        );

        // check state
        if (_tokens > beforeAllocation.tokens) {
            assertEq(afterAllocatedTokens, beforeAllocatedTokens + allocatedTokensDelta);
        } else {
            assertEq(afterAllocatedTokens, beforeAllocatedTokens - allocatedTokensDelta);
        }
        assertEq(afterAllocation.tokens, _tokens);
        assertEq(afterAllocation.accRewardsPerAllocatedToken, rewardsPerSubgraphAllocationUpdate);
        assertEq(afterAllocation.accRewardsPending, afterAccRewardsPending);
        assertEq(afterSubgraphAllocatedTokens, _tokens);
    }

    function _closeStaleAllocation(address _allocationId) internal {
        Allocation.State memory allocation = subgraphService.getAllocation(_allocationId);
        assertTrue(allocation.isOpen());
        uint256 previousSubgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(
            allocation.subgraphDeploymentId
        );

        vm.expectEmit(address(subgraphService));
        emit AllocationManager.AllocationClosed(
            allocation.indexer,
            _allocationId,
            allocation.subgraphDeploymentId,
            allocation.tokens,
            true
        );

        // close stale allocation
        subgraphService.closeStaleAllocation(_allocationId);

        // update allocation
        allocation = subgraphService.getAllocation(_allocationId);

        // check allocation
        assertEq(allocation.closedAt, block.timestamp);

        // check subgraph deployment allocated tokens
        uint256 subgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(subgraphDeployment);
        assertEq(subgraphAllocatedTokens, previousSubgraphAllocatedTokens - allocation.tokens);
    }

    struct IndexingRewardsData {
        bytes32 poi;
        bytes poiMetadata;
        uint256 tokensIndexerRewards;
        uint256 tokensDelegationRewards;
    }

    struct QueryFeeData {
        uint256 curationCut;
        uint256 protocolPaymentCut;
    }

    struct CollectPaymentData {
        uint256 rewardsDestinationBalance;
        uint256 indexerProvisionBalance;
        uint256 delegationPoolBalance;
        uint256 indexerBalance;
        uint256 curationBalance;
        uint256 lockedTokens;
    }

    function _collect(address _indexer, IGraphPayments.PaymentTypes _paymentType, bytes memory _data) internal {
        // Reset storage variables
        uint256 paymentCollected = 0;
        address allocationId;
        IndexingRewardsData memory indexingRewardsData;
        CollectPaymentData memory collectPaymentDataBefore = _collectPaymentDataBefore(_indexer);

        if (_paymentType == IGraphPayments.PaymentTypes.QueryFee) {
            paymentCollected = _handleQueryFeeCollection(_indexer, _data);
        } else if (_paymentType == IGraphPayments.PaymentTypes.IndexingRewards) {
            (paymentCollected, allocationId, indexingRewardsData) = _handleIndexingRewardsCollection(_data);
        }

        vm.expectEmit(address(subgraphService));
        emit IDataService.ServicePaymentCollected(_indexer, _paymentType, paymentCollected);

        // collect rewards
        subgraphService.collect(_indexer, _paymentType, _data);

        CollectPaymentData memory collectPaymentDataAfter = _collectPaymentDataAfter(_indexer);

        if (_paymentType == IGraphPayments.PaymentTypes.QueryFee) {
            _verifyQueryFeeCollection(
                _indexer,
                paymentCollected,
                _data,
                collectPaymentDataBefore,
                collectPaymentDataAfter
            );
        } else if (_paymentType == IGraphPayments.PaymentTypes.IndexingRewards) {
            _verifyIndexingRewardsCollection(
                _indexer,
                allocationId,
                indexingRewardsData,
                collectPaymentDataBefore,
                collectPaymentDataAfter
            );
        }
    }

    function _collectPaymentDataBefore(address _indexer) private view returns (CollectPaymentData memory) {
        address rewardsDestination = subgraphService.rewardsDestination(_indexer);
        CollectPaymentData memory collectPaymentDataBefore;
        collectPaymentDataBefore.rewardsDestinationBalance = token.balanceOf(rewardsDestination);
        collectPaymentDataBefore.indexerProvisionBalance = staking.getProviderTokensAvailable(
            _indexer,
            address(subgraphService)
        );
        collectPaymentDataBefore.delegationPoolBalance = staking.getDelegatedTokensAvailable(
            _indexer,
            address(subgraphService)
        );
        collectPaymentDataBefore.indexerBalance = token.balanceOf(_indexer);
        collectPaymentDataBefore.curationBalance = token.balanceOf(address(curation));
        collectPaymentDataBefore.lockedTokens = subgraphService.feesProvisionTracker(_indexer);
        return collectPaymentDataBefore;
    }

    function _collectPaymentDataAfter(address _indexer) private view returns (CollectPaymentData memory) {
        CollectPaymentData memory collectPaymentDataAfter;
        address rewardsDestination = subgraphService.rewardsDestination(_indexer);
        collectPaymentDataAfter.rewardsDestinationBalance = token.balanceOf(rewardsDestination);
        collectPaymentDataAfter.indexerProvisionBalance = staking.getProviderTokensAvailable(
            _indexer,
            address(subgraphService)
        );
        collectPaymentDataAfter.delegationPoolBalance = staking.getDelegatedTokensAvailable(
            _indexer,
            address(subgraphService)
        );
        collectPaymentDataAfter.indexerBalance = token.balanceOf(_indexer);
        collectPaymentDataAfter.curationBalance = token.balanceOf(address(curation));
        collectPaymentDataAfter.lockedTokens = subgraphService.feesProvisionTracker(_indexer);
        return collectPaymentDataAfter;
    }

    function _handleQueryFeeCollection(
        address _indexer,
        bytes memory _data
    ) private returns (uint256 paymentCollected) {
        (IGraphTallyCollector.SignedRAV memory signedRav, uint256 tokensToCollect) = abi.decode(
            _data,
            (IGraphTallyCollector.SignedRAV, uint256)
        );
        address allocationId = address(uint160(uint256(signedRav.rav.collectionId)));
        Allocation.State memory allocation = subgraphService.getAllocation(allocationId);
        bytes32 subgraphDeploymentId = allocation.subgraphDeploymentId;

        address payer = graphTallyCollector.isAuthorized(signedRav.rav.payer, _recoverRAVSigner(signedRav))
            ? signedRav.rav.payer
            : address(0);

        uint256 tokensCollected = graphTallyCollector.tokensCollected(
            address(subgraphService),
            signedRav.rav.collectionId,
            _indexer,
            payer
        );
        paymentCollected = tokensToCollect == 0 ? signedRav.rav.valueAggregate - tokensCollected : tokensToCollect;

        QueryFeeData memory queryFeeData = _queryFeeData(allocation.subgraphDeploymentId);
        uint256 tokensProtocol = paymentCollected.mulPPMRoundUp(queryFeeData.protocolPaymentCut);
        uint256 tokensCurators = (paymentCollected - tokensProtocol).mulPPMRoundUp(queryFeeData.curationCut);

        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.QueryFeesCollected(
            _indexer,
            payer,
            allocationId,
            subgraphDeploymentId,
            paymentCollected,
            tokensCurators
        );

        return paymentCollected;
    }

    function _queryFeeData(bytes32 _subgraphDeploymentId) private view returns (QueryFeeData memory) {
        QueryFeeData memory queryFeeData;
        queryFeeData.protocolPaymentCut = graphPayments.PROTOCOL_PAYMENT_CUT();
        uint256 curationFeesCut = subgraphService.curationFeesCut();
        queryFeeData.curationCut = curation.isCurated(_subgraphDeploymentId) ? curationFeesCut : 0;
        return queryFeeData;
    }

    function _handleIndexingRewardsCollection(
        bytes memory _data
    ) private returns (uint256 paymentCollected, address allocationId, IndexingRewardsData memory indexingRewardsData) {
        (allocationId, indexingRewardsData.poi, indexingRewardsData.poiMetadata) = abi.decode(
            _data,
            (address, bytes32, bytes)
        );
        Allocation.State memory allocation = subgraphService.getAllocation(allocationId);

        // Calculate accumulated tokens, this depends on the rewards manager which we have mocked
        uint256 accRewardsPerTokens = allocation.tokens.mulPPM(rewardsManager.rewardsPerSignal());
        // Calculate the payment collected by the indexer for this transaction
        paymentCollected = accRewardsPerTokens - allocation.accRewardsPerAllocatedToken;

        uint256 currentEpoch = epochManager.currentEpoch();
        paymentCollected = currentEpoch > allocation.createdAtEpoch ? paymentCollected : 0;

        uint256 delegatorCut = staking.getDelegationFeeCut(
            allocation.indexer,
            address(subgraphService),
            IGraphPayments.PaymentTypes.IndexingRewards
        );
        IHorizonStakingTypes.DelegationPool memory delegationPool = staking.getDelegationPool(
            allocation.indexer,
            address(subgraphService)
        );
        indexingRewardsData.tokensDelegationRewards = delegationPool.shares > 0
            ? paymentCollected.mulPPM(delegatorCut)
            : 0;
        indexingRewardsData.tokensIndexerRewards = paymentCollected - indexingRewardsData.tokensDelegationRewards;

        vm.expectEmit(address(subgraphService));
        emit AllocationManager.IndexingRewardsCollected(
            allocation.indexer,
            allocationId,
            allocation.subgraphDeploymentId,
            paymentCollected,
            indexingRewardsData.tokensIndexerRewards,
            indexingRewardsData.tokensDelegationRewards,
            indexingRewardsData.poi,
            indexingRewardsData.poiMetadata,
            epochManager.currentEpoch()
        );

        return (paymentCollected, allocationId, indexingRewardsData);
    }

    function _verifyQueryFeeCollection(
        address _indexer,
        uint256 _paymentCollected,
        bytes memory _data,
        CollectPaymentData memory collectPaymentDataBefore,
        CollectPaymentData memory collectPaymentDataAfter
    ) private view {
        (IGraphTallyCollector.SignedRAV memory signedRav, uint256 tokensToCollect) = abi.decode(
            _data,
            (IGraphTallyCollector.SignedRAV, uint256)
        );
        Allocation.State memory allocation = subgraphService.getAllocation(
            address(uint160(uint256(signedRav.rav.collectionId)))
        );
        QueryFeeData memory queryFeeData = _queryFeeData(allocation.subgraphDeploymentId);
        uint256 tokensProtocol = _paymentCollected.mulPPMRoundUp(queryFeeData.protocolPaymentCut);
        uint256 curationTokens = (_paymentCollected - tokensProtocol).mulPPMRoundUp(queryFeeData.curationCut);
        uint256 expectedIndexerTokensPayment = _paymentCollected - tokensProtocol - curationTokens;

        assertEq(
            collectPaymentDataAfter.indexerBalance,
            collectPaymentDataBefore.indexerBalance + expectedIndexerTokensPayment
        );
        assertEq(collectPaymentDataAfter.curationBalance, collectPaymentDataBefore.curationBalance + curationTokens);

        // Check locked tokens
        uint256 tokensToLock = _paymentCollected * subgraphService.stakeToFeesRatio();
        assertEq(collectPaymentDataAfter.lockedTokens, collectPaymentDataBefore.lockedTokens + tokensToLock);

        // Check the stake claim
        LinkedList.List memory claimsList = _getClaimList(_indexer);
        bytes32 claimId = _buildStakeClaimId(_indexer, claimsList.nonce - 1);
        IDataServiceFees.StakeClaim memory stakeClaim = _getStakeClaim(claimId);
        uint64 disputePeriod = disputeManager.getDisputePeriod();
        assertEq(stakeClaim.tokens, tokensToLock);
        assertEq(stakeClaim.createdAt, block.timestamp);
        assertEq(stakeClaim.releasableAt, block.timestamp + disputePeriod);
        assertEq(stakeClaim.nextClaim, bytes32(0));
    }

    function _verifyIndexingRewardsCollection(
        address _indexer,
        address allocationId,
        IndexingRewardsData memory indexingRewardsData,
        CollectPaymentData memory collectPaymentDataBefore,
        CollectPaymentData memory collectPaymentDataAfter
    ) private {
        Allocation.State memory allocation = subgraphService.getAllocation(allocationId);

        // Check allocation state
        assertEq(allocation.accRewardsPending, 0);
        uint256 accRewardsPerAllocatedToken = rewardsManager.onSubgraphAllocationUpdate(
            allocation.subgraphDeploymentId
        );
        assertEq(allocation.accRewardsPerAllocatedToken, accRewardsPerAllocatedToken);
        assertEq(allocation.lastPOIPresentedAt, block.timestamp);

        // Check indexer got paid the correct amount
        address rewardsDestination = subgraphService.rewardsDestination(_indexer);
        if (rewardsDestination == address(0)) {
            // If rewards destination is address zero indexer should get paid to their provision balance
            assertEq(
                collectPaymentDataAfter.indexerProvisionBalance,
                collectPaymentDataBefore.indexerProvisionBalance + indexingRewardsData.tokensIndexerRewards
            );
        } else {
            // If rewards destination is set indexer should get paid to the rewards destination address
            assertEq(
                collectPaymentDataAfter.rewardsDestinationBalance,
                collectPaymentDataBefore.rewardsDestinationBalance + indexingRewardsData.tokensIndexerRewards
            );
        }

        // Check delegation pool got paid the correct amount
        assertEq(
            collectPaymentDataAfter.delegationPoolBalance,
            collectPaymentDataBefore.delegationPoolBalance + indexingRewardsData.tokensDelegationRewards
        );

        // If after collecting indexing rewards the indexer is over allocated the allcation should close
        uint256 tokensAvailable = staking.getTokensAvailable(
            _indexer,
            address(subgraphService),
            subgraphService.getDelegationRatio()
        );
        if (allocation.tokens <= tokensAvailable) {
            // Indexer isn't over allocated so allocation should still be open
            assertTrue(allocation.isOpen());
        } else {
            // Indexer is over allocated so allocation should be closed
            assertFalse(allocation.isOpen());
        }
    }

    function _migrateLegacyAllocation(address _indexer, address _allocationId, bytes32 _subgraphDeploymentID) internal {
        vm.expectEmit(address(subgraphService));
        emit AllocationManager.LegacyAllocationMigrated(_indexer, _allocationId, _subgraphDeploymentID);

        subgraphService.migrateLegacyAllocation(_indexer, _allocationId, _subgraphDeploymentID);

        LegacyAllocation.State memory afterLegacyAllocation = subgraphService.getLegacyAllocation(_allocationId);
        assertEq(afterLegacyAllocation.indexer, _indexer);
        assertEq(afterLegacyAllocation.subgraphDeploymentId, _subgraphDeploymentID);
    }

    /*
     * HELPERS
     */

    function _createAndStartAllocation(address _indexer, uint256 _tokens) internal {
        mint(_indexer, _tokens);

        resetPrank(_indexer);
        token.approve(address(staking), _tokens);
        staking.stakeTo(_indexer, _tokens);
        staking.provision(_indexer, address(subgraphService), _tokens, fishermanRewardPercentage, disputePeriod);
        _register(_indexer, abi.encode("url", "geoHash", address(0)));

        (address newIndexerAllocationId, uint256 newIndexerAllocationKey) = makeAddrAndKey("newIndexerAllocationId");
        bytes32 digest = subgraphService.encodeAllocationProof(_indexer, newIndexerAllocationId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newIndexerAllocationKey, digest);

        bytes memory data = abi.encode(subgraphDeployment, _tokens, newIndexerAllocationId, abi.encodePacked(r, s, v));
        _startService(_indexer, data);
    }

    /*
     * PRIVATE FUNCTIONS
     */

    function _recoverRAVSigner(IGraphTallyCollector.SignedRAV memory _signedRAV) private view returns (address) {
        bytes32 messageHash = graphTallyCollector.encodeRAV(_signedRAV.rav);
        return ECDSA.recover(messageHash, _signedRAV.signature);
    }

    function _getClaimList(address _indexer) private view returns (LinkedList.List memory) {
        (bytes32 head, bytes32 tail, uint256 nonce, uint256 count) = subgraphService.claimsLists(_indexer);
        return LinkedList.List(head, tail, nonce, count);
    }

    function _buildStakeClaimId(address _indexer, uint256 _nonce) private view returns (bytes32) {
        return keccak256(abi.encodePacked(address(subgraphService), _indexer, _nonce));
    }

    function _getStakeClaim(bytes32 _claimId) private view returns (IDataServiceFees.StakeClaim memory) {
        (uint256 tokens, uint256 createdAt, uint256 releasableAt, bytes32 nextClaim) = subgraphService.claims(_claimId);
        return IDataServiceFees.StakeClaim(tokens, createdAt, releasableAt, nextClaim);
    }

    // This doesn't matter for testing because the metadata is not decoded onchain but it's expected to be of the form:
    // - uint256 blockNumber - the block number (indexed chain) the poi’s where computed at
    // - bytes32 publicPOI - the public POI matching the presenting poi
    // - uint8 indexingStatus - status (failed, syncing, etc). Mapping maintained by indexer agent.
    // - uint8 errorCode - Again up to indexer agent, but seems sensible to use 0 if no error, and error codes for anything else.
    // - uint256 errorBlockNumber - Block number (indexed chain) where the indexing error happens. 0 if no error.
    function _getHardcodedPOIMetadata() internal view returns (bytes memory) {
        return abi.encode(block.number, bytes32("PUBLIC_POI1"), uint8(0), uint8(0), uint256(0));
    }
}
