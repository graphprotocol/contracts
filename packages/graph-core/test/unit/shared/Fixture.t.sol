// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphProxy } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxy.sol";
import { GraphCoreTest } from "./GraphCoreTest.t.sol";

contract FixtureTest is GraphCoreTest {
    string internal constant CONTROLLER_ARTIFACT =
        string.concat(CORE_ARTIFACTS, "governance/Controller.sol/Controller.json");
    string internal constant MISSING_ARTIFACT = string.concat(CORE_ARTIFACTS, "governance/Missing.sol/Missing.json");

    function deployArtifact(string memory path) external returns (address) {
        return _deployArtifact(path, "");
    }

    function test_Fixture_ArtifactReadable() public view {
        assertTrue(vm.isFile(CONTROLLER_ARTIFACT));
    }

    function test_Fixture_RevertWhen_ArtifactMissing() public {
        assertFalse(vm.isFile(MISSING_ARTIFACT));
        vm.expectRevert();
        this.deployArtifact(MISSING_ARTIFACT);
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
