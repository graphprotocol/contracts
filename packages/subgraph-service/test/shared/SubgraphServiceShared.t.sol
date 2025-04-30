// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { Allocation } from "../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../contracts/utilities/AllocationManager.sol";
import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ISubgraphService } from "../../contracts/interfaces/ISubgraphService.sol";
import { MathUtils } from "@graphprotocol/horizon/contracts/libraries/MathUtils.sol";

import { HorizonStakingSharedTest } from "./HorizonStakingShared.t.sol";

abstract contract SubgraphServiceSharedTest is HorizonStakingSharedTest {
    using Allocation for Allocation.State;

    /*
     * VARIABLES
     */

    uint256 allocationIDPrivateKey;
    address allocationID;
    bytes32 subgraphDeployment;

    /*
     * MODIFIERS
     */

    modifier useIndexer() {
        vm.startPrank(users.indexer);
        _;
        vm.stopPrank();
    }

    modifier useAllocation(uint256 tokens) {
        vm.assume(tokens >= minimumProvisionTokens);
        vm.assume(tokens < 10_000_000_000 ether);
        _createProvision(users.indexer, tokens, fishermanRewardPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            users.indexer,
            subgraphDeployment,
            allocationIDPrivateKey,
            tokens
        );
        _startService(users.indexer, data);
        _;
    }

    modifier useDelegation(uint256 tokens) {
        vm.assume(tokens > MIN_DELEGATION);
        vm.assume(tokens < 10_000_000_000 ether);
        (, address msgSender, ) = vm.readCallers();
        resetPrank(users.delegator);
        token.approve(address(staking), tokens);
        _delegate(users.indexer, address(subgraphService), tokens, 0);
        resetPrank(msgSender);
        _;
    }

    /*
     * SET UP
     */

    function setUp() public virtual override {
        super.setUp();
        (allocationID, allocationIDPrivateKey) = makeAddrAndKey("allocationId");
        subgraphDeployment = keccak256(abi.encodePacked("Subgraph Deployment ID"));
    }

    /*
     * ACTIONS
     */

    function _register(address _indexer, bytes memory _data) internal {
        (string memory url, string memory geohash, address rewardsDestination) = abi.decode(
            _data,
            (string, string, address)
        );

        vm.expectEmit(address(subgraphService));
        emit IDataService.ServiceProviderRegistered(_indexer, _data);

        // Register indexer
        subgraphService.register(_indexer, _data);

        // Check registered indexer data
        ISubgraphService.Indexer memory indexer = _getIndexer(_indexer);
        assertEq(indexer.registeredAt, block.timestamp);
        assertEq(indexer.url, url);
        assertEq(indexer.geoHash, geohash);

        // Check rewards destination
        assertEq(subgraphService.rewardsDestination(_indexer), rewardsDestination);
    }

    function _startService(address _indexer, bytes memory _data) internal {
        (bytes32 subgraphDeploymentId, uint256 tokens, address allocationId, ) = abi.decode(
            _data,
            (bytes32, uint256, address, bytes)
        );
        uint256 previousSubgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(subgraphDeploymentId);
        uint256 currentEpoch = epochManager.currentEpoch();

        vm.expectEmit(address(subgraphService));
        emit IDataService.ServiceStarted(_indexer, _data);
        emit AllocationManager.AllocationCreated(_indexer, allocationId, subgraphDeploymentId, tokens, currentEpoch);

        // TODO: improve this
        uint256 accRewardsPerAllocatedToken = 0;
        if (rewardsManager.subgraphs(subgraphDeploymentId)) {
            accRewardsPerAllocatedToken = rewardsManager.rewardsPerSubgraphAllocationUpdate();
        }

        // Start service
        subgraphService.startService(_indexer, _data);

        // Check allocation data
        Allocation.State memory allocation = subgraphService.getAllocation(allocationId);
        assertEq(allocation.tokens, tokens);
        assertEq(allocation.indexer, _indexer);
        assertEq(allocation.subgraphDeploymentId, subgraphDeploymentId);
        assertEq(allocation.createdAt, block.timestamp);
        assertEq(allocation.closedAt, 0);
        assertEq(allocation.lastPOIPresentedAt, 0);
        assertEq(allocation.accRewardsPerAllocatedToken, accRewardsPerAllocatedToken);
        assertEq(allocation.accRewardsPending, 0);
        assertEq(allocation.createdAtEpoch, currentEpoch);

        // Check subgraph deployment allocated tokens
        uint256 subgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(subgraphDeploymentId);
        assertEq(subgraphAllocatedTokens, previousSubgraphAllocatedTokens + tokens);
    }

    function _stopService(address _indexer, bytes memory _data) internal {
        address allocationId = abi.decode(_data, (address));

        Allocation.State memory allocation = subgraphService.getAllocation(allocationId);
        assertTrue(allocation.isOpen());
        uint256 previousSubgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(
            allocation.subgraphDeploymentId
        );

        vm.expectEmit(address(subgraphService));
        emit AllocationManager.AllocationClosed(
            _indexer,
            allocationId,
            allocation.subgraphDeploymentId,
            allocation.tokens,
            false
        );
        emit IDataService.ServiceStopped(_indexer, _data);

        // stop allocation
        subgraphService.stopService(_indexer, _data);

        // update allocation
        allocation = subgraphService.getAllocation(allocationId);

        // check allocation
        assertEq(allocation.closedAt, block.timestamp);

        // check subgraph deployment allocated tokens
        uint256 subgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(subgraphDeployment);
        assertEq(subgraphAllocatedTokens, previousSubgraphAllocatedTokens - allocation.tokens);
    }

    /*
     * HELPERS
     */

    function _createSubgraphAllocationData(
        address _indexer,
        bytes32 _subgraphDeployment,
        uint256 _allocationIdPrivateKey,
        uint256 _tokens
    ) internal view returns (bytes memory) {
        address allocationId = vm.addr(_allocationIdPrivateKey);
        bytes32 digest = subgraphService.encodeAllocationProof(_indexer, allocationId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_allocationIdPrivateKey, digest);

        return abi.encode(_subgraphDeployment, _tokens, allocationId, abi.encodePacked(r, s, v));
    }

    function _delegate(uint256 tokens) internal {
        token.approve(address(staking), tokens);
        staking.delegate(users.indexer, address(subgraphService), tokens, 0);
    }

    function _calculateStakeSnapshot(uint256 _tokens, uint256 _tokensDelegated) internal view returns (uint256) {
        bool delegationSlashingEnabled = staking.isDelegationSlashingEnabled();
        if (delegationSlashingEnabled) {
            return _tokens + _tokensDelegated;
        } else {
            return _tokens;
        }
    }

    /*
     * PRIVATE FUNCTIONS
     */

    function _getIndexer(address _indexer) private view returns (ISubgraphService.Indexer memory) {
        (uint256 registeredAt, string memory url, string memory geoHash) = subgraphService.indexers(_indexer);
        return ISubgraphService.Indexer({ registeredAt: registeredAt, url: url, geoHash: geoHash });
    }
}
