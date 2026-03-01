// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { IRewardsEligibilityAdministration } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityAdministration.sol";
import { IRewardsEligibilityMaintenance } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityMaintenance.sol";
import { IRewardsEligibilityReporting } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityReporting.sol";
import { IRewardsEligibilityStatus } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityStatus.sol";
import { IPausableControl } from "@graphprotocol/interfaces/contracts/issuance/common/IPausableControl.sol";

import { RewardsEligibilityOracleSharedTest } from "./shared.t.sol";

/// @notice ERC-165 interface compliance and interface ID stability tests.
contract RewardsEligibilityOracleInterfaceTest is RewardsEligibilityOracleSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== ERC-165 Support ====================

    function test_SupportsERC165() public view {
        assertTrue(oracle.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsIProviderEligibility() public view {
        assertTrue(oracle.supportsInterface(type(IProviderEligibility).interfaceId));
    }

    function test_SupportsIRewardsEligibilityAdministration() public view {
        assertTrue(oracle.supportsInterface(type(IRewardsEligibilityAdministration).interfaceId));
    }

    function test_SupportsIRewardsEligibilityMaintenance() public view {
        assertTrue(oracle.supportsInterface(type(IRewardsEligibilityMaintenance).interfaceId));
    }

    function test_SupportsIRewardsEligibilityReporting() public view {
        assertTrue(oracle.supportsInterface(type(IRewardsEligibilityReporting).interfaceId));
    }

    function test_SupportsIRewardsEligibilityStatus() public view {
        assertTrue(oracle.supportsInterface(type(IRewardsEligibilityStatus).interfaceId));
    }

    function test_SupportsIPausableControl() public view {
        assertTrue(oracle.supportsInterface(type(IPausableControl).interfaceId));
    }

    function test_SupportsIAccessControl() public view {
        assertTrue(oracle.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_DoesNotSupportRandomInterface() public view {
        assertFalse(oracle.supportsInterface(bytes4(0xdeadbeef)));
    }

    // ==================== Interface ID Stability ====================
    // These guard against accidental interface changes that would break compatibility.

    function test_InterfaceId_IProviderEligibility() public pure {
        assertEq(type(IProviderEligibility).interfaceId, bytes4(0x66e305fd));
    }

    function test_InterfaceId_IRewardsEligibilityAdministration() public pure {
        assertEq(type(IRewardsEligibilityAdministration).interfaceId, bytes4(0x428f54e5));
    }

    function test_InterfaceId_IRewardsEligibilityMaintenance() public pure {
        assertEq(type(IRewardsEligibilityMaintenance).interfaceId, bytes4(0x6f001113));
    }

    function test_InterfaceId_IRewardsEligibilityReporting() public pure {
        assertEq(type(IRewardsEligibilityReporting).interfaceId, bytes4(0x38b7c077));
    }

    function test_InterfaceId_IRewardsEligibilityStatus() public pure {
        assertEq(type(IRewardsEligibilityStatus).interfaceId, bytes4(0x054cdbc2));
    }

    /* solhint-enable graph/func-name-mixedcase */
}
