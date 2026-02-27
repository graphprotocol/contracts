// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IIssuanceAllocationAdministration } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationAdministration.sol";
import { IIssuanceAllocationData } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationData.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceAllocationStatus } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationStatus.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { ISendTokens } from "@graphprotocol/interfaces/contracts/issuance/allocate/ISendTokens.sol";
import { IPausableControl } from "@graphprotocol/interfaces/contracts/issuance/common/IPausableControl.sol";

/// @notice Interface ID stability tests for issuance allocate contracts.
/// @dev These guard against accidental interface changes that would break deployed contract compatibility.
///      If a test fails, verify the interface change was intentional and document the breaking change.
contract AllocateInterfaceIdStabilityTest is Test {
    /* solhint-disable graph/func-name-mixedcase */

    // -- IssuanceAllocator interfaces --

    function test_InterfaceId_IIssuanceAllocationDistribution() public pure {
        assertEq(type(IIssuanceAllocationDistribution).interfaceId, bytes4(0x79da37fc));
    }

    function test_InterfaceId_IIssuanceAllocationAdministration() public pure {
        assertEq(type(IIssuanceAllocationAdministration).interfaceId, bytes4(0x50d8541d));
    }

    function test_InterfaceId_IIssuanceAllocationStatus() public pure {
        assertEq(type(IIssuanceAllocationStatus).interfaceId, bytes4(0xa896602d));
    }

    function test_InterfaceId_IIssuanceAllocationData() public pure {
        assertEq(type(IIssuanceAllocationData).interfaceId, bytes4(0x48c3c62e));
    }

    // -- DirectAllocation / shared interfaces --

    function test_InterfaceId_IIssuanceTarget() public pure {
        assertEq(type(IIssuanceTarget).interfaceId, bytes4(0xaee4dc43));
    }

    function test_InterfaceId_ISendTokens() public pure {
        assertEq(type(ISendTokens).interfaceId, bytes4(0x05ab421d));
    }

    // -- Common interfaces --

    function test_InterfaceId_IPausableControl() public pure {
        assertEq(type(IPausableControl).interfaceId, bytes4(0xe78a39d8));
    }

    function test_InterfaceId_IAccessControl() public pure {
        assertEq(type(IAccessControl).interfaceId, bytes4(0x7965db0b));
    }

    /* solhint-enable graph/func-name-mixedcase */
}
