// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGoverned } from "@graphprotocol/interfaces/contracts/contracts/governance/IGoverned.sol";
import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";

contract GovernedTest is ProtocolFixture {
    event NewPendingOwnership(address indexed from, address indexed to);
    event NewOwnership(address indexed from, address indexed to);

    IGoverned internal governed;
    address internal me = makeAddr("me");

    function setUp() public {
        vm.warp(1_700_000_000);
        governor = makeAddr("governor");
        vm.prank(governor);
        governed = IGoverned(
            _deployArtifact(string.concat(PKG_ARTIFACTS, "tests/GovernedMock.sol/GovernedMock.json"), "")
        );
        assertEq(governed.governor(), governor);
    }

    function test_Governed_RevertWhen_TransferNotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        governed.transferOwnership(me);
    }

    function test_Governed_TransferAndAccept() public {
        vm.expectEmit(address(governed));
        emit NewPendingOwnership(address(0), me);
        vm.prank(governor);
        governed.transferOwnership(me);

        vm.expectRevert(bytes("Caller must be pending governor"));
        vm.prank(governor);
        governed.acceptOwnership();

        vm.expectEmit(address(governed));
        emit NewOwnership(governor, me);
        vm.prank(me);
        governed.acceptOwnership();

        assertEq(governed.pendingGovernor(), address(0));
    }

    function test_Governed_RevertWhen_TransferToZero() public {
        vm.expectRevert(bytes("Governor must be set"));
        vm.prank(governor);
        governed.transferOwnership(address(0));
    }
}
