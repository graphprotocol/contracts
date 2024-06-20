// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocateStartTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function testStart_Allocation(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(tokens);
        _registerIndexer(address(0));

        bytes32 digest = subgraphService.encodeAllocationProof(users.indexer, allocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocationIDPrivateKey, digest);

        bytes memory data = abi.encode(subgraphDeployment, tokens, allocationID, abi.encodePacked(r, s, v));
        vm.expectEmit(address(subgraphService));
        emit IDataService.ServiceStarted(users.indexer, data);
        subgraphService.startService(users.indexer, data);

        Allocation.State memory allocation = subgraphService.getAllocation(allocationID);
        assertEq(allocation.tokens, tokens);
        assertEq(allocation.indexer, users.indexer);
        assertEq(allocation.subgraphDeploymentId, subgraphDeployment);
        assertEq(allocation.createdAt, block.timestamp);
        assertEq(allocation.closedAt, 0);
        assertEq(allocation.lastPOIPresentedAt, 0);
        assertEq(allocation.accRewardsPerAllocatedToken, 0);
        assertEq(allocation.accRewardsPending, 0);
    }

    function testStart_RevertWhen_NotAuthorized(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(tokens);
        _registerIndexer(address(0));

        resetPrank(users.operator);
        bytes32 digest = subgraphService.encodeAllocationProof(users.indexer, allocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocationIDPrivateKey, digest);

        bytes memory data = abi.encode(subgraphDeployment, tokens, allocationID, abi.encodePacked(r, s, v));
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            users.operator,
            users.indexer
        ));
        subgraphService.startService(users.indexer, data);
    }
}
