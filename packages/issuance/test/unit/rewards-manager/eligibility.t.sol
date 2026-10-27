// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";

import { MockERC165 } from "../../../contracts/test/allocate/MockERC165.sol";
import { RewardsManagerSharedTest } from "./shared.t.sol";

contract RewardsManagerEligibilityTest is RewardsManagerSharedTest {
    event ProviderEligibilityOracleSet(IProviderEligibility indexed oldOracle, IProviderEligibility indexed newOracle);
    event HorizonRewardsAssigned(address indexed indexer, address indexed allocationID, uint256 amount);
    event RewardsDenied(address indexed indexer, address indexed allocationID);
    event RewardsDeniedDueToEligibility(address indexed indexer, address indexed allocationID, uint256 amount);

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_1 = keccak256("subgraphDeploymentID1");

    address internal allocationID1 = makeAddr("allocationID1");

    function _findLog(Vm.Log[] memory logs, bytes32 topic) internal view returns (Vm.Log memory) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(rm) && logs[i].topics[0] == topic) return logs[i];
        }
        revert("log not found");
    }

    // -- rewards eligibility oracle --

    function test_RewardsEligibilityOracle_RevertWhen_Unauthorized() public {
        vm.prank(indexer);
        vm.expectRevert(bytes("Only Controller governor"));
        rm.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));
    }

    function test_RewardsEligibilityOracle_SetsOracleAsGovernor() public {
        vm.expectEmit(address(rm));
        emit ProviderEligibilityOracleSet(IProviderEligibility(address(0)), IProviderEligibility(address(oracle)));
        vm.prank(governor);
        rm.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));

        assertEq(address(rm.getProviderEligibilityOracle()), address(oracle));
    }

    function test_RewardsEligibilityOracle_AllowsSettingToZeroAddress() public {
        vm.prank(governor);
        rm.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));

        vm.expectEmit(address(rm));
        emit ProviderEligibilityOracleSet(IProviderEligibility(address(oracle)), IProviderEligibility(address(0)));
        vm.prank(governor);
        rm.setProviderEligibilityOracle(IProviderEligibility(address(0)));

        assertEq(address(rm.getProviderEligibilityOracle()), address(0));
    }

    function test_RewardsEligibilityOracle_RevertWhen_OracleIsEOA() public {
        // An EOA has no code, so the supportsInterface call reverts
        vm.prank(governor);
        vm.expectRevert();
        rm.setProviderEligibilityOracle(IProviderEligibility(indexer));
    }

    function test_RewardsEligibilityOracle_RevertWhen_InterfaceNotSupported() public {
        MockERC165 mockERC165 = new MockERC165();

        vm.prank(governor);
        vm.expectRevert(bytes("Contract does not support IProviderEligibility interface"));
        rm.setProviderEligibilityOracle(IProviderEligibility(address(mockERC165)));
    }

    function test_RewardsEligibilityOracle_NoEventWhenSettingSameOracle() public {
        vm.prank(governor);
        rm.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));

        vm.recordLogs();
        vm.prank(governor);
        rm.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));
        _assertNotEmitted(vm.getRecordedLogs(), ProviderEligibilityOracleSet.selector);
    }

    // -- rewards eligibility in takeRewards --

    function test_RewardsEligibilityInTakeRewards_DeniesRewardsDueToEligibilityOracle() public {
        _useEligibilityOracle(false);
        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.expectEmit(address(rm), 1);
        emit RewardsDeniedDueToEligibility(indexer, allocationID1, expectedRewards);
        _close(allocationID1);
    }

    function test_RewardsEligibilityInTakeRewards_AllowsRewardsWhenOracleApproves() public {
        _useEligibilityOracle(true);
        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.expectEmit(address(rm), 1);
        emit HorizonRewardsAssigned(indexer, allocationID1, expectedRewards);
        _close(allocationID1);
    }

    // -- rewards eligibility oracle and denylist interaction --

    function test_RewardsEligibilityOracleAndDenylistInteraction_PrioritizesDenylistOverOracleWhenBothDeny() public {
        _setAvailabilityOracle(governor);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        _useEligibilityOracle(false);

        // Created while denied: the accumulator is frozen, so the allocation has no rewards to deny
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.recordLogs();
        _close(allocationID1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertNotEmitted(logs, RewardsDenied.selector);
        _assertNotEmitted(logs, RewardsDeniedDueToEligibility.selector);
        _assertNotEmitted(logs, HorizonRewardsAssigned.selector);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_ChecksOracleWhenDenylistAllowsButIndexerIneligible()
        public
    {
        _useEligibilityOracle(false);
        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.expectEmit(address(rm), 1);
        emit RewardsDeniedDueToEligibility(indexer, allocationID1, expectedRewards);
        _close(allocationID1);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_IndexerBecomesIneligibleMidAllocation() public {
        _useEligibilityOracle(true);
        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        // Eligibility is checked at close time, not at creation time
        oracle.setIndexerEligible(indexer, false);

        vm.expectEmit(address(rm), 1);
        emit RewardsDeniedDueToEligibility(indexer, allocationID1, expectedRewards);
        _close(allocationID1);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_IndexerBecomesEligibleMidAllocation() public {
        _useEligibilityOracle(false);
        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        oracle.setIndexerEligible(indexer, true);

        vm.expectEmit(address(rm), 1);
        emit HorizonRewardsAssigned(indexer, allocationID1, expectedRewards);
        _close(allocationID1);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_DenylistAddedMidAllocation() public {
        _setAvailabilityOracle(governor);
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        vm.roll(block.number + 1);

        vm.expectEmit(address(rm));
        emit RewardsDenied(indexer, allocationID1);
        _close(allocationID1);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_DenylistRemovedMidAllocation() public {
        _setAvailabilityOracle(governor);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);

        // Created while denied: rewards accrued while denied are reclaimed at the subgraph level
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        // Undeny snapshots the accumulator, then only post-undeny rewards accrue
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, false);
        vm.roll(block.number + EPOCH_LENGTH);

        vm.expectEmit(address(rm));
        emit HorizonRewardsAssigned(
            indexer,
            allocationID1,
            _expectedAllocationRewards(EPOCH_LENGTH, ALLOCATION, ALLOCATION)
        );
        _close(allocationID1);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_AllowsRewardsWhenOracleIsZeroAddress() public {
        assertEq(address(rm.getProviderEligibilityOracle()), address(0));

        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.expectEmit(address(rm), 1);
        emit HorizonRewardsAssigned(indexer, allocationID1, expectedRewards);
        _close(allocationID1);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_RevertWhen_IneligibleAndRevertOnIneligible() public {
        _useEligibilityOracle(false);
        vm.prank(governor);
        rm.setRevertOnIneligible(true);

        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.expectRevert(bytes("Indexer not eligible for rewards"));
        issuer.close(allocationID1);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_NoRevertForEligibleWhenRevertOnIneligible() public {
        _useEligibilityOracle(true);
        vm.prank(governor);
        rm.setRevertOnIneligible(true);

        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.expectEmit(address(rm));
        emit HorizonRewardsAssigned(indexer, allocationID1, expectedRewards);
        _close(allocationID1);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_ReclaimsForIneligibleWhenNotRevertOnIneligible()
        public
    {
        _useEligibilityOracle(false);
        assertFalse(rm.getRevertOnIneligible());

        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.expectEmit(address(rm), 1);
        emit RewardsDeniedDueToEligibility(indexer, allocationID1, expectedRewards);
        uint256 rewards = _close(allocationID1);
        assertEq(rewards, 0);
    }

    function test_RewardsEligibilityOracleAndDenylistInteraction_EventStructureDiffersBetweenDenialMechanisms() public {
        uint256 snapshot = vm.snapshotState();

        // Denylist denial: event WITHOUT amount. Deny after the allocation so there are rewards to deny.
        _setAvailabilityOracle(governor);
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        vm.roll(block.number + 1);

        vm.recordLogs();
        _close(allocationID1);
        Vm.Log memory denied = _findLog(vm.getRecordedLogs(), RewardsDenied.selector);
        assertEq(denied.topics.length, 3);
        assertEq(denied.topics[1], bytes32(uint256(uint160(indexer))));
        assertEq(denied.topics[2], bytes32(uint256(uint160(allocationID1))));
        assertEq(denied.data.length, 0);

        // Reset, as the old test's fixture teardown and setup
        vm.revertToState(snapshot);

        // Eligibility denial: event WITH amount, what the indexer would have received
        _useEligibilityOracle(false);
        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.recordLogs();
        _close(allocationID1);
        Vm.Log memory ineligible = _findLog(vm.getRecordedLogs(), RewardsDeniedDueToEligibility.selector);
        assertEq(ineligible.topics.length, 3);
        assertEq(ineligible.topics[1], bytes32(uint256(uint160(indexer))));
        assertEq(ineligible.topics[2], bytes32(uint256(uint160(allocationID1))));
        uint256 amount = abi.decode(ineligible.data, (uint256));
        assertGt(amount, 0);
        assertEq(amount, expectedRewards);
    }
}
