// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";
import { GraphCoreTest } from "../shared/GraphCoreTest.t.sol";

contract ManagedTest is GraphCoreTest {
    event ContractSynced(bytes32 indexed nameHash, address contractAddress);

    address internal me = makeAddr("me");

    /// In the order ManagedMock.resolveAll and Managed.syncAllContracts use
    function _names() internal pure returns (string[7] memory) {
        return ["Curation", "EpochManager", "RewardsManager", "Staking", "GraphToken", "GraphTokenGateway", "GNS"];
    }

    function _registerAll(string memory prefix) internal returns (address[7] memory addrs) {
        string[7] memory names = _names();
        for (uint256 i = 0; i < 7; i++) {
            addrs[i] = makeAddr(string.concat(prefix, names[i]));
            _registerContract(names[i], addrs[i]);
        }
    }

    function test_Managed_SyncAllContractsEmitsPerChangedId() public {
        address curation = makeAddr("curation");
        address staking = makeAddr("staking");
        address gns = makeAddr("gns");
        _registerContract("Curation", curation);
        _registerContract("Staking", staking);
        _registerContract("GNS", gns);

        vm.expectEmit(address(managed));
        emit ContractSynced(keccak256("Curation"), curation);
        vm.expectEmit(address(managed));
        emit ContractSynced(keccak256("Staking"), staking);
        vm.expectEmit(address(managed));
        emit ContractSynced(keccak256("GNS"), gns);
        managed.syncAllContracts();

        vm.recordLogs();
        managed.syncAllContracts();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], ContractSynced.selector);
        }
    }

    function test_Managed_ResolveAllUsesControllerThenCache() public {
        address[7] memory registered = _registerAll("first");
        address[7] memory resolved = managed.resolveAll();
        for (uint256 i = 0; i < 7; i++) {
            assertEq(resolved[i], registered[i]);
        }

        managed.syncAllContracts();
        _registerAll("second");

        resolved = managed.resolveAll();
        for (uint256 i = 0; i < 7; i++) {
            assertEq(resolved[i], registered[i]);
        }
    }

    function test_Managed_RevertWhen_CheckOnlyGovernorNotGovernor() public {
        assertEq(controller.getGovernor(), governor);
        vm.prank(governor);
        managed.checkOnlyGovernor();

        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(me);
        managed.checkOnlyGovernor();
    }
}
