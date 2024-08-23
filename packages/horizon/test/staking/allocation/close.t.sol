// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingExtensionTest } from "./HorizonStakingExtension.t.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";

contract HorizonStakingCloseAllocationTest is HorizonStakingExtensionTest {
    using PPMMath for uint256;

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
        assertEq(staking.getStake(address(users.indexer)), tokens * 2 + ALLOCATIONS_REWARD_CUT);
    }

    function testCloseAllocation_WithBeneficiaryAddress(uint256 tokens) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        _storeAllocation(tokens);
        _storeMaxAllocationEpochs();
        _createProvision(subgraphDataServiceLegacyAddress, tokens, 0, 0);

        address beneficiary = makeAddr("beneficiary");
        _storeRewardsDestination(beneficiary);

        // Skip 15 epochs
        vm.roll(15);

        staking.closeAllocation(_allocationId, _poi);
        IHorizonStakingExtension.Allocation memory allocation = staking.getAllocation(_allocationId);
        assertEq(allocation.closedAtEpoch, epochManager.currentEpoch());

        // Stake should be updated with rewards
        assertEq(token.balanceOf(beneficiary), ALLOCATIONS_REWARD_CUT);
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
        assertEq(staking.getStake(address(users.indexer)), tokens * 2);
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

    function testCloseAllocation_WithDelegation(uint256 tokens, uint256 delegationTokens, uint32 indexingRewardCut) public useIndexer {
        tokens = bound(tokens, 2, MAX_STAKING_TOKENS);
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        vm.assume(indexingRewardCut <= MAX_PPM);

        uint256 legacyAllocationTokens = tokens / 2;
        uint256 provisionTokens = tokens - legacyAllocationTokens;

        _storeAllocation(legacyAllocationTokens);
        _storeMaxAllocationEpochs();
        _createProvision(subgraphDataServiceLegacyAddress, provisionTokens, 0, 0);
        _storeDelegationPool(delegationTokens, indexingRewardCut, 0);

        // Skip 15 epochs
        vm.roll(15);

        staking.closeAllocation(_allocationId, _poi);
        IHorizonStakingExtension.Allocation memory allocation = staking.getAllocation(_allocationId);
        assertEq(allocation.closedAtEpoch, epochManager.currentEpoch());

        uint256 indexerRewardCut = ALLOCATIONS_REWARD_CUT.mulPPM(indexingRewardCut);
        uint256 delegationFeeCut = ALLOCATIONS_REWARD_CUT - indexerRewardCut;
        assertEq(staking.getStake(address(users.indexer)), tokens + indexerRewardCut);
        assertEq(staking.getDelegationPool(users.indexer, subgraphDataServiceLegacyAddress).tokens, delegationTokens + delegationFeeCut);
    }
}