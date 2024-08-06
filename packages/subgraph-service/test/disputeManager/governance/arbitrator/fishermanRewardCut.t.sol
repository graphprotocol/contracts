// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DisputeManagerGovernanceFishermanRewardCutTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Governance_SetFishermanRewardCut() public useGovernor {
        uint32 fishermanRewardCut = 1000;
        disputeManager.setFishermanRewardCut(fishermanRewardCut);
        assertEq(disputeManager.fishermanRewardCut(), fishermanRewardCut, "Fisherman reward cut should be set.");
    }

    function test_Governance_RevertWhen_NotPPM() public useGovernor {
        uint32 fishermanRewardCut = 10000000;
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidFishermanReward.selector, fishermanRewardCut));
        disputeManager.setFishermanRewardCut(fishermanRewardCut);
    }

    function test_Governance_RevertWhen_NotGovernor() public useFisherman {
        uint32 fishermanRewardCut = 1000;
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.fisherman));
        disputeManager.setFishermanRewardCut(fishermanRewardCut);
    }
}
