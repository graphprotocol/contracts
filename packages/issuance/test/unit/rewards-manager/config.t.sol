// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { RewardsManagerSharedTest } from "./shared.t.sol";

contract RewardsManagerConfigTest is RewardsManagerSharedTest {
    event ParameterUpdated(string param);
    event RewardsDenylistUpdated(bytes32 indexed subgraphDeploymentID, uint256 sinceBlock);

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_1 = keccak256("subgraphDeploymentID1");

    address internal availabilityOracle = makeAddr("availabilityOracle");

    // -- initialize --

    function test_Initialize_RevertWhen_CalledOnImplementation() public {
        // As in the old test, the call goes through the proxy, so `onlyImpl` rejects the caller
        vm.expectRevert(bytes("Only implementation"));
        vm.prank(governor);
        rm.initialize(address(controller));
    }

    // -- issuance per block update --

    function test_IssuancePerBlockUpdate_RevertWhen_Unauthorized() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(indexer);
        rm.setIssuancePerBlock(1.025 ether);
    }

    function test_IssuancePerBlockUpdate_SetToMinimumZero() public {
        vm.prank(governor);
        rm.setIssuancePerBlock(0);
        assertEq(rm.issuancePerBlock(), 0);
    }

    function test_IssuancePerBlockUpdate_SetIssuanceRate() public {
        uint256 newIssuancePerBlock = 100.025 ether;
        vm.prank(governor);
        rm.setIssuancePerBlock(newIssuancePerBlock);
        assertEq(rm.issuancePerBlock(), newIssuancePerBlock);
        assertEq(rm.accRewardsPerSignalLastBlockUpdated(), block.number);
    }

    function test_IssuancePerBlockUpdate_UpdatesTimestampFromZeroToNonZero() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, 10_000 ether);
        vm.roll(block.number + 10);

        vm.prank(governor);
        rm.setIssuancePerBlock(0);
        assertEq(rm.accRewardsPerSignalLastBlockUpdated(), block.number);

        vm.roll(block.number + 10);

        vm.prank(governor);
        rm.setIssuancePerBlock(ISSUANCE_PER_BLOCK);
        assertEq(
            rm.accRewardsPerSignalLastBlockUpdated(),
            block.number,
            "Timestamp should be updated when transitioning from zero issuance"
        );
    }

    function test_IssuancePerBlockUpdate_NoOverIssuanceAfterZeroPeriod() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, 10_000 ether);
        uint256 signalledTokens = token.balanceOf(address(curation));

        vm.roll(block.number + 10);

        vm.prank(governor);
        rm.updateAccRewardsPerSignal();
        uint256 rewardsAfterFirstPeriod = rm.accRewardsPerSignal();

        vm.prank(governor);
        rm.setIssuancePerBlock(0);
        uint256 timestampAfterZeroSet = rm.accRewardsPerSignalLastBlockUpdated();

        // No rewards accrue during zero issuance
        vm.roll(block.number + 10);

        vm.prank(governor);
        rm.setIssuancePerBlock(ISSUANCE_PER_BLOCK);
        uint256 timestampAfterRestore = rm.accRewardsPerSignalLastBlockUpdated();

        vm.roll(block.number + 10);

        vm.prank(governor);
        rm.updateAccRewardsPerSignal();
        uint256 finalRewards = rm.accRewardsPerSignal();
        uint256 finalTimestamp = rm.accRewardsPerSignalLastBlockUpdated();

        assertGt(
            timestampAfterRestore,
            timestampAfterZeroSet,
            "Timestamp should advance when setting non-zero issuance"
        );

        // Exact: the update and the zero-issuance set share a block, so no stray block accrues (old tolerance: 1 block)
        assertEq(
            finalRewards - rewardsAfterFirstPeriod,
            _expectedRewardsPerSignal(finalTimestamp - timestampAfterRestore, signalledTokens),
            "Rewards should match active period only"
        );
    }

    // -- subgraph availability service --

    function test_SubgraphAvailabilityService_RevertWhen_SetOracleUnauthorized() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(indexer);
        rm.setSubgraphAvailabilityOracle(availabilityOracle);
    }

    function test_SubgraphAvailabilityService_SetOracle() public {
        _setAvailabilityOracle(availabilityOracle);
        assertEq(rm.subgraphAvailabilityOracle(), availabilityOracle);
    }

    function test_SubgraphAvailabilityService_RevertWhen_DenyNotOracle() public {
        vm.expectRevert(bytes("Caller must be the subgraph availability oracle"));
        vm.prank(governor);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
    }

    function test_SubgraphAvailabilityService_Deny() public {
        _setAvailabilityOracle(availabilityOracle);

        vm.expectEmit(address(rm));
        emit RewardsDenylistUpdated(SUBGRAPH_DEPLOYMENT_ID_1, block.number);
        vm.prank(availabilityOracle);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        assertTrue(rm.isDenied(SUBGRAPH_DEPLOYMENT_ID_1));
    }

    function test_SubgraphAvailabilityService_Undeny() public {
        _setAvailabilityOracle(availabilityOracle);

        vm.prank(availabilityOracle);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        assertTrue(rm.isDenied(SUBGRAPH_DEPLOYMENT_ID_1));

        vm.expectEmit(address(rm));
        emit RewardsDenylistUpdated(SUBGRAPH_DEPLOYMENT_ID_1, 0);
        vm.prank(availabilityOracle);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID_1, false);
        assertFalse(rm.isDenied(SUBGRAPH_DEPLOYMENT_ID_1));
    }

    function test_SubgraphAvailabilityService_DenyAlreadyDeniedIsNoOp() public {
        _setAvailabilityOracle(availabilityOracle);

        vm.prank(availabilityOracle);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        assertTrue(rm.isDenied(SUBGRAPH_DEPLOYMENT_ID_1));
        uint256 denyBlockBefore = rm.denylist(SUBGRAPH_DEPLOYMENT_ID_1);

        vm.recordLogs();
        vm.prank(availabilityOracle);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        _assertNotEmitted(vm.getRecordedLogs(), RewardsDenylistUpdated.selector);

        assertTrue(rm.isDenied(SUBGRAPH_DEPLOYMENT_ID_1));
        assertEq(rm.denylist(SUBGRAPH_DEPLOYMENT_ID_1), denyBlockBefore);
    }

    function test_SubgraphAvailabilityService_UndenyNotDeniedIsNoOp() public {
        _setAvailabilityOracle(availabilityOracle);

        assertFalse(rm.isDenied(SUBGRAPH_DEPLOYMENT_ID_1));

        vm.recordLogs();
        vm.prank(availabilityOracle);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID_1, false);
        _assertNotEmitted(vm.getRecordedLogs(), RewardsDenylistUpdated.selector);

        assertFalse(rm.isDenied(SUBGRAPH_DEPLOYMENT_ID_1));
        assertEq(rm.denylist(SUBGRAPH_DEPLOYMENT_ID_1), 0);
    }

    function test_SubgraphAvailabilityService_RevertWhen_SetMinimumSubgraphSignalUnauthorized() public {
        vm.expectRevert(bytes("Not authorized"));
        vm.prank(indexer);
        rm.setMinimumSubgraphSignal(1000 ether);
    }

    function test_SubgraphAvailabilityService_SetMinimumSubgraphSignalFromOracle() public {
        _setAvailabilityOracle(availabilityOracle);

        uint256 newMinimumSignal = 2000 ether;
        vm.expectEmit(address(rm));
        emit ParameterUpdated("minimumSubgraphSignal");
        vm.prank(availabilityOracle);
        rm.setMinimumSubgraphSignal(newMinimumSignal);

        assertEq(rm.minimumSubgraphSignal(), newMinimumSignal);
    }

    function test_SubgraphAvailabilityService_SetMinimumSubgraphSignalFromGovernor() public {
        uint256 newMinimumSignal = 3000 ether;
        vm.expectEmit(address(rm));
        emit ParameterUpdated("minimumSubgraphSignal");
        vm.prank(governor);
        rm.setMinimumSubgraphSignal(newMinimumSignal);

        assertEq(rm.minimumSubgraphSignal(), newMinimumSignal);
    }

    // -- revertOnIneligible --

    function test_RevertOnIneligible_RevertWhen_Unauthorized() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(indexer);
        rm.setRevertOnIneligible(true);
    }

    function test_RevertOnIneligible_SetTrue() public {
        vm.expectEmit(address(rm));
        emit ParameterUpdated("revertOnIneligible");
        vm.prank(governor);
        rm.setRevertOnIneligible(true);
        assertTrue(rm.getRevertOnIneligible());
    }

    function test_RevertOnIneligible_SetFalse() public {
        vm.prank(governor);
        rm.setRevertOnIneligible(true);

        vm.expectEmit(address(rm));
        emit ParameterUpdated("revertOnIneligible");
        vm.prank(governor);
        rm.setRevertOnIneligible(false);
        assertFalse(rm.getRevertOnIneligible());
    }

    function test_RevertOnIneligible_SameValueFalseIsNoOp() public {
        assertFalse(rm.getRevertOnIneligible());

        vm.recordLogs();
        vm.prank(governor);
        rm.setRevertOnIneligible(false);
        _assertNotEmitted(vm.getRecordedLogs(), ParameterUpdated.selector);

        assertFalse(rm.getRevertOnIneligible());
    }

    function test_RevertOnIneligible_SameValueTrueIsNoOp() public {
        vm.prank(governor);
        rm.setRevertOnIneligible(true);

        vm.recordLogs();
        vm.prank(governor);
        rm.setRevertOnIneligible(true);
        _assertNotEmitted(vm.getRecordedLogs(), ParameterUpdated.selector);

        assertTrue(rm.getRevertOnIneligible());
    }
}
