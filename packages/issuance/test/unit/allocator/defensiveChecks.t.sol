// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IssuanceAllocator } from "../../../contracts/allocate/IssuanceAllocator.sol";
import { IssuanceAllocatorTestHarness } from "../../../contracts/test/allocate/IssuanceAllocatorTestHarness.sol";
import { MockGraphToken } from "../mocks/MockGraphToken.sol";

/// @notice Tests for defensive checks in IssuanceAllocator internal functions.
contract IssuanceAllocatorDefensiveChecksTest is Test {
    /* solhint-disable graph/func-name-mixedcase */

    IssuanceAllocatorTestHarness internal harness;

    function setUp() public {
        MockGraphToken token = new MockGraphToken();
        IssuanceAllocatorTestHarness impl = new IssuanceAllocatorTestHarness(address(token));
        bytes memory initData = abi.encodeCall(IssuanceAllocator.initialize, (address(this)));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), address(this), initData);
        harness = IssuanceAllocatorTestHarness(address(proxy));
    }

    function test_DistributePendingProportionally_AllocatedRateZero() public {
        // Defensive: allocatedRate == 0 should return early without reverting
        harness.exposedDistributePendingProportionally(100, 0, 1000);
    }

    function test_DistributePendingProportionally_AvailableZero() public {
        // Defensive: available == 0 should return early without reverting
        harness.exposedDistributePendingProportionally(0, 100, 1000);
    }

    function test_DistributePendingProportionally_BothZero() public {
        // Defensive: both == 0 should return early without reverting
        harness.exposedDistributePendingProportionally(0, 0, 1000);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
