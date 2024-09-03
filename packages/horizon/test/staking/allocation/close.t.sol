// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";

contract HorizonStakingCloseAllocationTest is HorizonStakingTest {
    using PPMMath for uint256;

    bytes32 internal constant _poi = keccak256("poi");

    /*
     * TESTS
     */

    function testCloseAllocation(uint256 tokens) public useIndexer useAllocation(1 ether) {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        _setStorage_MaxAllocationEpochs();
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        // Skip 15 epochs
        vm.roll(15);

        staking.closeAllocation(_allocationId, _poi);
        IHorizonStakingExtension.Allocation memory allocation = staking.getAllocation(_allocationId);
        assertEq(allocation.closedAtEpoch, epochManager.currentEpoch());

        // Stake should be updated with rewards
        assertEq(staking.getStake(address(users.indexer)), tokens * 2 + ALLOCATIONS_REWARD_CUT);
    }

    function testCloseAllocation_WithBeneficiaryAddress(uint256 tokens) public useIndexer useAllocation(1 ether) {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);

        _setStorage_MaxAllocationEpochs();
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        address beneficiary = makeAddr("beneficiary");
        _setStorage_RewardsDestination(users.indexer, beneficiary);

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

    function testCloseAllocation_RevertWhen_NotIndexer() public useIndexer useAllocation(1 ether) {
        resetPrank(users.delegator);
        vm.expectRevert("!auth");
        staking.closeAllocation(_allocationId, _poi);
    }

    function testCloseAllocation_AfterMaxEpochs_AnyoneCanClose(uint256 tokens) public useIndexer useAllocation(1 ether) {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        _setStorage_MaxAllocationEpochs();
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        // Skip to over the max allocation epochs
        vm.roll(MAX_ALLOCATION_EPOCHS + 2);

        resetPrank(users.delegator);
        staking.closeAllocation(_allocationId, 0x0);
        IHorizonStakingExtension.Allocation memory allocation = staking.getAllocation(_allocationId);
        assertEq(allocation.closedAtEpoch, epochManager.currentEpoch());

        // No rewards distributed
        assertEq(staking.getStake(address(users.indexer)), tokens * 2);
    }

    function testCloseAllocation_RevertWhen_ZeroTokensNotAuthorized() public useIndexer useAllocation(1 ether){
        _setStorage_MaxAllocationEpochs();

        // Skip to over the max allocation epochs
        vm.roll(MAX_ALLOCATION_EPOCHS + 2);

        resetPrank(users.delegator);
        vm.expectRevert("!auth");
        staking.closeAllocation(_allocationId, 0x0);
    }

    function testCloseAllocation_WithDelegation(uint256 tokens, uint256 delegationTokens, uint32 indexingRewardCut) public useIndexer useAllocation(1 ether) {
        tokens = bound(tokens, 2, MAX_STAKING_TOKENS);
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        vm.assume(indexingRewardCut <= MAX_PPM);

        uint256 legacyAllocationTokens = tokens / 2;
        uint256 provisionTokens = tokens - legacyAllocationTokens;

        _setStorage_MaxAllocationEpochs();
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, provisionTokens, 0, 0);
        _setStorage_DelegationPool(users.indexer, delegationTokens, indexingRewardCut, 0);

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