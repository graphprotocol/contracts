// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { ILegacyAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/ILegacyAllocation.sol";
import { LegacyAllocationHarness } from "../mocks/LegacyAllocationHarness.sol";

contract LegacyAllocationLibraryTest is Test {
    LegacyAllocationHarness private harness;
    address private allocationId;

    function setUp() public {
        harness = new LegacyAllocationHarness();
        allocationId = makeAddr("allocationId");
    }

    function test_LegacyAllocation_Get() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        harness.migrate(address(1), allocationId, bytes32("sdid"));

        ILegacyAllocation.State memory alloc = harness.get(allocationId);
        assertEq(alloc.indexer, address(1));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(alloc.subgraphDeploymentId, bytes32("sdid"));
    }

    function test_LegacyAllocation_Get_RevertWhen_NotExists() public {
        address nonExistent = makeAddr("nonExistent");
        vm.expectRevert(abi.encodeWithSelector(ILegacyAllocation.LegacyAllocationDoesNotExist.selector, nonExistent));
        harness.get(nonExistent);
    }
}
