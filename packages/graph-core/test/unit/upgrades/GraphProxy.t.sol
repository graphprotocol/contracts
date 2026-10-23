// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphProxy } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxy.sol";
import { IManagedMock } from "../interfaces/IManagedMock.sol";
import { GraphCoreTest } from "../shared/GraphCoreTest.t.sol";

contract GraphProxyTest is GraphCoreTest {
    IGraphProxy internal proxy;

    function setUp() public override {
        super.setUp();
        proxy = IGraphProxy(address(managed));
    }

    function test_GraphProxy_RevertWhen_AcceptUpgradeAndCallFails() public {
        vm.prank(governor);
        proxyAdmin.upgrade(proxy, implB);

        // The delegatecall runs with msg.sender == implB, which is not the governor
        vm.expectRevert(bytes("Impl call failed"));
        vm.prank(implB);
        proxy.acceptUpgradeAndCall(abi.encodeCall(IManagedMock.checkOnlyGovernor, ()));
    }

    function test_GraphProxy_RevertWhen_AdminCallsFallback() public {
        vm.expectRevert(bytes("Cannot fallback to proxy target"));
        vm.prank(address(proxyAdmin));
        managed.checkNotPaused();
    }

    function test_GraphProxy_RevertWhen_SetAdminZero() public {
        vm.expectRevert(bytes("Admin cant be the zero address"));
        vm.prank(address(proxyAdmin));
        proxy.setAdmin(address(0));
    }

    function test_GraphProxy_RevertWhen_AcceptUpgradeWithoutPendingImplementation() public {
        vm.expectRevert(bytes("Impl cannot be zero address"));
        vm.prank(address(proxyAdmin));
        proxy.acceptUpgrade();
    }

    function test_GraphProxy_RevertWhen_AcceptUpgradeNotPendingImplementation() public {
        vm.prank(governor);
        proxyAdmin.upgrade(proxy, implB);

        vm.expectRevert(bytes("Only pending implementation"));
        vm.prank(address(proxyAdmin));
        proxy.acceptUpgrade();
    }
}
