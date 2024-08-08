// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { SubgraphServiceSharedTest } from "../shared/SubgraphServiceShared.t.sol";

contract SubgraphServiceTest is SubgraphServiceSharedTest {

    /*
     * VARIABLES
     */

    /*
     * MODIFIERS
     */

    modifier useOperator {
        vm.startPrank(users.operator);
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
     * HELPERS
     */

    function _createAndStartAllocation(address indexer, uint256 tokens) internal {
        mint(indexer, tokens);

        resetPrank(indexer);
        token.approve(address(staking), tokens);
        staking.stakeTo(indexer, tokens);
        staking.provision(indexer, address(subgraphService), tokens, maxSlashingPercentage, disputePeriod);
        subgraphService.register(indexer, abi.encode("url", "geoHash", address(0)));

        (address newIndexerAllocationId, uint256 newIndexerAllocationKey) = makeAddrAndKey("newIndexerAllocationId");
        bytes32 digest = subgraphService.encodeAllocationProof(indexer, newIndexerAllocationId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newIndexerAllocationKey, digest);

        bytes memory data = abi.encode(subgraphDeployment, tokens, newIndexerAllocationId, abi.encodePacked(r, s, v));
        subgraphService.startService(indexer, data);
    }
}
