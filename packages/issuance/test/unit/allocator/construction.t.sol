// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseUpgradeable } from "../../../contracts/common/BaseUpgradeable.sol";
import { IssuanceAllocator } from "../../../contracts/allocate/IssuanceAllocator.sol";
import { IssuanceAllocatorSharedTest } from "./shared.t.sol";

/// @notice Construction and initialization tests for IssuanceAllocator.
contract IssuanceAllocatorConstructionTest is IssuanceAllocatorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_Revert_ZeroGraphTokenAddress() public {
        vm.expectRevert(BaseUpgradeable.GraphTokenCannotBeZeroAddress.selector);
        new IssuanceAllocator(address(0));
    }

    function test_Revert_ZeroGovernorAddress() public {
        IssuanceAllocator impl = new IssuanceAllocator(address(token));
        bytes memory initData = abi.encodeCall(IssuanceAllocator.initialize, (address(0)));
        vm.expectRevert(BaseUpgradeable.GovernorCannotBeZeroAddress.selector);
        new TransparentUpgradeableProxy(address(impl), address(this), initData);
    }

    function test_Init_GovernorRoleSet() public view {
        assertTrue(allocator.hasRole(GOVERNOR_ROLE, governor));
    }

    function test_Init_DefaultTargetCount() public view {
        // Should have 1 target (the default at index 0)
        assertEq(allocator.getTargetCount(), 1);
    }

    function test_Init_DefaultTargetIsZeroAddress() public view {
        assertEq(allocator.getTargetAt(0), address(0));
    }

    function test_Init_IssuancePerBlockIsZero() public view {
        assertEq(allocator.getIssuancePerBlock(), 0);
    }

    function test_Init_LastDistributionBlockIsCurrentBlock() public view {
        assertEq(allocator.getDistributionState().lastDistributionBlock, block.number);
    }

    function test_Revert_DoubleInitialization() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        allocator.initialize(governor);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
