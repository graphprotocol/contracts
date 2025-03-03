// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DisputeManagerGovernanceDisputeDepositTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Governance_SetDisputeDeposit(uint256 disputeDeposit) public useGovernor {
        vm.assume(disputeDeposit >= MIN_DISPUTE_DEPOSIT);
        _setDisputeDeposit(disputeDeposit);
    }

    function test_Governance_RevertWhen_DepositTooLow(uint256 disputeDeposit) public useGovernor {
        vm.assume(disputeDeposit < MIN_DISPUTE_DEPOSIT);
        vm.expectRevert(
            abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDisputeDeposit.selector, disputeDeposit)
        );
        disputeManager.setDisputeDeposit(disputeDeposit);
    }

    function test_Governance_RevertWhen_NotGovernor() public useFisherman {
        uint256 disputeDeposit = 100 ether;
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.fisherman)
        );
        disputeManager.setDisputeDeposit(disputeDeposit);
    }
}
