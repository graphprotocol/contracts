// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphProxy } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxy.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { GraphCoreTest } from "./GraphCoreTest.t.sol";

contract FixtureTest is GraphCoreTest {
    function getCode(string memory id) external view returns (bytes memory) {
        return vm.getCode(id);
    }

    function test_Fixture_ArtifactReadable() public view {
        assertGt(vm.getCode("Controller.sol:Controller").length, 0);
    }

    function test_Fixture_RevertWhen_ArtifactMissing() public {
        vm.expectRevert();
        this.getCode("Missing.sol:Missing");
    }

    function test_Fixture_FoundryControllerMatchesHardhat() public {
        vm.skip(vm.isContext(VmSafe.ForgeContext.Coverage));
        string memory json = vm.readFile("artifacts/contracts/governance/Controller.sol/Controller.json");
        bytes memory hardhat = _stripMetadata(vm.parseJsonBytes(json, ".bytecode"));
        bytes memory foundry = _stripMetadata(vm.getCode("Controller.sol:Controller"));
        assertGt(hardhat.length, 0);
        assertEq(foundry, hardhat);
    }

    function test_Fixture_ProxyWiredToImplementation() public view {
        IGraphProxy proxy = IGraphProxy(address(managed));
        assertEq(proxyAdmin.getProxyAdmin(proxy), address(proxyAdmin));
        assertEq(proxyAdmin.getProxyImplementation(proxy), implA);
        assertEq(proxyAdmin.getProxyPendingImplementation(proxy), address(0));
        assertEq(address(managed.controller()), address(controller));
    }

    function test_Fixture_ControllerUnpaused() public view {
        assertFalse(controller.paused());
        assertFalse(controller.partialPaused());
        managed.checkNotPartialPaused();
    }
}
