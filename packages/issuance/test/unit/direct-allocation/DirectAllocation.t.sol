// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { ISendTokens } from "@graphprotocol/interfaces/contracts/issuance/allocate/ISendTokens.sol";

import { BaseUpgradeable } from "../../../contracts/common/BaseUpgradeable.sol";
import { DirectAllocation } from "../../../contracts/allocate/DirectAllocation.sol";
import { MockGraphToken } from "../mocks/MockGraphToken.sol";

/// @notice Tests for DirectAllocation contract.
contract DirectAllocationTest is Test {
    /* solhint-disable graph/func-name-mixedcase */

    MockGraphToken internal token;
    DirectAllocation internal directAlloc;

    address internal governor;
    address internal operator;
    address internal unauthorized;
    address internal user;

    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    function setUp() public virtual {
        governor = makeAddr("governor");
        operator = makeAddr("operator");
        unauthorized = makeAddr("unauthorized");
        user = makeAddr("user");

        token = new MockGraphToken();

        DirectAllocation impl = new DirectAllocation(address(token));
        bytes memory initData = abi.encodeCall(DirectAllocation.initialize, (governor));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), address(this), initData);
        directAlloc = DirectAllocation(address(proxy));

        vm.label(address(token), "GraphToken");
        vm.label(address(directAlloc), "DirectAllocation");
    }

    // ==================== Construction ====================

    function test_Revert_ZeroGraphTokenAddress() public {
        vm.expectRevert(BaseUpgradeable.GraphTokenCannotBeZeroAddress.selector);
        new DirectAllocation(address(0));
    }

    function test_Revert_ZeroGovernorAddress() public {
        DirectAllocation impl = new DirectAllocation(address(token));
        bytes memory initData = abi.encodeCall(DirectAllocation.initialize, (address(0)));
        vm.expectRevert(BaseUpgradeable.GovernorCannotBeZeroAddress.selector);
        new TransparentUpgradeableProxy(address(impl), address(this), initData);
    }

    function test_Revert_DoubleInitialization() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        directAlloc.initialize(governor);
    }

    function test_Init_GovernorRoleSet() public view {
        assertTrue(directAlloc.hasRole(GOVERNOR_ROLE, governor));
    }

    function test_Init_OperatorNotSet() public view {
        assertFalse(directAlloc.hasRole(OPERATOR_ROLE, operator));
    }

    // ==================== Token Sending ====================

    function test_SendTokens_Success() public {
        // Mint tokens to directAlloc
        token.mint(address(directAlloc), 1000 ether);

        // Grant operator role
        vm.prank(governor);
        directAlloc.grantRole(OPERATOR_ROLE, operator);

        // Send tokens
        vm.prank(operator);
        directAlloc.sendTokens(user, 100 ether);

        assertEq(token.balanceOf(user), 100 ether);
        assertEq(token.balanceOf(address(directAlloc)), 900 ether);
    }

    function test_Revert_SendTokens_NonOperator() public {
        token.mint(address(directAlloc), 1000 ether);

        vm.expectRevert();
        vm.prank(unauthorized);
        directAlloc.sendTokens(user, 100 ether);
    }

    function test_Revert_SendTokens_WhenPaused() public {
        token.mint(address(directAlloc), 1000 ether);

        vm.prank(governor);
        directAlloc.grantRole(OPERATOR_ROLE, operator);
        vm.prank(governor);
        directAlloc.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        directAlloc.pause();

        vm.expectRevert();
        vm.prank(operator);
        directAlloc.sendTokens(user, 100 ether);
    }

    function test_Revert_SendTokens_InsufficientBalance() public {
        vm.prank(governor);
        directAlloc.grantRole(OPERATOR_ROLE, operator);

        vm.expectRevert();
        vm.prank(operator);
        directAlloc.sendTokens(user, 100 ether);
    }

    // ==================== IIssuanceTarget Interface ====================

    function test_BeforeIssuanceAllocationChange_NoOp() public {
        // Should not revert — it's a no-op
        directAlloc.beforeIssuanceAllocationChange();
    }

    function test_SetIssuanceAllocator_NoOp() public {
        vm.prank(governor);
        directAlloc.setIssuanceAllocator(makeAddr("allocator"));
    }

    function test_Revert_SetIssuanceAllocator_NonGovernor() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        directAlloc.setIssuanceAllocator(makeAddr("allocator"));
    }

    // ==================== ERC-165 Interface Support ====================

    function test_SupportsInterface_IERC165() public view {
        assertTrue(directAlloc.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_IIssuanceTarget() public view {
        assertTrue(directAlloc.supportsInterface(type(IIssuanceTarget).interfaceId));
    }

    function test_SupportsInterface_ISendTokens() public view {
        assertTrue(directAlloc.supportsInterface(type(ISendTokens).interfaceId));
    }

    function test_SupportsInterface_IAccessControl() public view {
        assertTrue(directAlloc.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_DoesNotSupportRandomInterface() public view {
        assertFalse(directAlloc.supportsInterface(bytes4(0xdeadbeef)));
    }

    // ==================== Role Hierarchy ====================

    function test_RoleAdminHierarchy() public view {
        assertEq(directAlloc.getRoleAdmin(GOVERNOR_ROLE), GOVERNOR_ROLE);
        assertEq(directAlloc.getRoleAdmin(OPERATOR_ROLE), GOVERNOR_ROLE);
        assertEq(directAlloc.getRoleAdmin(PAUSE_ROLE), GOVERNOR_ROLE);
    }

    // ==================== Transfer Returns False ====================

    function test_Revert_SendTokens_TransferReturnsFalse() public {
        // Deploy DirectAllocation with a mock token that returns false on transfer
        MockFalseTransferToken falseToken = new MockFalseTransferToken();
        DirectAllocation impl2 = new DirectAllocation(address(falseToken));
        bytes memory initData2 = abi.encodeCall(DirectAllocation.initialize, (governor));
        TransparentUpgradeableProxy proxy2 = new TransparentUpgradeableProxy(address(impl2), address(this), initData2);
        DirectAllocation da2 = DirectAllocation(address(proxy2));

        // Grant operator
        vm.prank(governor);
        da2.grantRole(OPERATOR_ROLE, operator);

        // sendTokens should revert with SendTokensFailed because transfer returns false
        vm.expectRevert(abi.encodeWithSelector(DirectAllocation.SendTokensFailed.selector, user, 100 ether));
        vm.prank(operator);
        da2.sendTokens(user, 100 ether);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

/// @notice Minimal ERC20 that always returns false on transfer (instead of reverting).
contract MockFalseTransferToken {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function balanceOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }
}
