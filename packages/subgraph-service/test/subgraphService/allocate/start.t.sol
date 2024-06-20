// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocateStartTest is SubgraphServiceTest {

    /*
     * Helpers
     */

    function _generateData(uint256 tokens) private view returns(bytes memory) {
        bytes32 digest = subgraphService.encodeAllocationProof(users.indexer, allocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocationIDPrivateKey, digest);
        return abi.encode(subgraphDeployment, tokens, allocationID, abi.encodePacked(r, s, v));
    }

    /*
     * TESTS
     */

    function testStart_Allocation(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(tokens);
        _registerIndexer(address(0));

        bytes memory data = _generateData(tokens);
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
        bytes memory data = _generateData(tokens);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            users.operator,
            users.indexer
        ));
        subgraphService.startService(users.indexer, data);
    }

    function testStart_RevertWhen_NoValidProvision(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        
        bytes memory data = _generateData(tokens);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerProvisionNotFound.selector,
            users.indexer
        ));
        subgraphService.startService(users.indexer, data);
    }

    function testStart_RevertWhen_NotRegistered(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(tokens);

        bytes memory data = _generateData(tokens);
        vm.expectRevert(abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            users.indexer
        ));
        subgraphService.startService(users.indexer, data);
    }

    function testStart_RevertWhen_ZeroAllocationId(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(tokens);
        _registerIndexer(address(0));

        bytes32 digest = subgraphService.encodeAllocationProof(users.indexer, address(0));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocationIDPrivateKey, digest);
        bytes memory data = abi.encode(subgraphDeployment, tokens, address(0), abi.encodePacked(r, s, v));
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerInvalidZeroAllocationId.selector
        ));
        subgraphService.startService(users.indexer, data);
    }

    function testStart_RevertWhen_InvalidSignature(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(tokens);
        _registerIndexer(address(0));

        (address signer, uint256 signerPrivateKey) = makeAddrAndKey("invalidSigner");
        bytes32 digest = subgraphService.encodeAllocationProof(users.indexer, allocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory data = abi.encode(subgraphDeployment, tokens, allocationID, abi.encodePacked(r, s, v));
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerInvalidAllocationProof.selector,
            signer,
            allocationID
        ));
        subgraphService.startService(users.indexer, data);
    }
}
