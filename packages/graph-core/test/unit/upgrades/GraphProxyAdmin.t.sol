// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphProxy } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxy.sol";
import { IGraphProxyAdmin } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxyAdmin.sol";
import { IManagedMock } from "../interfaces/IManagedMock.sol";
import { GraphCoreTest } from "../shared/GraphCoreTest.t.sol";

contract GraphProxyAdminTest is GraphCoreTest {
    event PendingImplementationUpdated(
        address indexed oldPendingImplementation,
        address indexed newPendingImplementation
    );
    event ImplementationUpdated(address indexed oldImplementation, address indexed newImplementation);

    address internal me = makeAddr("me");
    IGraphProxy internal proxy;

    function setUp() public override {
        super.setUp();
        proxy = IGraphProxy(address(managed));
    }

    function _deployOtherProxyAdmin() internal returns (IGraphProxyAdmin) {
        vm.prank(governor);
        return
            IGraphProxyAdmin(
                _deployArtifact(string.concat(CORE_ARTIFACTS, "upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json"), "")
            );
    }

    // -- admin() --

    function test_Admin_GetsProxyAdmin() public view {
        assertEq(proxyAdmin.getProxyAdmin(proxy), address(proxyAdmin));
    }

    function test_Admin_RevertWhen_NotProxyAdmin() public {
        vm.expectRevert();
        vm.prank(governor);
        proxy.admin();
    }

    // -- implementation() --

    function test_Implementation_GetsFromProxyAdmin() public view {
        assertEq(proxyAdmin.getProxyImplementation(proxy), implA);
    }

    function test_Implementation_RevertWhen_NotProxyAdmin() public {
        vm.expectRevert();
        vm.prank(governor);
        proxy.implementation();
    }

    // -- pendingImplementation() --

    function test_PendingImplementation_GetsFromProxyAdmin() public view {
        assertEq(proxyAdmin.getProxyPendingImplementation(proxy), address(0));
    }

    function test_PendingImplementation_RevertWhen_NotProxyAdmin() public {
        vm.expectRevert();
        vm.prank(governor);
        proxy.pendingImplementation();
    }

    // -- upgrade --

    function test_Upgrade_UpgradesContract() public {
        vm.expectEmit(address(proxy));
        emit PendingImplementationUpdated(address(0), implB);
        vm.prank(governor);
        proxyAdmin.upgrade(proxy, implB);

        vm.expectEmit(address(proxy));
        emit ImplementationUpdated(implA, implB);
        vm.prank(governor);
        proxyAdmin.acceptProxy(implB, proxy);

        assertEq(proxyAdmin.getProxyImplementation(proxy), implB);
    }

    function test_Upgrade_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        proxyAdmin.upgrade(proxy, implB);
    }

    function test_Upgrade_RevertWhen_NotProxyAdmin() public {
        vm.expectRevert();
        vm.prank(governor);
        proxy.upgradeTo(implB);
    }

    // -- acceptUpgrade --

    function test_AcceptUpgrade_RevertWhen_NotProxyAdmin() public {
        vm.expectRevert();
        vm.prank(governor);
        proxy.acceptUpgrade();
    }

    // -- acceptProxy --

    function test_AcceptProxy_RevertWhen_NotProxyAdmin() public {
        vm.prank(governor);
        proxyAdmin.upgrade(proxy, implB);

        vm.expectRevert(bytes("Caller must be the proxy admin"));
        vm.prank(governor);
        IManagedMock(implB).acceptProxy(proxy);
    }

    // -- changeProxyAdmin --

    function test_ChangeProxyAdmin_SetsProxyAdmin() public {
        IGraphProxyAdmin otherProxyAdmin = _deployOtherProxyAdmin();

        vm.prank(governor);
        proxyAdmin.changeProxyAdmin(proxy, address(otherProxyAdmin));
        assertEq(otherProxyAdmin.getProxyAdmin(proxy), address(otherProxyAdmin));

        vm.expectRevert();
        vm.prank(governor);
        proxyAdmin.changeProxyAdmin(proxy, address(otherProxyAdmin));
    }

    function test_ChangeProxyAdmin_RevertWhen_NotGovernor() public {
        IGraphProxyAdmin otherProxyAdmin = _deployOtherProxyAdmin();

        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        proxyAdmin.changeProxyAdmin(proxy, address(otherProxyAdmin));
    }

    function test_ChangeProxyAdmin_RevertWhen_NotProxyAdmin() public {
        vm.expectRevert();
        vm.prank(governor);
        proxy.setAdmin(me);
    }
}
