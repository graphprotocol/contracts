// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DisputeManagerGovernanceFishermanRewardCutTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Governance_SetFishermanRewardCut(uint32 fishermanRewardCut) public useGovernor {
        vm.assume(fishermanRewardCut <= disputeManager.MAX_FISHERMAN_REWARD_CUT());
        _setFishermanRewardCut(fishermanRewardCut);
    }

    function test_Governance_RevertWhen_OverMaximumValue(uint32 fishermanRewardCut) public useGovernor {
        vm.assume(fishermanRewardCut > disputeManager.MAX_FISHERMAN_REWARD_CUT());
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidFishermanReward.selector, fishermanRewardCut));
        disputeManager.setFishermanRewardCut(fishermanRewardCut);
    }

    function test_Governance_RevertWhen_NotGovernor() public useFisherman {
        uint32 fishermanRewardCut = 1000;
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.fisherman));
        disputeManager.setFishermanRewardCut(fishermanRewardCut);
    }
}