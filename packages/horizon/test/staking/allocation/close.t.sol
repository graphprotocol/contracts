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
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        // Skip 15 epochs
        vm.roll(15);

        _closeAllocation(_allocationId, _poi);
    }

    function testCloseAllocation_WithBeneficiaryAddress(uint256 tokens) public useIndexer useAllocation(1 ether) {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        address beneficiary = makeAddr("beneficiary");
        _setStorage_RewardsDestination(users.indexer, beneficiary);

        // Skip 15 epochs
        vm.roll(15);

        _closeAllocation(_allocationId, _poi);
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
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        // Skip to over the max allocation epochs
        vm.roll((MAX_ALLOCATION_EPOCHS + 1)* EPOCH_LENGTH + 1);

        resetPrank(users.delegator);
        _closeAllocation(_allocationId, 0x0);
    }

    function testCloseAllocation_RevertWhen_ZeroTokensNotAuthorized() public useIndexer useAllocation(1 ether){
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, 100 ether, 0, 0);

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

        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, provisionTokens, 0, 0);
        _setStorage_DelegationPool(users.indexer, delegationTokens, indexingRewardCut, 0);

        // Skip 15 epochs
        vm.roll(15);

        _closeAllocation(_allocationId, _poi);
    }
}