// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Directory } from "../../../contracts/utilities/Directory.sol";
import { SubgraphServiceTest } from "./SubgraphService.t.sol";

contract SubgraphServiceSlashTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Slash_RevertWhen_NotDisputeManager(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes memory data = abi.encode(uint256(1), uint256(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                Directory.DirectoryNotDisputeManager.selector,
                users.indexer,
                address(disputeManager)
            )
        );
        subgraphService.slash(users.indexer, data);
    }
}
