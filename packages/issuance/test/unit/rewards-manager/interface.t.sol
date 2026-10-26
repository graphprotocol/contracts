// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IProviderEligibilityManagement } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibilityManagement.sol";

import { RewardsManagerSharedTest } from "./shared.t.sol";

/// @notice Interface ids are stable across builds: a change is a breaking change to the interface definitions.
contract RewardsManagerInterfaceTest is RewardsManagerSharedTest {
    // -- Interface ID Stability --

    function test_InterfaceIdStability_IERC165() public pure {
        assertEq(type(IERC165).interfaceId, bytes4(0x01ffc9a7));
    }

    function test_InterfaceIdStability_IIssuanceTarget() public pure {
        assertEq(type(IIssuanceTarget).interfaceId, bytes4(0x19f6601a));
    }

    function test_InterfaceIdStability_IRewardsManager() public pure {
        assertEq(type(IRewardsManager).interfaceId, bytes4(0x8469b577));
    }

    // -- supportsInterface --

    function test_SupportsInterface_IIssuanceTarget() public view {
        assertTrue(rm.supportsInterface(type(IIssuanceTarget).interfaceId));
    }

    function test_SupportsInterface_IRewardsManager() public view {
        assertTrue(rm.supportsInterface(type(IRewardsManager).interfaceId));
    }

    function test_SupportsInterface_IERC165() public view {
        assertTrue(rm.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_IProviderEligibilityManagement() public view {
        assertTrue(rm.supportsInterface(type(IProviderEligibilityManagement).interfaceId));
    }

    function test_SupportsInterface_FalseForUnsupported() public view {
        assertFalse(rm.supportsInterface(bytes4(0x12345678)));
    }

    // -- getter functions --

    function test_GetterFunctions_IssuanceAllocatorZeroWhenNotSet() public view {
        assertEq(address(rm.getIssuanceAllocator()), address(0));
    }

    function test_GetterFunctions_EligibilityOracleZeroWhenNotSet() public view {
        assertEq(address(rm.getProviderEligibilityOracle()), address(0));
    }

    function test_GetterFunctions_ReclaimAddressZeroWhenNotSet() public view {
        assertEq(rm.getReclaimAddress(bytes32(0)), address(0));
    }

    // -- calcRewards --

    function test_CalcRewards_Calculates() public view {
        // (1000 * 0.5 * 1e18) / 1e18 = 500 GRT
        assertEq(rm.calcRewards(1000 ether, 0.5 ether), 500 ether);
    }

    function test_CalcRewards_ZeroWhenTokensZero() public view {
        assertEq(rm.calcRewards(0, 0.5 ether), 0);
    }

    function test_CalcRewards_ZeroWhenAccRewardsPerAllocatedTokenZero() public view {
        assertEq(rm.calcRewards(1000 ether, 0), 0);
    }
}
