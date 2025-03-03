// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { ExponentialRebates } from "../../../contracts/staking/libraries/ExponentialRebates.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";

contract HorizonStakingCollectAllocationTest is HorizonStakingTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function testCollectAllocation_RevertWhen_InvalidAllocationId(
        uint256 tokens
    ) public useIndexer useAllocation(1 ether) {
        vm.expectRevert("!alloc");
        staking.collect(tokens, address(0));
    }

    function testCollectAllocation_RevertWhen_Null(uint256 tokens) public {
        vm.expectRevert("!collect");
        staking.collect(tokens, _allocationId);
    }

    function testCollect_Tokenss(
        uint256 allocationTokens,
        uint256 collectTokens,
        uint256 curationTokens,
        uint32 curationPercentage,
        uint32 protocolTaxPercentage,
        uint256 delegationTokens,
        uint32 queryFeeCut
    ) public useIndexer useRebateParameters useAllocation(allocationTokens) {
        collectTokens = bound(collectTokens, 0, MAX_STAKING_TOKENS);
        curationTokens = bound(curationTokens, 0, MAX_STAKING_TOKENS);
        delegationTokens = bound(delegationTokens, 0, MAX_STAKING_TOKENS);
        vm.assume(curationPercentage <= MAX_PPM);
        vm.assume(protocolTaxPercentage <= MAX_PPM);
        vm.assume(queryFeeCut <= MAX_PPM);

        resetPrank(users.indexer);
        _setStorage_ProtocolTaxAndCuration(curationPercentage, protocolTaxPercentage);
        console.log("queryFeeCut", queryFeeCut);
        _setStorage_DelegationPool(users.indexer, delegationTokens, 0, queryFeeCut);
        curation.signal(_subgraphDeploymentID, curationTokens);

        resetPrank(users.gateway);
        approve(address(staking), collectTokens);
        _collect(collectTokens, _allocationId);
    }

    function testCollect_WithBeneficiaryAddress(
        uint256 allocationTokens,
        uint256 collectTokens
    ) public useIndexer useRebateParameters useAllocation(allocationTokens) {
        collectTokens = bound(collectTokens, 0, MAX_STAKING_TOKENS);

        address beneficiary = makeAddr("beneficiary");
        _setStorage_RewardsDestination(users.indexer, beneficiary);

        resetPrank(users.gateway);
        approve(address(staking), collectTokens);
        _collect(collectTokens, _allocationId);

        uint256 newRebates = ExponentialRebates.exponentialRebates(
            collectTokens,
            allocationTokens,
            alphaNumerator,
            alphaDenominator,
            lambdaNumerator,
            lambdaDenominator
        );
        uint256 payment = newRebates > collectTokens ? collectTokens : newRebates;

        assertEq(token.balanceOf(beneficiary), payment);
    }
}
