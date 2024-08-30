// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DisputeManagerGovernanceMaxSlashingCutTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Governance_SetMaxSlashingCut() public useGovernor {
        uint32 maxSlashingCut = 1000;
        disputeManager.setMaxSlashingCut(maxSlashingCut);
        assertEq(disputeManager.maxSlashingCut(), maxSlashingCut, "Max slashing cut should be set.");
    }

    function test_Governance_RevertWhen_NotPPM() public useGovernor {
        uint32 maxSlashingCut = 10000000;
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidMaxSlashingCut.selector, maxSlashingCut));
        disputeManager.setMaxSlashingCut(maxSlashingCut);
    }

    function test_Governance_RevertWhen_NotGovernor() public useFisherman {
        uint32 maxSlashingCut = 1000;
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.fisherman));
        disputeManager.setMaxSlashingCut(maxSlashingCut);
    }
}
