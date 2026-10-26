// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";

import { RewardsManagerSharedTest } from "./shared.t.sol";

contract RewardsManagerSubgraphServiceTest is RewardsManagerSharedTest {
    event SubgraphServiceSet(address indexed oldSubgraphService, address indexed newSubgraphService);
    event HorizonRewardsAssigned(address indexed indexer, address indexed allocationID, uint256 amount);
    event RewardsDenied(address indexed indexer, address indexed allocationID);
    event RewardsDeniedDueToEligibility(address indexed indexer, address indexed allocationID, uint256 amount);

    uint256 internal constant ISSUANCE_RATE_PERIODS = 5;

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_1 = keccak256("subgraphDeploymentID1");

    address internal allocationID1 = makeAddr("allocationID1");

    /// Rewards of an allocation holding all of the allocated tokens, on a subgraph holding all the signal.
    function _expectedAllocationRewards(uint256 blocks, uint256 tokens) internal pure returns (uint256) {
        uint256 subgraphRewards = _expectedSubgraphRewards(blocks, SIGNAL, SIGNAL);
        return (_expectedRewardsPerAllocatedToken(subgraphRewards, tokens) * tokens) / 1e18;
    }

    function _setActiveAllocation(uint256 tokens, uint256 accRewardsPending) internal {
        issuer.setAllocation(allocationID1, true, indexer, SUBGRAPH_DEPLOYMENT_ID_1, tokens, 0, accRewardsPending);
        issuer.setSubgraphAllocatedTokens(SUBGRAPH_DEPLOYMENT_ID_1, tokens);
    }

    // -- subgraph service configuration --

    function test_SubgraphServiceConfiguration_RevertWhen_SetByNonGovernor() public {
        vm.prank(indexer);
        vm.expectRevert(bytes("Only Controller governor"));
        rm.setSubgraphService(makeAddr("newService"));
    }

    function test_SubgraphServiceConfiguration_SetsSubgraphServiceAsGovernor() public {
        address newService = makeAddr("newService");

        vm.expectEmit(address(rm));
        emit SubgraphServiceSet(address(issuer), newService);
        vm.prank(governor);
        rm.setSubgraphService(newService);

        assertEq(address(rm.subgraphService()), newService);
    }

    function test_SubgraphServiceConfiguration_AllowsSettingToZeroAddress() public {
        address service = makeAddr("service");
        vm.prank(governor);
        rm.setSubgraphService(service);

        vm.expectEmit(address(rm));
        emit SubgraphServiceSet(service, address(0));
        vm.prank(governor);
        rm.setSubgraphService(address(0));

        assertEq(address(rm.subgraphService()), address(0));
    }

    function test_SubgraphServiceConfiguration_EmitsEventWhenSettingDifferentAddress() public {
        address service1 = makeAddr("service1");
        address service2 = makeAddr("service2");

        vm.prank(governor);
        rm.setSubgraphService(service1);

        vm.expectEmit(address(rm));
        emit SubgraphServiceSet(service1, service2);
        vm.prank(governor);
        rm.setSubgraphService(service2);
    }

    // -- getRewards from subgraph service --

    function test_GetRewards_CalculatesRewardsForSubgraphServiceAllocations() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        _setActiveAllocation(ALLOCATION, 0);

        vm.roll(block.number + 10);

        uint256 rewards = rm.getRewards(address(issuer), allocationID1);
        assertGt(rewards, 0);
        assertEq(rewards, _expectedAllocationRewards(10, ALLOCATION));
    }

    function test_GetRewards_ZeroForInactiveAllocation() public {
        issuer.setAllocation(allocationID1, false, indexer, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION, 0, 0);

        assertEq(rm.getRewards(address(issuer), allocationID1), 0);
    }

    function test_GetRewards_RevertWhen_NotARewardsIssuer() public {
        address randomContract = makeAddr("randomContract");

        vm.expectRevert(bytes("Not a rewards issuer"));
        rm.getRewards(randomContract, allocationID1);
    }

    // -- takeRewards from subgraph service --

    function test_TakeRewards_TakesRewardsThroughSubgraphService() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        _setActiveAllocation(ALLOCATION, 0);

        vm.roll(block.number + 10);

        uint256 expectedRewards = _expectedAllocationRewards(10, ALLOCATION);
        uint256 beforeIssuerBalance = token.balanceOf(address(issuer));
        uint256 beforeTotalSupply = token.totalSupply();

        vm.expectEmit(address(rm));
        emit HorizonRewardsAssigned(indexer, allocationID1, expectedRewards);
        vm.prank(address(issuer));
        uint256 rewards = rm.takeRewards(allocationID1);

        assertEq(rewards, expectedRewards);
        assertEq(token.balanceOf(address(issuer)), beforeIssuerBalance + expectedRewards);
        assertEq(token.totalSupply(), beforeTotalSupply + expectedRewards);
    }

    function test_TakeRewards_ZeroRewardsForInactiveAllocation() public {
        issuer.setAllocation(allocationID1, false, indexer, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION, 0, 0);

        vm.recordLogs();
        vm.prank(address(issuer));
        rm.takeRewards(allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), HorizonRewardsAssigned.selector);
    }

    function test_TakeRewards_RevertWhen_CallerIsNotARewardsIssuer() public {
        vm.prank(indexer);
        vm.expectRevert(bytes("Caller must be a rewards issuer"));
        rm.takeRewards(allocationID1);
    }

    function test_TakeRewards_HandlesZeroRewardsScenario() public {
        vm.prank(governor);
        rm.setIssuancePerBlock(0);

        _setActiveAllocation(ALLOCATION, 0);

        vm.roll(block.number + 10);

        vm.recordLogs();
        vm.prank(address(issuer));
        uint256 rewards = rm.takeRewards(allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), HorizonRewardsAssigned.selector);

        assertEq(rewards, 0);
    }

    // -- mixed allocations from staking and subgraph service --
    // Titles are stale: there is a single rewards issuer now, so the assertions run against `issuer`.

    function test_MixedAllocationsFromStakingAndSubgraphService_AccountsForSubgraphServiceAllocationsInAccRewardsPerAllocatedToken()
        public
    {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);

        uint256 tokensFromSubgraphService = 5000 ether;
        issuer.setSubgraphAllocatedTokens(SUBGRAPH_DEPLOYMENT_ID_1, tokensFromSubgraphService);

        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        (uint256 accRewardsPerAllocatedToken, uint256 accRewardsForSubgraph) = rm.getAccRewardsPerAllocatedToken(
            SUBGRAPH_DEPLOYMENT_ID_1
        );

        assertGt(accRewardsPerAllocatedToken, 0);
        assertGt(accRewardsForSubgraph, 0);
        uint256 expectedForSubgraph = _expectedSubgraphRewards(ISSUANCE_RATE_PERIODS, SIGNAL, SIGNAL);
        assertEq(accRewardsForSubgraph, expectedForSubgraph);
        assertEq(
            accRewardsPerAllocatedToken,
            _expectedRewardsPerAllocatedToken(expectedForSubgraph, tokensFromSubgraphService)
        );
    }

    function test_MixedAllocationsFromStakingAndSubgraphService_HandlesCaseWhereOnlySubgraphServiceHasAllocations()
        public
    {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);

        uint256 tokensFromSubgraphService = 10_000 ether;
        issuer.setSubgraphAllocatedTokens(SUBGRAPH_DEPLOYMENT_ID_1, tokensFromSubgraphService);

        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        (uint256 accRewardsPerAllocatedToken, ) = rm.getAccRewardsPerAllocatedToken(SUBGRAPH_DEPLOYMENT_ID_1);

        assertGt(accRewardsPerAllocatedToken, 0);
        assertEq(
            accRewardsPerAllocatedToken,
            _expectedRewardsPerAllocatedToken(
                _expectedSubgraphRewards(ISSUANCE_RATE_PERIODS, SIGNAL, SIGNAL),
                tokensFromSubgraphService
            )
        );
    }

    function test_MixedAllocationsFromStakingAndSubgraphService_ZeroWhenNeitherIssuerHasAllocations() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);

        issuer.setSubgraphAllocatedTokens(SUBGRAPH_DEPLOYMENT_ID_1, 0);

        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        // With no allocations, rewards are reclaimed (NO_ALLOCATED_TOKENS), so both stay at zero
        (uint256 accRewardsPerAllocatedToken, uint256 accRewardsForSubgraph) = rm.getAccRewardsPerAllocatedToken(
            SUBGRAPH_DEPLOYMENT_ID_1
        );

        assertEq(accRewardsPerAllocatedToken, 0);
        assertEq(accRewardsForSubgraph, 0);
    }

    // -- subgraph service with denylist and eligibility --

    function test_SubgraphServiceWithDenylistAndEligibility_DeniesRewardsWhenSubgraphIsOnDenylist() public {
        vm.startPrank(governor);
        rm.setSubgraphAvailabilityOracle(governor);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        vm.stopPrank();

        // Pending rewards > 0 so there are rewards to deny
        _setActiveAllocation(ALLOCATION, 100 ether);

        vm.expectEmit(address(rm));
        emit RewardsDenied(indexer, allocationID1);
        vm.prank(address(issuer));
        rm.takeRewards(allocationID1);
    }

    function test_SubgraphServiceWithDenylistAndEligibility_DeniesRewardsWhenIndexerIsIneligible() public {
        // Oracle denies by default
        oracle.setDefaultResponse(false);
        vm.prank(governor);
        rm.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));

        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        _setActiveAllocation(ALLOCATION, 0);

        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        vm.expectEmit(address(rm));
        emit RewardsDeniedDueToEligibility(
            indexer,
            allocationID1,
            _expectedAllocationRewards(ISSUANCE_RATE_PERIODS, ALLOCATION)
        );
        vm.prank(address(issuer));
        rm.takeRewards(allocationID1);
    }
}
