// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { ITAPCollector } from "@graphprotocol/horizon/contracts/interfaces/ITAPCollector.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { LinkedList } from "@graphprotocol/horizon/contracts/libraries/LinkedList.sol";
import { IDataServiceFees } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataServiceFees.sol";

import { Allocation } from "../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceSharedTest } from "../shared/SubgraphServiceShared.t.sol";

contract SubgraphServiceTest is SubgraphServiceSharedTest {
    using PPMMath for uint256;
    using Allocation for Allocation.State;
    using LinkedList for LinkedList.List;

    /*
     * VARIABLES
     */

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
        staking.setOperator(users.operator, address(subgraphService), true);
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
        emit IDataService.ProvisionAccepted(_indexer);

        // Accept provision
        subgraphService.acceptProvision(_indexer, _data);

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
        assertTrue(subgraphService.isActiveAllocation(_allocationId));

        Allocation.State memory allocation = subgraphService.getAllocation(_allocationId);
        uint256 previousSubgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(
            allocation.subgraphDeploymentId
        );

        vm.expectEmit(address(subgraphService));
        emit AllocationManager.AllocationClosed(
            allocation.indexer,
            _allocationId,
            allocation.subgraphDeploymentId,
            allocation.tokens
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
        address allocationId;
        uint256 paymentCollected = 0;
        Allocation.State memory allocation;
        CollectPaymentData memory collectPaymentDataBefore;

        // PaymentType.IndexingRewards variables
        IndexingRewardsData memory indexingRewardsData;
        address rewardsDestination = subgraphService.rewardsDestination(_indexer);
        collectPaymentDataBefore.rewardsDestinationBalance = token.balanceOf(rewardsDestination);
        collectPaymentDataBefore.indexerProvisionBalance = staking.getProviderTokensAvailable(
            _indexer,
            address(subgraphService)
        );
        collectPaymentDataBefore.delegationPoolBalance = staking.getDelegatedTokensAvailable(
            _indexer,
            address(subgraphService)
        );

        // PaymentType.QueryFee variables
        QueryFeeData memory queryFeeData;
        queryFeeData.protocolPaymentCut = graphPayments.PROTOCOL_PAYMENT_CUT();
        collectPaymentDataBefore.indexerBalance = token.balanceOf(_indexer);
        collectPaymentDataBefore.curationBalance = token.balanceOf(address(curation));
        collectPaymentDataBefore.lockedTokens = subgraphService.feesProvisionTracker(_indexer);

        if (_paymentType == IGraphPayments.PaymentTypes.QueryFee) {
            // Recover RAV data
            ITAPCollector.SignedRAV memory signedRav = abi.decode(_data, (ITAPCollector.SignedRAV));
            allocationId = abi.decode(signedRav.rav.metadata, (address));
            allocation = subgraphService.getAllocation(allocationId);
            address payer = _recoverRAVSigner(signedRav);

            // Total amount of tokens collected for indexer
            uint256 tokensCollected = tapCollector.tokensCollected(address(subgraphService), _indexer, payer);
            // Find out how much of the payment was collected via this RAV
            paymentCollected = signedRav.rav.valueAggregate - tokensCollected;

            // Calculate curation cut
            uint256 curationFeesCut = subgraphService.curationFeesCut();
            queryFeeData.curationCut = curation.isCurated(allocation.subgraphDeploymentId) ? curationFeesCut : 0;
            uint256 tokensCurators = paymentCollected.mulPPM(queryFeeData.curationCut);

            vm.expectEmit(address(subgraphService));
            emit ISubgraphService.QueryFeesCollected(_indexer, paymentCollected, tokensCurators);
        } else if (_paymentType == IGraphPayments.PaymentTypes.IndexingRewards) {
            // Recover IndexingRewards data
            (allocationId, indexingRewardsData.poi) = abi.decode(_data, (address, bytes32));
            allocation = subgraphService.getAllocation(allocationId);

            // Calculate accumulated tokens, this depends on the rewards manager which we have mocked
            uint256 accRewardsPerTokens = allocation.tokens.mulPPM(rewardsManager.rewardsPerSignal());
            // Calculate the payment collected by the indexer for this transaction
            paymentCollected = accRewardsPerTokens - allocation.accRewardsPerAllocatedToken;

            uint256 delegatorCut = staking.getDelegationFeeCut(
                allocation.indexer,
                address(subgraphService),
                // TODO: this should be fixed in AllocationManager, it should be IndexingRewards instead
                IGraphPayments.PaymentTypes.IndexingFee
            );
            indexingRewardsData.tokensDelegationRewards = paymentCollected.mulPPM(delegatorCut);
            indexingRewardsData.tokensIndexerRewards = paymentCollected - indexingRewardsData.tokensDelegationRewards;

            vm.expectEmit(address(subgraphService));
            emit AllocationManager.IndexingRewardsCollected(
                allocation.indexer,
                allocationId,
                allocation.subgraphDeploymentId,
                paymentCollected,
                indexingRewardsData.tokensIndexerRewards,
                indexingRewardsData.tokensDelegationRewards,
                indexingRewardsData.poi
            );
        }

        vm.expectEmit(address(subgraphService));
        emit IDataService.ServicePaymentCollected(_indexer, _paymentType, paymentCollected);

        // collect rewards
        subgraphService.collect(_indexer, _paymentType, _data);

        // Collect payment data after
        CollectPaymentData memory collectPaymentDataAfter;
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

        if (_paymentType == IGraphPayments.PaymentTypes.QueryFee) {
            // Check indexer got paid the correct amount
            {
                uint256 tokensProtocol = paymentCollected.mulPPM(protocolPaymentCut);
                uint256 curationTokens = paymentCollected.mulPPM(queryFeeData.curationCut);
                uint256 expectedIndexerTokensPayment = paymentCollected - tokensProtocol - curationTokens;
                assertEq(
                    collectPaymentDataAfter.indexerBalance,
                    collectPaymentDataBefore.indexerBalance + expectedIndexerTokensPayment
                );

                // Check curation got paid the correct amount
                assertEq(
                    collectPaymentDataAfter.curationBalance,
                    collectPaymentDataBefore.curationBalance + curationTokens
                );
            }

            // Check locked tokens
            uint256 tokensToLock = paymentCollected * subgraphService.stakeToFeesRatio();
            assertEq(collectPaymentDataAfter.lockedTokens, collectPaymentDataBefore.lockedTokens + tokensToLock);

            // Check the stake claim
            LinkedList.List memory claimsList = _getClaimList(_indexer);
            bytes32 claimId = _buildStakeClaimId(_indexer, claimsList.nonce - 1);
            IDataServiceFees.StakeClaim memory stakeClaim = _getStakeClaim(claimId);
            uint64 disputePeriod = disputeManager.getDisputePeriod();
            assertEq(stakeClaim.tokens, tokensToLock);
            assertEq(stakeClaim.createdAt, block.timestamp);
            assertEq(stakeClaim.releaseAt, block.timestamp + disputePeriod);
            assertEq(stakeClaim.nextClaim, bytes32(0));
        } else {
            // Update allocation after collecting rewards
            allocation = subgraphService.getAllocation(allocationId);

            // Check allocation state
            assertEq(allocation.accRewardsPending, 0);
            uint256 accRewardsPerAllocatedToken = rewardsManager.onSubgraphAllocationUpdate(
                allocation.subgraphDeploymentId
            );
            assertEq(allocation.accRewardsPerAllocatedToken, accRewardsPerAllocatedToken);
            assertEq(allocation.lastPOIPresentedAt, block.timestamp);

            // Check indexer got paid the correct amount
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
                subgraphService.delegationRatio()
            );
            if (allocation.tokens <= tokensAvailable) {
                // Indexer isn't over allocated so allocation should still be open
                assertTrue(allocation.isOpen());
            } else {
                // Indexer is over allocated so allocation should be closed
                assertFalse(allocation.isOpen());
            }
        }
    }

    /*
     * HELPERS
     */

    function _createAndStartAllocation(address _indexer, uint256 _tokens) internal {
        mint(_indexer, _tokens);

        resetPrank(_indexer);
        token.approve(address(staking), _tokens);
        staking.stakeTo(_indexer, _tokens);
        staking.provision(_indexer, address(subgraphService), _tokens, maxSlashingPercentage, disputePeriod);
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

    function _recoverRAVSigner(ITAPCollector.SignedRAV memory _signedRAV) private view returns (address) {
        bytes32 messageHash = tapCollector.encodeRAV(_signedRAV.rav);
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
        (uint256 tokens, uint256 createdAt, uint256 releaseAt, bytes32 nextClaim) = subgraphService.claims(_claimId);
        return IDataServiceFees.StakeClaim(tokens, createdAt, releaseAt, nextClaim);
    }
}
