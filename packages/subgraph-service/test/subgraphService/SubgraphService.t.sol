// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { Allocation } from "../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../contracts/utilities/AllocationManager.sol";
import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingTypes.sol";

import { SubgraphServiceSharedTest } from "../shared/SubgraphServiceShared.t.sol";

contract SubgraphServiceTest is SubgraphServiceSharedTest {
    using PPMMath for uint256;

    /*
     * VARIABLES
     */

    /*
     * MODIFIERS
     */

    modifier useOperator {
        resetPrank(users.indexer);
        staking.setOperator(users.operator, address(subgraphService), true);
        resetPrank(users.operator);
        _;
        vm.stopPrank();
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
        emit AllocationManager.AllocationResized(_indexer, _allocationId, subgraphDeploymentId, _tokens, beforeSubgraphAllocatedTokens);

        // resize allocation
        subgraphService.resizeAllocation(_indexer, _allocationId, _tokens);

        // after state
        uint256 afterSubgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(subgraphDeploymentId);
        uint256 afterAllocatedTokens = subgraphService.allocationProvisionTracker(_indexer);
        Allocation.State memory afterAllocation = subgraphService.getAllocation(_allocationId);
        uint256 accRewardsPerAllocatedTokenDelta = afterAllocation.accRewardsPerAllocatedToken - beforeAllocation.accRewardsPerAllocatedToken;
        uint256 afterAccRewardsPending = rewardsManager.calcRewards(beforeAllocation.tokens, accRewardsPerAllocatedTokenDelta);

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
        uint256 previousSubgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(allocation.subgraphDeploymentId);
        
        vm.expectEmit(address(subgraphService));
        emit AllocationManager.AllocationClosed(allocation.indexer, _allocationId, allocation.subgraphDeploymentId, allocation.tokens);

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

    function _collectIndexingRewards(address _indexer, address _allocationID, uint256 _tokens) internal {
        resetPrank(_indexer);
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(_allocationID, bytes32("POI1"));

        uint256 indexerPreviousProvisionBalance = staking.getProviderTokensAvailable(_indexer, address(subgraphService));
        subgraphService.collect(_indexer, paymentType, data);

        uint256 indexerProvisionBalance = staking.getProviderTokensAvailable(_indexer, address(subgraphService));
        assertEq(indexerProvisionBalance, indexerPreviousProvisionBalance + _tokens.mulPPM(rewardsPerSignal));
    }
}
