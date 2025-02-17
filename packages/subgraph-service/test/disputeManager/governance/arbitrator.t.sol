// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DisputeManagerGovernanceArbitratorTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Governance_SetArbitrator() public useGovernor {
        address arbitrator = makeAddr("newArbitrator");
        _setArbitrator(arbitrator);
    }

    function test_Governance_RevertWhen_ZeroAddress() public useGovernor {
        address arbitrator = address(0);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidZeroAddress.selector));
        disputeManager.setArbitrator(arbitrator);
    }

    function test_Governance_RevertWhen_NotGovernor() public useFisherman {
        address arbitrator = makeAddr("newArbitrator");
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.fisherman)
        );
        disputeManager.setArbitrator(arbitrator);
    }
}
