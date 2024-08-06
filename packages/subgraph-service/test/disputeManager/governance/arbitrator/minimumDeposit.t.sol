// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DisputeManagerGovernanceDisputeDepositTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Governance_SetDisputeDeposit() public useGovernor {
        uint256 disputeDeposit = 100 ether;
        disputeManager.setDisputeDeposit(disputeDeposit);
        assertEq(disputeManager.disputeDeposit(), disputeDeposit, "Dispute deposit should be set.");
    }

    function test_Governance_RevertWhen_ZeroValue() public useGovernor {
        uint256 disputeDeposit = 0;
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDisputeDeposit.selector, disputeDeposit));
        disputeManager.setDisputeDeposit(disputeDeposit);
    }

    function test_Governance_RevertWhen_NotGovernor() public useFisherman {
        uint256 disputeDeposit = 100 ether;
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.fisherman));
        disputeManager.setDisputeDeposit(disputeDeposit);
    }
}
