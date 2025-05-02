// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { GraphUpgradeable } from "@graphprotocol/contracts/contracts/upgrades/GraphUpgradeable.sol";
import { Managed } from "../staking/utilities/Managed.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IIssuanceAllocator } from "@graphprotocol/contracts/contracts/issuance/IIssuanceAllocator.sol";

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
contract IssuanceAllocator is Initializable, GraphUpgradeable, Managed, IIssuanceAllocator {
    // -- Custom Errors --

    error ZeroTargetAddress();
    error TargetNotActive();
    error InsufficientAllocationAvailable();
    error TargetExistsWithDifferentSelfMinterFlag();
    error ControllerMismatch();

    // -- Constants --

    uint256 private constant PPM = 1_000_000; // 100% = 1,000,000 parts per million

    // -- State --

    struct AllocationTarget {
        string name;
        uint256 allocation; // In PPM (parts per million)
        bool isSelfMinter; // Whether this target is a self-minting contract
    }

    // No need for a separate graphToken variable - using the inherited graphToken() function from Managed

    // Total issuance per block
    uint256 public issuancePerBlock;

    // Last block when issuance was distributed
    uint256 public lastIssuanceBlock;

    // Allocation targets
    mapping(address => AllocationTarget) public allocationTargets;
    address[] public targetAddresses;

    // Total active allocation (can be less than PPM but never more)
    uint256 public totalActiveAllocation;

    // -- Events --

    event IssuanceDistributed(address indexed target, uint256 amount);
    event AllocationTargetAdded(address indexed target, string name, uint256 allocation, bool isSelfMinter);
    event AllocationTargetRemoved(address indexed target);
    event TargetAllocationUpdated(address indexed target, uint256 newAllocation);
    event IssuancePerBlockUpdated(uint256 oldIssuancePerBlock, uint256 newIssuancePerBlock);

    // -- Constructor --

    /**
     * @notice Constructor for the IssuanceAllocator contract
     * @param _controller Controller contract that manages this contract
     */
    constructor(address _controller) Managed(_controller) {
        _disableInitializers();
    }

    /**
     * @notice Initialize this contract.
     * @param _controller Controller contract that manages this contract
     * @param _issuancePerBlock Initial issuance per block
     */
    function initialize(address _controller, uint256 _issuancePerBlock) external onlyImpl initializer {
        if (_controller != address(_graphController())) revert ControllerMismatch();

        issuancePerBlock = _issuancePerBlock;
        lastIssuanceBlock = block.number;
    }

    // -- External Functions --

    /**
     * @notice Distribute issuance to all active targets.
     * @dev This function calculates token issuance for all active targets based on their
     * configured allocations. For non-self-minting targets, it mints tokens directly to them.
     * For self-minting targets (like the legacy RewardsManager), it only emits events but does
     * not mint tokens directly, as these contracts are expected to handle minting themselves.
     *
     * @dev The self-minting feature is intended only for backwards compatibility with existing
     * contracts and should not be used for new targets. New targets should be non-self-minting
     * to ensure centralized control over token issuance through the IssuanceAllocator.
     */
    function distributeIssuance() external override {
        uint256 blocksSinceLastIssuance = block.number - lastIssuanceBlock;
        if (blocksSinceLastIssuance == 0) return;

        uint256 newIssuance = issuancePerBlock * blocksSinceLastIssuance;
        lastIssuanceBlock = block.number;

        for (uint256 i = 0; i < targetAddresses.length; i++) {
            address target = targetAddresses[i];
            AllocationTarget storage targetData = allocationTargets[target];

            if (targetData.allocation > 0 && !targetData.isSelfMinter) {
                uint256 targetIssuance = (newIssuance * targetData.allocation) / PPM;

                _graphToken().mint(target, targetIssuance);
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
    function setIssuancePerBlock(uint256 _issuancePerBlock) external override onlyGovernor {
        if (_issuancePerBlock == issuancePerBlock) return;

        if (block.number > lastIssuanceBlock) {
            this.distributeIssuance();
        }

        uint256 oldIssuancePerBlock = issuancePerBlock;
        issuancePerBlock = _issuancePerBlock;

        emit IssuancePerBlockUpdated(oldIssuancePerBlock, _issuancePerBlock);
    }

    /**
     * @notice Add a new allocation target with zero allocation.
     * @dev This function can only be called by the governor.
     * @dev If the target already exists with the same self-minter flag, this function is a no-op.
     * @dev If the target already exists with a different self-minter flag, this function reverts.
     * @param _target Address of the target contract
     * @param _name Name of the target
     * @param _isSelfMinter Whether the target is a self-minting contract.
     *
     * @dev The _isSelfMinter parameter should typically be set to false for new targets.
     * It should only be set to true for backwards compatibility with existing contracts
     * like the RewardsManager that already have minting capabilities. Self-minting targets
     * will not have tokens minted to them by the IssuanceAllocator. Self-minting targets
     * should call getTargetIssuancePerBlock to determine their issuance amount and mint
     * tokens accordingly. For example, the RewardsManager contract is expected to call
     * getTargetIssuancePerBlock in its takeRewards function to calculate the correct
     * amount of tokens to mint. Self-minting targets are responsible for adhering to
     * the issuance schedule and should not mint more tokens than allocated.
     */
    function addAllocationTarget(
        address _target,
        string calldata _name,
        bool _isSelfMinter
    ) external override onlyGovernor {
        if (_target == address(0)) revert ZeroTargetAddress();

        if (bytes(allocationTargets[_target].name).length > 0) {
            if (allocationTargets[_target].isSelfMinter != _isSelfMinter) {
                revert TargetExistsWithDifferentSelfMinterFlag();
            }
            // Target already exists with the same self-minter flag, so this is a no-op
            return;
        }

        allocationTargets[_target] = AllocationTarget({ name: _name, allocation: 0, isSelfMinter: _isSelfMinter });

        targetAddresses.push(_target);

        emit AllocationTargetAdded(_target, _name, 0, _isSelfMinter);
    }

    /**
     * @notice Remove an allocation target completely.
     * @dev This function can only be called by the governor.
     * @dev This removes the target from the mapping and from the targetAddresses array using swap and pop.
     * @dev If the target doesn't exist, this function is a no-op.
     * @param _target Address of the target to remove
     */
    function removeAllocationTarget(address _target) external override onlyGovernor {
        if (bytes(allocationTargets[_target].name).length == 0) {
            // Target doesn't exist, so this is a no-op
            return;
        }

        if (allocationTargets[_target].allocation > 0) {
            totalActiveAllocation = totalActiveAllocation - allocationTargets[_target].allocation;
        }

        delete allocationTargets[_target];

        for (uint256 i = 0; i < targetAddresses.length; i++) {
            if (targetAddresses[i] == _target) {
                // Swap with the last element (if not already the last)
                if (i != targetAddresses.length - 1) {
                    targetAddresses[i] = targetAddresses[targetAddresses.length - 1];
                }

                targetAddresses.pop();
                break;
            }
        }

        emit AllocationTargetRemoved(_target);
    }

    /**
     * @notice Set the allocation for a target.
     * @dev This function can only be called by the governor.
     * @dev If the new allocation is the same as the current allocation, this function is a no-op.
     * @param _target Address of the target to update
     * @param _allocation Allocation for the target (in PPM)
     */
    function setTargetAllocation(address _target, uint256 _allocation) external override onlyGovernor {
        // Check if target exists in our mapping
        if (bytes(allocationTargets[_target].name).length == 0) revert TargetNotActive();

        uint256 oldAllocation = allocationTargets[_target].allocation;

        if (_allocation == oldAllocation) return;

        uint256 newTotalAllocation = totalActiveAllocation - oldAllocation + _allocation;

        if (newTotalAllocation > PPM) revert InsufficientAllocationAvailable();

        allocationTargets[_target].allocation = _allocation;
        totalActiveAllocation = newTotalAllocation;

        emit TargetAllocationUpdated(_target, _allocation);
    }

    /**
     * @notice Get the current allocation for a target.
     * @param _target Address of the target
     * @return Allocation for the target (in PPM), or 0 if the target is not registered
     */
    function getTargetAllocation(address _target) external view override returns (uint256) {
        // If target doesn't exist, it will return 0 by default
        return allocationTargets[_target].allocation;
    }

    /**
     * @notice Get all registered target addresses (including those with 0 allocation).
     * @return Array of registered target addresses
     */
    function getRegisteredTargets() external view override returns (address[] memory) {
        uint256 registeredCount = 0;

        // Count registered targets (those that exist in the mapping)
        for (uint256 i = 0; i < targetAddresses.length; i++) {
            address target = targetAddresses[i];
            if (bytes(allocationTargets[target].name).length > 0) {
                registeredCount++;
            }
        }

        // Create array of registered target addresses
        address[] memory registeredTargets = new address[](registeredCount);
        uint256 index = 0;

        for (uint256 i = 0; i < targetAddresses.length; i++) {
            address target = targetAddresses[i];
            if (bytes(allocationTargets[target].name).length > 0) {
                registeredTargets[index] = target;
                index++;
            }
        }

        return registeredTargets;
    }

    /**
     * @notice Calculate the issuance per block for a specific target.
     * @param _target Address of the target
     * @return Amount of tokens issued per block for the target, or 0 if the target is not registered
     */
    function getTargetIssuancePerBlock(address _target) external view override returns (uint256) {
        // If target doesn't exist or has 0 allocation, issuance will be 0
        return (issuancePerBlock * allocationTargets[_target].allocation) / PPM;
    }

    /**
     * @notice Check if a target is a self-minting contract.
     * @param _target Address of the target
     * @return True if the target is a registered self-minting contract, false otherwise
     *
     * @dev Self-minting targets are a special case for backwards compatibility with
     * existing contracts like the RewardsManager. The IssuanceAllocator calculates
     * issuance for these targets but does not mint tokens directly to them, as they
     * are expected to handle minting themselves. New targets should typically be
     * non-self-minting (return false) to ensure centralized control over token issuance.
     */
    function isSelfMinter(address _target) external view override returns (bool) {
        // If target doesn't exist, it will return false by default
        return allocationTargets[_target].isSelfMinter;
    }
}
