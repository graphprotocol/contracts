// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

/**
 * @title IssuanceAllocatorStorage
 * @notice Storage contract for IssuanceAllocator
 * @dev This contract defines the storage layout for the IssuanceAllocator contract
 */
abstract contract IssuanceAllocatorStorage {
    struct AllocationTarget {
        uint256 allocation; // In PPM (parts per million)
        bool exists; // Whether this target exists
        bool isSelfMinter; // Whether this target is a self-minting contract
    }

    // Total issuance per block
    uint256 public issuancePerBlock;

    // Last block when issuance was distributed
    uint256 public lastIssuanceBlock;

    // Allocation targets
    mapping(address => AllocationTarget) public allocationTargets;
    address[] public targetAddresses;

    // Total active allocation (can be less than PPM but never more)
    uint256 public totalActiveAllocation;

    // -- Storage Gap --

    // Gap for future storage variables in upgrades
    uint256[50] private __gap;
}
