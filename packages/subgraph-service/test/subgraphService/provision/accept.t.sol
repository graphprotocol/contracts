// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceProvisionAcceptTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function testAccept_Provision(uint256 tokens) public useIndexer useAllocation(tokens) {
        vm.expectEmit(address(subgraphService));
        emit IDataService.ProvisionAccepted(users.indexer);
        subgraphService.acceptProvision(users.indexer, "");
    }

    function testAccept_RevertWhen_NotRegistered() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            users.indexer
        ));
        subgraphService.acceptProvision(users.indexer, "");
    }

    function testAccept_RevertWhen_NotAuthorized() public {
        resetPrank(users.operator);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            users.operator,
            users.indexer
        ));
        subgraphService.acceptProvision(users.indexer, "");
    }
}
