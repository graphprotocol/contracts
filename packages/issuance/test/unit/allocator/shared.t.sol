// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IssuanceAllocator } from "../../../contracts/allocate/IssuanceAllocator.sol";
import { MockGraphToken } from "../mocks/MockGraphToken.sol";
import { MockSimpleTarget } from "../../../contracts/test/allocate/MockSimpleTarget.sol";
import { MockNotificationTracker } from "../../../contracts/test/allocate/MockNotificationTracker.sol";
import { MockRevertingTarget } from "../../../contracts/test/allocate/MockRevertingTarget.sol";
import { MockReentrantTarget } from "../../../contracts/test/allocate/MockReentrantTarget.sol";
import { MockERC165 } from "../../../contracts/test/allocate/MockERC165.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";

/// @notice Shared test setup for IssuanceAllocator tests.
contract IssuanceAllocatorSharedTest is Test {
    // -- Contracts --
    MockGraphToken internal token;
    IssuanceAllocator internal allocator;

    // -- Mock targets --
    MockSimpleTarget internal simpleTarget;
    MockNotificationTracker internal trackerTarget;
    MockRevertingTarget internal revertingTarget;
    MockReentrantTarget internal reentrantTarget;
    MockERC165 internal nonTarget; // supports ERC165 but not IIssuanceTarget

    // -- Accounts --
    address internal governor;
    address internal operator;
    address internal unauthorized;

    // -- Constants --
    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    uint256 internal constant ISSUANCE_PER_BLOCK = 100 ether;

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        vm.roll(1_000_000);

        governor = makeAddr("governor");
        operator = makeAddr("operator");
        unauthorized = makeAddr("unauthorized");

        // Deploy token
        token = new MockGraphToken();

        // Deploy IssuanceAllocator behind proxy
        IssuanceAllocator impl = new IssuanceAllocator(address(token));
        bytes memory initData = abi.encodeCall(IssuanceAllocator.initialize, (governor));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), address(this), initData);
        allocator = IssuanceAllocator(address(proxy));

        // Deploy mock targets
        simpleTarget = new MockSimpleTarget();
        trackerTarget = new MockNotificationTracker();
        revertingTarget = new MockRevertingTarget();
        reentrantTarget = new MockReentrantTarget();
        nonTarget = new MockERC165();

        // MockGraphToken has no access control on mint — allocator can call it freely.

        // Label addresses
        vm.label(address(token), "GraphToken");
        vm.label(address(allocator), "IssuanceAllocator");
        vm.label(address(simpleTarget), "SimpleTarget");
        vm.label(address(trackerTarget), "TrackerTarget");
        vm.label(address(revertingTarget), "RevertingTarget");
        vm.label(address(reentrantTarget), "ReentrantTarget");
    }

    // -- Helpers --

    /// @notice Add a target with the given allocation (in tokens per block)
    function _addTarget(IIssuanceTarget target, uint256 allocation) internal {
        vm.prank(governor);
        allocator.setTargetAllocation(target, allocation);
    }

    /// @notice Add a target with both allocator-minting and self-minting rates
    function _addTargetWithSelfMinting(
        IIssuanceTarget target,
        uint256 allocatorRate,
        uint256 selfMintingRate
    ) internal {
        vm.prank(governor);
        allocator.setTargetAllocation(target, allocatorRate, selfMintingRate);
    }

    /// @notice Set the issuance rate
    function _setIssuanceRate(uint256 rate) internal {
        vm.prank(governor);
        allocator.setIssuancePerBlock(rate);
    }
}
