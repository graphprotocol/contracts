// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DisputeManagerGovernanceMaxSlashingCutTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Governance_SetMaxSlashingCut(uint32 maxSlashingCut) public useGovernor {
        vm.assume(maxSlashingCut <= MAX_PPM);
        _setMaxSlashingCut(maxSlashingCut);
    }

    function test_Governance_RevertWhen_NotPPM(uint32 maxSlashingCut) public useGovernor {
        vm.assume(maxSlashingCut > MAX_PPM);
        vm.expectRevert(
            abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidMaxSlashingCut.selector, maxSlashingCut)
        );
        disputeManager.setMaxSlashingCut(maxSlashingCut);
    }

    function test_Governance_RevertWhen_NotGovernor() public useFisherman {
        uint32 maxSlashingCut = 1000;
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.fisherman)
        );
        disputeManager.setMaxSlashingCut(maxSlashingCut);
    }
}
