// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import { IIssuanceAllocator } from "@graphprotocol/contracts/contracts/allocate/IIssuanceAllocator.sol";
import { IIssuanceTarget } from "@graphprotocol/contracts/contracts/allocate/IIssuanceTarget.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Roles } from "../common/Roles.sol";

/**
 * @title IssuanceAllocator
 * @notice This contract is responsible for allocating token issuance to different components
 * of the protocol. It calculates issuance for all targets based on their configured proportions
 * and handles minting for non-self-minting targets.
 *
 * @dev The contract distinguishes between two types of targets:
 * 1. Self-minting contracts: These are contracts that have their own minting authority. The IssuanceAllocator
 *    calculates issuance for these targets but does not mint tokens directly to them. Instead, these
 *    contracts are expected to call getTargetIssuancePerBlock to determine their issuance amount and
 *    mint tokens themselves. This feature is primarily intended for backwards compatibility with
 *    the existing RewardsManager contract.
 *
 * 2. Non-self-minting contracts: These are contracts that cannot mint tokens themselves. The IssuanceAllocator
 *    calculates issuance for these targets and mints tokens directly to them.
 *
 * New targets are expected to be non-self-minting, as this provides better centralized control
 * over token issuance through the IssuanceAllocator. The self-minting feature is intended only
 * for backwards compatibility with existing contracts.
 */
