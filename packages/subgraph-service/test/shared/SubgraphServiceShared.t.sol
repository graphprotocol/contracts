// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { SubgraphBaseTest } from "../SubgraphBaseTest.t.sol";

abstract contract SubgraphServiceSharedTest is SubgraphBaseTest {

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

    modifier useProvision(uint256 tokens) {
        vm.assume(tokens > minimumProvisionTokens);
        vm.assume(tokens < 10_000_000_000 ether);
        _createProvision(tokens);
        _registerIndexer(address(0));
        _startService(tokens);
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

    function _createProvision(uint256 tokens) internal {
        token.approve(address(staking), tokens);
        staking.stakeTo(users.indexer, tokens);
        staking.provision(users.indexer, address(subgraphService), tokens, maxSlashingPercentage, disputePeriod);
    }

    function _registerIndexer(address rewardsDestination) internal {
        subgraphService.register(users.indexer, abi.encode("url", "geoHash", rewardsDestination));
    }

    function _startService(uint256 tokens) internal {
        bytes32 digest = subgraphService.encodeAllocationProof(users.indexer, allocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocationIDPrivateKey, digest);

        bytes memory data = abi.encode(subgraphDeployment, tokens, allocationID, abi.encodePacked(r, s, v));
        subgraphService.startService(users.indexer, data);
    }
}
