// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingSharedTest } from "./HorizonStakingShared.t.sol";

abstract contract SubgraphServiceSharedTest is HorizonStakingSharedTest {

    /*
     * VARIABLES
     */

    uint256 allocationIDPrivateKey;
    address allocationID;
    bytes32 subgraphDeployment;

    /*
     * MODIFIERS
     */

    modifier useIndexer {
        vm.startPrank(users.indexer);
        _;
        vm.stopPrank();
    }

    modifier useAllocation(uint256 tokens) {
        vm.assume(tokens > minimumProvisionTokens);
        vm.assume(tokens < 10_000_000_000 ether);
        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(users.indexer, subgraphDeployment, allocationIDPrivateKey, tokens);
        _startService(users.indexer, data);
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
     * HELPERS
     */

    function _register(address _indexer, bytes memory _data) internal {
        subgraphService.register(_indexer, _data);
    }

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

    function _startService(address indexer, bytes memory data) internal {
        subgraphService.startService(indexer, data);
    }

    function _stopService(address _indexer, bytes memory _data) internal {
        subgraphService.stopService(_indexer, _data);
    }

    function _delegate(uint256 tokens) internal {
        token.approve(address(staking), tokens);
        staking.delegate(users.indexer, address(subgraphService), tokens, 0);
    }
}