contract IssuanceAllocator is
    BaseUpgradeable,
    IIssuanceAllocator
{
    using Address for address;
    // -- Namespaced Storage --

    struct AllocationTarget {
        uint256 allocation; // In PPM (parts per million)
        bool exists; // Whether this target exists
        bool isSelfMinter; // Whether this target is a self-minting contract
    }

    /// @custom:storage-location erc7201:graphprotocol.storage.IssuanceAllocator
    struct IssuanceAllocatorData {
        // Total issuance per block
        uint256 issuancePerBlock;

        // Last block when issuance was distributed
        uint256 lastIssuanceBlock;

        // Allocation targets
        mapping(address => AllocationTarget) allocationTargets;
        address[] targetAddresses;

        // Total active allocation (can be less than PPM but never more)
        uint256 totalActiveAllocation;
    }

    /**
     * @dev Returns the storage struct for IssuanceAllocator
     */
    function _getIssuanceAllocatorStorage() private pure returns (IssuanceAllocatorData storage $) {
        // This value was calculated using: node scripts/calculate-storage-locations.js --contract IssuanceAllocator
        assembly {
            $.slot := 0x2d39b85bacae9509bd6a8a34a4de8c9bb5dbc76a31598e9bea496cdec9ff0100
        }
    }

    // -- Storage Getters --

    /**
     * @notice Get the total issuance per block
     */
    function issuancePerBlock() public view returns (uint256) {
        return _getIssuanceAllocatorStorage().issuancePerBlock;
    }

    /**
     * @notice Get the last block when issuance was distributed
     */
    function lastIssuanceBlock() public view returns (uint256) {
        return _getIssuanceAllocatorStorage().lastIssuanceBlock;
    }

    /**
     * @notice Get the allocation targets mapping
     */
    function allocationTargets(address _target) public view returns (AllocationTarget memory) {
        return _getIssuanceAllocatorStorage().allocationTargets[_target];
    }

    /**
     * @notice Get the target addresses array
     */
    function targetAddresses() public view returns (address[] memory) {
        return _getIssuanceAllocatorStorage().targetAddresses;
    }

    /**
     * @notice Get a specific target address by index
     */
    function targetAddresses(uint256 _index) public view returns (address) {
        return _getIssuanceAllocatorStorage().targetAddresses[_index];
    }

    /**
     * @notice Get the total active allocation
     */
    function totalActiveAllocation() public view returns (uint256) {
        return _getIssuanceAllocatorStorage().totalActiveAllocation;
    }
    // -- Custom Errors --

    error TargetAddressCannotBeZero();
    error TargetExistsWithDifferentSelfMinterFlag();
    error TargetNotRegistered();
    error InsufficientAllocationAvailable();

    // -- Events --

    event IssuanceDistributed(address indexed target, uint256 amount);
    event AllocationTargetAdded(address indexed target, bool isSelfMinter);
    event AllocationTargetRemoved(address indexed target);
    event TargetAllocationUpdated(address indexed target, uint256 newAllocation);
    event IssuancePerBlockUpdated(uint256 oldIssuancePerBlock, uint256 newIssuancePerBlock);

    /**
     * @notice Constructor for the IssuanceAllocator contract
     * @dev This contract is upgradeable, but we use the constructor to pass the Graph Token address
     * to the base contract.
     * @param _graphToken Address of the Graph Token contract
     */
    constructor(address _graphToken) BaseUpgradeable(_graphToken) {}

    // -- External Functions --

    /**
     * @notice Distribute issuance, minting tokens for non-self-minting targets.
     * @dev This function calculates token issuance for all targets based on their
     * configured allocations. For non-self-minting targets, it mints tokens directly to them.
     * For self-minting targets (like the legacy RewardsManager), it only emits events but does
     * not mint tokens directly, as these contracts are expected to handle minting themselves.
     *
     * @dev The self-minting feature is intended only for backwards compatibility with existing
     * contracts and should not be used for new targets. New targets should be non-self-minting
     * to ensure centralized control over token issuance through the IssuanceAllocator.
     */
    function distributeIssuance() external override whenNotPaused nonReentrant {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        uint256 blocksSinceLastIssuance = block.number - $.lastIssuanceBlock;
        if (blocksSinceLastIssuance == 0) return;

        uint256 newIssuance = $.issuancePerBlock * blocksSinceLastIssuance;
        $.lastIssuanceBlock = block.number;

        for (uint256 i = 0; i < $.targetAddresses.length; i++) {
            address target = $.targetAddresses[i];
            AllocationTarget storage targetData = $.allocationTargets[target];

            if (targetData.allocation > 0 && !targetData.isSelfMinter) {
                uint256 targetIssuance = (newIssuance * targetData.allocation) / PPM;

                GRAPH_TOKEN.mint(target, targetIssuance);
                emit IssuanceDistributed(target, targetIssuance);
            }
        }
    }

    /**
     * @notice Set the issuance per block.
     * @dev This function can only be called by the governor.
     * @dev If the new value is the same as the current value, this function is a no-op.
     * @param _issuancePerBlock New issuance per block
     */
    function setIssuancePerBlock(uint256 _issuancePerBlock) external override onlyRole(Roles.GOVERNOR) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        if (_issuancePerBlock == $.issuancePerBlock) return;

        // TODO: Think carefully about this !paused() check.
        // It means a change while paused will apply from lastIssuanceBlock.
        // I think we want this to address a wider range of scenarios,
        // but it changes the normal behaviour of a rate change.
        if (block.number > $.lastIssuanceBlock && !paused()) {
            this.distributeIssuance();
        }

        uint256 oldIssuancePerBlock = $.issuancePerBlock;
        $.issuancePerBlock = _issuancePerBlock;

        emit IssuancePerBlockUpdated(oldIssuancePerBlock, _issuancePerBlock);
    }

    /**
     * @notice Add a new allocation target with zero proportion.
     * @dev This function can only be called by the governor.
     * @dev The target must not already exist with a different self-minter flag.
     * @param _target Address of the target contract
     * @param _isSelfMinter Whether the target is a self-minting contract
     *
     * @dev Self-minting targets are a special case for backwards compatibility with
     * existing contracts like the RewardsManager. The IssuanceAllocator calculates
     * issuance for these targets but does not mint tokens directly to them. Self-minting targets
     * will not have tokens minted to them by the IssuanceAllocator. Self-minting targets
     * should call getTargetIssuancePerBlock to determine their issuance amount and mint
     * tokens accordingly. For example, the RewardsManager contract is expected to call
     * getTargetIssuancePerBlock in its takeRewards function to calculate the correct
     * amount of tokens to mint. Self-minting targets are responsible for adhering to
     * the issuance schedule and should not mint more tokens than allocated.
     */
    function addAllocationTarget(address _target, bool _isSelfMinter) external override onlyRole(Roles.GOVERNOR) {
        if (_target == address(0)) revert TargetAddressCannotBeZero();

        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[_target];

        // If the target already exists, make sure it has the same self-minter flag
        if (targetData.exists) {
            if (targetData.isSelfMinter != _isSelfMinter) revert TargetExistsWithDifferentSelfMinterFlag();
            return; // Target already exists, nothing to do
        }

        // Add the target
        targetData.isSelfMinter = _isSelfMinter;
        targetData.allocation = 0; // Start with zero allocation
        targetData.exists = true;
        $.targetAddresses.push(_target);

        emit AllocationTargetAdded(_target, _isSelfMinter);
    }

    /**
     * @notice Remove an allocation target.
     * @dev This function can only be called by the governor.
     * @dev If the target has a non-zero allocation, it will be set to zero first.
     * @param _target Address of the target to remove
     */
    function removeAllocationTarget(address _target) external override onlyRole(Roles.GOVERNOR) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[_target];
        if (!targetData.exists) revert TargetNotRegistered();

        // If the target has a non-zero allocation, set it to zero first
        if (targetData.allocation > 0) {
            // Notify the target if it implements IIssuanceTarget
            if (_target.code.length > 0) {
                try IIssuanceTarget(_target).preIssuanceAllocationChange() {} catch {}
            }

            $.totalActiveAllocation -= targetData.allocation;
            targetData.allocation = 0;
        }

        // Remove the target from the array
        for (uint256 i = 0; i < $.targetAddresses.length; i++) {
            if ($.targetAddresses[i] == _target) {
                $.targetAddresses[i] = $.targetAddresses[$.targetAddresses.length - 1];
                $.targetAddresses.pop();
                break;
            }
        }

        // Delete the target data
        delete $.allocationTargets[_target];

        emit AllocationTargetRemoved(_target);
    }

    /**
     * @notice Set the allocation for a target.
     * @dev This function can only be called by the governor.
     * @dev If the new allocation is the same as the current allocation, this function is a no-op.
     * @param _target Address of the target to update
     * @param _allocation Allocation for the target (in PPM)
     */
    function setTargetAllocation(address _target, uint256 _allocation) external override onlyRole(Roles.GOVERNOR) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[_target];
        if (!targetData.exists) revert TargetNotRegistered();

        // If the allocation is the same, do nothing
        if (targetData.allocation == _allocation) return;

        // Ensure the new total allocation doesn't exceed PPM
        uint256 newTotalAllocation = $.totalActiveAllocation - targetData.allocation + _allocation;
        if (newTotalAllocation > PPM) revert InsufficientAllocationAvailable();

        // Notify the target if it implements IIssuanceTarget
        if (_target.code.length > 0) {
            try IIssuanceTarget(_target).preIssuanceAllocationChange() {} catch {}
        }

        // Update the allocation
        $.totalActiveAllocation = newTotalAllocation;
        targetData.allocation = _allocation;

        emit TargetAllocationUpdated(_target, _allocation);
    }

    /**
     * @notice Get the current allocation for a target.
     * @param _target Address of the target
     * @return Allocation for the target (in PPM), or 0 if the target is not registered
     */
    function getTargetAllocation(address _target) external view override returns (uint256) {
        return _getIssuanceAllocatorStorage().allocationTargets[_target].allocation;
    }

    /**
     * @notice Get all registered target addresses (including those with 0 allocation).
     * @return Array of registered target addresses
     */
    function getRegisteredTargets() external view override returns (address[] memory) {
        return _getIssuanceAllocatorStorage().targetAddresses;
    }

    /**
     * @notice Calculate the issuance per block for a specific target.
     * @param _target Address of the target
     * @return Amount of tokens issued per block for the target, or 0 if the target is not registered
     */
    function getTargetIssuancePerBlock(address _target) external view override returns (uint256) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[_target];

        return ($.issuancePerBlock * targetData.allocation) / PPM;
    }

    /**
     * @notice Check if a target is a self-minting contract.
     * @param _target Address of the target
     * @return True if the target is a registered self-minting contract, false otherwise
     *
     * @dev Self-minting targets are a special case for backwards compatibility with
     * existing contracts like the RewardsManager. The IssuanceAllocator calculates
     * issuance for these targets but does not mint tokens directly to them.
     */
    function isSelfMinter(address _target) external view override returns (bool) {
        return _getIssuanceAllocatorStorage().allocationTargets[_target].isSelfMinter;
    }
}
