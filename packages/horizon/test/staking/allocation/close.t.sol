// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingExtensionTest } from "./HorizonStakingExtension.t.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";

contract HorizonStakingCloseAllocationTest is HorizonStakingExtensionTest {

    /*
     * TESTS
     */

    function testCloseAllocation(uint256 tokens) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        _storeAllocation(tokens);
        _storeMaxAllocationEpochs();
        _createProvision(subgraphDataServiceLegacyAddress, tokens, 0, 0);

        // Skip 15 epochs
        vm.roll(15);

        staking.closeAllocation(_allocationId, _poi);
        IHorizonStakingExtension.Allocation memory allocation = staking.getAllocation(_allocationId);
        assertEq(allocation.closedAtEpoch, epochManager.currentEpoch());

        // Stake should be updated with rewards
        assertEq(staking.getStake(address(users.indexer)), tokens + ALLOCATIONS_REWARD_CUT);
    }

    function testCloseAllocation_RevertWhen_NotActive() public {
        vm.expectRevert("!active");
        staking.closeAllocation(_allocationId, _poi);
    }

    function testCloseAllocation_RevertWhen_NotIndexer() public useAllocation {
        resetPrank(users.delegator);
        vm.expectRevert("!auth");
        staking.closeAllocation(_allocationId, _poi);
    }

    function testCloseAllocation_AfterMaxEpochs_AnyoneCanClose(uint256 tokens) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        _storeAllocation(tokens);
        _storeMaxAllocationEpochs();
        _createProvision(subgraphDataServiceLegacyAddress, tokens, 0, 0);

        // Skip to over the max allocation epochs
        vm.roll(MAX_ALLOCATION_EPOCHS + 2);

        resetPrank(users.delegator);
        staking.closeAllocation(_allocationId, 0x0);
        IHorizonStakingExtension.Allocation memory allocation = staking.getAllocation(_allocationId);
        assertEq(allocation.closedAtEpoch, epochManager.currentEpoch());

        // No rewards distributed
        assertEq(staking.getStake(address(users.indexer)), tokens);
    }

    function testCloseAllocation_RevertWhen_ZeroTokensNotAuthorized() public useIndexer {
        _storeAllocation(0);
        _storeMaxAllocationEpochs();

        // Skip to over the max allocation epochs
        vm.roll(MAX_ALLOCATION_EPOCHS + 2);

        resetPrank(users.delegator);
        vm.expectRevert("!auth");
        staking.closeAllocation(_allocationId, 0x0);
    }
}