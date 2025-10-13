// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { TargetIssuancePerBlock, Allocation, AllocationTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocatorTypes.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceAllocationAdministration } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationAdministration.sol";
import { IIssuanceAllocationStatus } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationStatus.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title IssuanceAllocator
 * @author Edge & Node
 * @notice This contract is responsible for allocating token issuance to different components
 * of the protocol. It calculates issuance for all targets based on their configured proportions
 * and handles minting for allocator-minting portions.
 *
 * @dev The contract supports two types of allocation for each target:
 * 1. Allocator-minting allocation: The IssuanceAllocator calculates and mints tokens directly to targets
 *    for this portion of their allocation.
 *
 * 2. Self-minting allocation: The IssuanceAllocator calculates issuance but does not mint tokens directly.
 *    Instead, targets are expected to call `getTargetIssuancePerBlock` to determine their self-minting
 *    issuance amount and mint tokens themselves. This feature is primarily intended for backwards
 *    compatibility with existing contracts like the RewardsManager.
 *
 * Each target can have both allocator-minting and self-minting allocations. New targets are expected
 * to use allocator-minting allocation to provide more robust control over token issuance through
 * the IssuanceAllocator. The self-minting allocation is intended only for backwards compatibility
 * with existing contracts.
 *
 * @dev There are a number of scenarios where the IssuanceAllocator could run into issues, including:
 * 1. The targetAddresses array could grow large enough that it exceeds the gas limit when calling distributeIssuance.
 * 2. When notifying targets of allocation changes the calls to `beforeIssuanceAllocationChange` could exceed the gas limit.
 * 3. Target contracts could revert when notifying them of changes via `beforeIssuanceAllocationChange`.
 * While in practice the IssuanceAllocator is expected to have a relatively small number of trusted targets, and the
 * gas limit is expected to be high enough to handle the above scenarios, the following would allow recovery:
 * 1. The contract can be paused, which can help make the recovery process easier to manage.
 * 2. The GOVERNOR_ROLE can directly trigger change notification to individual targets. As there is per target
 *    tracking of the lastChangeNotifiedBlock, this can reduce the gas cost of other operations and allow
 *    for graceful recovery.
 * 3. If a target reverts when notifying it of changes or notifying it is too expensive, the GOVERNOR_ROLE can use `forceTargetNoChangeNotificationBlock()`
 *    to skip notifying that particular target of changes.
 *
 * In combination these should allow recovery from gas limit issues or malfunctioning targets, with fine-grained control over
 * which targets are notified of changes and when.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any bugs. We might have an active bug bounty program.
 */
contract IssuanceAllocator is
    BaseUpgradeable,
    IIssuanceAllocationDistribution,
    IIssuanceAllocationAdministration,
    IIssuanceAllocationStatus
{
    // -- Namespaced Storage --

    /// @notice ERC-7201 storage location for IssuanceAllocator
    bytes32 private constant ISSUANCE_ALLOCATOR_STORAGE_LOCATION =
        // solhint-disable-next-line gas-small-strings
        keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.IssuanceAllocator")) - 1)) &
            ~bytes32(uint256(0xff));

    /// @notice Main storage structure for IssuanceAllocator using ERC-7201 namespaced storage
    /// @param issuancePerBlock Total issuance per block across all targets
    /// @param lastDistributionBlock Last block when issuance was distributed
    /// @param lastAccumulationBlock Last block when pending issuance was accumulated
    /// @dev Design invariant: lastDistributionBlock <= lastAccumulationBlock
    /// @param allocationTargets Mapping of target addresses to their allocation data
    /// @param targetAddresses Array of all target addresses with non-zero allocation
    /// @param totalAllocatorMintingPPM Total allocator-minting allocation (in PPM) across all targets
    /// @param totalSelfMintingPPM Total self-minting allocation (in PPM) across all targets
    /// @param pendingAccumulatedAllocatorIssuance Accumulated but not distributed issuance for allocator-minting from lastDistributionBlock to lastAccumulationBlock
    /// @custom:storage-location erc7201:graphprotocol.storage.IssuanceAllocator
    struct IssuanceAllocatorData {
        uint256 issuancePerBlock;
        uint256 lastDistributionBlock;
        uint256 lastAccumulationBlock;
        mapping(address => AllocationTarget) allocationTargets;
        address[] targetAddresses;
        uint256 totalAllocatorMintingPPM;
        uint256 totalSelfMintingPPM;
        uint256 pendingAccumulatedAllocatorIssuance;
    }

    /**
     * @notice Returns the storage struct for IssuanceAllocator
     * @return $ contract storage
     */
    function _getIssuanceAllocatorStorage() private pure returns (IssuanceAllocatorData storage $) {
        // solhint-disable-previous-line use-natspec
        // Solhint does not support $ return variable in natspec

        bytes32 slot = ISSUANCE_ALLOCATOR_STORAGE_LOCATION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    // -- Custom Errors --

    /// @notice Thrown when attempting to add a target with zero address
    error TargetAddressCannotBeZero();

    /// @notice Thrown when the total allocation would exceed 100% (PPM)
    error InsufficientAllocationAvailable();

    /// @notice Thrown when a target does not support the IIssuanceTarget interface
    error TargetDoesNotSupportIIssuanceTarget();

    /// @notice Thrown when toBlockNumber is out of valid range for accumulation
    error ToBlockOutOfRange();

    // -- Events --

    /// @notice Emitted when issuance is distributed to a target
    /// @param target The address of the target that received issuance
    /// @param amount The amount of tokens distributed
    event IssuanceDistributed(address indexed target, uint256 amount); // solhint-disable-line gas-indexed-events
    // Do not need to index amount, filtering by amount ranges is not expected use case

    /// @notice Emitted when a target's allocation is updated
    /// @param target The address of the target whose allocation was updated
    /// @param newAllocatorMintingPPM The new allocator-minting allocation (in PPM) for the target
    /// @param newSelfMintingPPM The new self-minting allocation (in PPM) for the target
    event TargetAllocationUpdated(address indexed target, uint256 newAllocatorMintingPPM, uint256 newSelfMintingPPM); // solhint-disable-line gas-indexed-events
    // Do not need to index PPM values

    /// @notice Emitted when the issuance per block is updated
    /// @param oldIssuancePerBlock The previous issuance per block amount
    /// @param newIssuancePerBlock The new issuance per block amount
    event IssuancePerBlockUpdated(uint256 oldIssuancePerBlock, uint256 newIssuancePerBlock); // solhint-disable-line gas-indexed-events
    // Do not need to index issuance per block values

    // -- Constructor --

    /**
     * @notice Constructor for the IssuanceAllocator contract
     * @dev This contract is upgradeable, but we use the constructor to pass the Graph Token address
     * to the base contract.
     * @param _graphToken Address of the Graph Token contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address _graphToken) BaseUpgradeable(_graphToken) {}

    // -- Initialization --

    /**
     * @notice Initialize the IssuanceAllocator contract
     * @param _governor Address that will have the GOVERNOR_ROLE
     */
    function initialize(address _governor) external virtual initializer {
        __BaseUpgradeable_init(_governor);
    }

    // -- Core Functionality --

    /**
     * @inheritdoc ERC165Upgradeable
     * @dev Supports the three IssuanceAllocator sub-interfaces
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IIssuanceAllocationDistribution).interfaceId ||
            interfaceId == type(IIssuanceAllocationAdministration).interfaceId ||
            interfaceId == type(IIssuanceAllocationStatus).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @inheritdoc IIssuanceAllocationDistribution
     * @dev Implementation details:
     * - For allocator-minting portions, tokens are minted and transferred directly to targets based on their allocation
     * - For self-minting portions (like the legacy RewardsManager), it does not mint tokens directly. Instead, these contracts are expected to handle minting themselves
     * - The self-minting allocation is intended only for backwards compatibility with existing contracts and should not be used for new targets. New targets should use allocator-minting allocation to ensure robust control of token issuance by the IssuanceAllocator
     * - Unless paused will always result in lastIssuanceBlock == block.number, even if there is no issuance to distribute
     */
    function distributeIssuance() external override returns (uint256) {
        return _distributeIssuance();
    }

    /**
     * @notice Internal implementation for `distributeIssuance`
     * @dev Handles the actual distribution logic.
     * @return Block number distributed to
     */
    function _distributeIssuance() private returns (uint256) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        if (paused()) return $.lastDistributionBlock;

        _distributePendingIssuance();

        uint256 blocksSinceLastIssuance = block.number - $.lastDistributionBlock;
        if (blocksSinceLastIssuance == 0) return $.lastDistributionBlock;

        // Note: Theoretical overflow risk exists if issuancePerBlock * blocksSinceLastIssuance > type(uint256).max
        // In practice, this would require either:
        // 1. Extremely high issuancePerBlock (governance error), and/or
        // 2. Contract paused for an implausibly long time (decades)
        // If such overflow occurs, the transaction reverts (Solidity 0.8.x), indicating the contract
        // is in a state requiring governance intervention.
        uint256 newIssuance = $.issuancePerBlock * blocksSinceLastIssuance;
        $.lastDistributionBlock = block.number;
        $.lastAccumulationBlock = block.number;

        if (0 < newIssuance) {
            for (uint256 i = 0; i < $.targetAddresses.length; ++i) {
                address target = $.targetAddresses[i];
                AllocationTarget storage targetData = $.allocationTargets[target];

                if (0 < targetData.allocatorMintingPPM) {
                    // There can be a small rounding loss here. This is acceptable.
                    uint256 targetIssuance = (newIssuance * targetData.allocatorMintingPPM) / MILLION;

                    GRAPH_TOKEN.mint(target, targetIssuance);
                    emit IssuanceDistributed(target, targetIssuance);
                }
            }
        }

        return $.lastDistributionBlock;
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Implementation details:
     * - `distributeIssuance` will be called before changing the rate *unless the contract is paused and evenIfDistributionPending is false*
     * - `beforeIssuanceAllocationChange` will be called on all targets before changing the rate, even when the contract is paused
     * - Whenever the rate is changed, the updateL2MintAllowance function _must_ be called on the L1GraphTokenGateway in L1, to ensure the bridge can mint the right amount of tokens
     */
    function setIssuancePerBlock(
        uint256 newIssuancePerBlock,
        bool evenIfDistributionPending
    ) external override onlyRole(GOVERNOR_ROLE) returns (bool) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        if (newIssuancePerBlock == $.issuancePerBlock) return true;

        if (_distributeIssuance() < block.number) {
            if (evenIfDistributionPending) accumulatePendingIssuance();
            else return false;
        }
        notifyAllTargets();

        uint256 oldIssuancePerBlock = $.issuancePerBlock;
        $.issuancePerBlock = newIssuancePerBlock;

        emit IssuancePerBlockUpdated(oldIssuancePerBlock, newIssuancePerBlock);
        return true;
    }

    // -- Target Management --

    /**
     * @notice Internal function to notify a target about an upcoming allocation change
     * @dev Uses per-target lastChangeNotifiedBlock to prevent reentrancy and duplicate notifications.
     *
     * Will revert if the target's beforeIssuanceAllocationChange call fails.
     * Use forceTargetNoChangeNotificationBlock to skip notification for malfunctioning targets.
     *
     * @param target Address of the target to notify
     * @return True if notification was sent or already sent for this block
     */
    function _notifyTarget(address target) private returns (bool) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[target];

        // Check-effects-interactions pattern: check if already notified this block
        // solhint-disable-next-line gas-strict-inequalities
        if (block.number <= targetData.lastChangeNotifiedBlock) return true;

        // Effect: update the notification block before external calls
        targetData.lastChangeNotifiedBlock = block.number;

        // Interactions: make external call after state changes
        // This will revert if the target's notification fails
        IIssuanceTarget(target).beforeIssuanceAllocationChange();
        return true;
    }

    /**
     * @notice Notify all targets (used prior to an allocation or rate change)
     * @dev Each target is notified at most once per block.
     * Will revert if any target notification reverts.
     */
    function notifyAllTargets() private {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        for (uint256 i = 0; i < $.targetAddresses.length; ++i) {
            _notifyTarget($.targetAddresses[i]);
        }
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Implementation details:
     * - The target will be notified at most once per block to prevent reentrancy looping
     * - Will revert if target notification reverts
     */
    function notifyTarget(address target) external onlyRole(GOVERNOR_ROLE) returns (bool) {
        return _notifyTarget(target);
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Implementation details:
     * - This can be used to enable notification to be sent again (by setting to a past block) or to prevent notification until a future block (by setting to current or future block)
     * - Returns the block number that was set, always equal to blockNumber in current implementation
     */
    function forceTargetNoChangeNotificationBlock(
        address target,
        uint256 blockNumber
    ) external override onlyRole(GOVERNOR_ROLE) returns (uint256) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[target];

        // Note: No bounds checking on blockNumber is intentional. Governance might need to set
        // very high values in unanticipated edge cases or for recovery scenarios. Constraining
        // governance flexibility is deemed unnecessary and perhaps counterproductive.
        targetData.lastChangeNotifiedBlock = blockNumber;
        return blockNumber;
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Delegates to _setTargetAllocation with selfMintingPPM=0 and evenIfDistributionPending=false
     */
    function setTargetAllocation(
        address target,
        uint256 allocatorMintingPPM
    ) external override onlyRole(GOVERNOR_ROLE) returns (bool) {
        return _setTargetAllocation(target, allocatorMintingPPM, 0, false);
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Delegates to _setTargetAllocation with evenIfDistributionPending=false
     */
    function setTargetAllocation(
        address target,
        uint256 allocatorMintingPPM,
        uint256 selfMintingPPM
    ) external override onlyRole(GOVERNOR_ROLE) returns (bool) {
        return _setTargetAllocation(target, allocatorMintingPPM, selfMintingPPM, false);
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Implementation details:
     * - If the new allocations are the same as the current allocations, this function is a no-op
     * - If both allocations are 0 and the target doesn't exist, this function is a no-op
     * - If both allocations are 0 and the target exists, the target will be removed
     * - If any allocation is non-zero and the target doesn't exist, the target will be added
     * - Will revert if the total allocation would exceed PPM, or if attempting to add a target that doesn't support IIssuanceTarget
     *
     * Self-minting allocation is a special case for backwards compatibility with
     * existing contracts like the RewardsManager. The IssuanceAllocator calculates
     * issuance for self-minting portions but does not mint tokens directly for them. Self-minting targets
     * should call getTargetIssuancePerBlock to determine their issuance amount and mint
     * tokens accordingly. For example, the RewardsManager contract is expected to call
     * getTargetIssuancePerBlock in its takeRewards function to calculate the correct
     * amount of tokens to mint. Self-minting targets are responsible for adhering to
     * the issuance schedule and should not mint more tokens than allocated.
     */
    function setTargetAllocation(
        address target,
        uint256 allocatorMintingPPM,
        uint256 selfMintingPPM,
        bool evenIfDistributionPending
    ) external override onlyRole(GOVERNOR_ROLE) returns (bool) {
        return _setTargetAllocation(target, allocatorMintingPPM, selfMintingPPM, evenIfDistributionPending);
    }

    /**
     * @notice Internal implementation for setting target allocation
     * @param target Address of the target to update
     * @param allocatorMintingPPM Allocator-minting allocation for the target (in PPM)
     * @param selfMintingPPM Self-minting allocation for the target (in PPM)
     * @param evenIfDistributionPending Whether to force the allocation change even if issuance distribution is behind
     * @return True if the value is applied (including if already the case), false if not applied due to paused state
     */
    function _setTargetAllocation(
        address target,
        uint256 allocatorMintingPPM,
        uint256 selfMintingPPM,
        bool evenIfDistributionPending
    ) internal returns (bool) {
        if (!_validateTargetAllocation(target, allocatorMintingPPM, selfMintingPPM)) return true; // No change needed

        if (!_handleDistributionBeforeAllocation(target, selfMintingPPM, evenIfDistributionPending)) return false; // Distribution pending and not forced

        _notifyTarget(target);

        _validateAndUpdateTotalAllocations(target, allocatorMintingPPM, selfMintingPPM);

        _updateTargetAllocationData(target, allocatorMintingPPM, selfMintingPPM);

        emit TargetAllocationUpdated(target, allocatorMintingPPM, selfMintingPPM);
        return true;
    }

    /**
     * @notice Validates target address and interface support, returns false if allocation is unchanged
     * @param target Address of the target to validate
     * @param allocatorMintingPPM Allocator-minting allocation for the target (in PPM)
     * @param selfMintingPPM Self-minting allocation for the target (in PPM)
     * @return True if validation passes and allocation change is needed, false if allocation is already set to these values
     */
    function _validateTargetAllocation(
        address target,
        uint256 allocatorMintingPPM,
        uint256 selfMintingPPM
    ) private view returns (bool) {
        require(target != address(0), TargetAddressCannotBeZero());

        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[target];

        if (targetData.allocatorMintingPPM == allocatorMintingPPM && targetData.selfMintingPPM == selfMintingPPM)
            return false; // No change needed

        if (allocatorMintingPPM != 0 || selfMintingPPM != 0)
            require(
                IERC165(target).supportsInterface(type(IIssuanceTarget).interfaceId),
                TargetDoesNotSupportIIssuanceTarget()
            );

        return true;
    }

    /**
     * @notice Distributes current issuance and handles accumulation for self-minting changes
     * @param target Address of the target being updated
     * @param selfMintingPPM New self-minting allocation for the target (in PPM)
     * @param evenIfDistributionPending Whether to force the allocation change even if issuance distribution is behind
     * @return True if allocation change should proceed, false if distribution is behind and not forced
     */
    function _handleDistributionBeforeAllocation(
        address target,
        uint256 selfMintingPPM,
        bool evenIfDistributionPending
    ) private returns (bool) {
        if (_distributeIssuance() < block.number) {
            if (!evenIfDistributionPending) return false;

            // A change in self-minting allocation changes the accumulation rate for pending allocator-minting.
            // So for a self-minting change, accumulate pending issuance prior to the rate change.
            IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
            AllocationTarget storage targetData = $.allocationTargets[target];
            if (selfMintingPPM != targetData.selfMintingPPM) accumulatePendingIssuance();
        }

        return true;
    }

    /**
     * @notice Updates global allocation totals and validates they don't exceed maximum
     * @param target Address of the target being updated
     * @param allocatorMintingPPM New allocator-minting allocation for the target (in PPM)
     * @param selfMintingPPM New self-minting allocation for the target (in PPM)
     */
    function _validateAndUpdateTotalAllocations(
        address target,
        uint256 allocatorMintingPPM,
        uint256 selfMintingPPM
    ) private {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[target];

        // Total allocation calculation and check is delayed until after notifications.
        // Distributing and notifying unecessarily is harmless, but we need to prevent
        // reentrancy looping changing allocations mid-calculation.
        // (Would not be likely to be exploitable due to only governor being able to
        // make a call to set target allocation, but better to be paranoid.)
        $.totalAllocatorMintingPPM = $.totalAllocatorMintingPPM - targetData.allocatorMintingPPM + allocatorMintingPPM;
        $.totalSelfMintingPPM = $.totalSelfMintingPPM - targetData.selfMintingPPM + selfMintingPPM;

        // Ensure the new total allocation doesn't exceed MILLION as in PPM.
        // solhint-disable-next-line gas-strict-inequalities
        require(($.totalAllocatorMintingPPM + $.totalSelfMintingPPM) <= MILLION, InsufficientAllocationAvailable());
    }

    /**
     * @notice Sets target allocation values and adds/removes target from active list
     * @param target Address of the target being updated
     * @param allocatorMintingPPM New allocator-minting allocation for the target (in PPM)
     * @param selfMintingPPM New self-minting allocation for the target (in PPM)
     */
    function _updateTargetAllocationData(address target, uint256 allocatorMintingPPM, uint256 selfMintingPPM) private {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[target];

        // Internal design invariants:
        // - targetAddresses contains all targets with non-zero allocation.
        // - targetAddresses does not contain targets with zero allocation.
        // - targetAddresses does not contain duplicates.
        // - allocationTargets mapping contains all targets in targetAddresses with a non-zero allocation.
        // - allocationTargets mapping allocations are zero for targets not in targetAddresses.
        // - Governance actions can create allocationTarget mappings with lastChangeNotifiedBlock set for targets not in targetAddresses. This is valid.
        // Therefore:
        // - Only add a target to the list if it previously had no allocation.
        // - Remove a target from the list when setting both allocations to 0.
        // - Delete allocationTargets mapping entry when removing a target from targetAddresses.
        // - Do not set lastChangeNotifiedBlock in this function.
        if (allocatorMintingPPM != 0 || selfMintingPPM != 0) {
            // Add to list if previously had no allocation
            if (targetData.allocatorMintingPPM == 0 && targetData.selfMintingPPM == 0) $.targetAddresses.push(target);

            targetData.allocatorMintingPPM = allocatorMintingPPM;
            targetData.selfMintingPPM = selfMintingPPM;
        } else {
            // Remove from list and delete mapping
            _removeTargetFromList(target);
            delete $.allocationTargets[target];
        }
    }

    /**
     * @notice Removes target from targetAddresses array using swap-and-pop for gas efficiency
     * @param target Address of the target to remove
     */
    function _removeTargetFromList(address target) private {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        for (uint256 i = 0; i < $.targetAddresses.length; ++i) {
            if ($.targetAddresses[i] == target) {
                $.targetAddresses[i] = $.targetAddresses[$.targetAddresses.length - 1];
                $.targetAddresses.pop();
                break;
            }
        }
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Implementation details:
     * - This function can only be called by Governor role
     * - Distributes pending issuance that has accumulated while paused
     * - This function can be called even when the contract is paused to perform interim distributions
     * - If there is no pending issuance, this function is a no-op
     * - If allocatorMintingAllowance is 0 (all targets are self-minting), pending issuance will be lost
     */
    function distributePendingIssuance() external onlyRole(GOVERNOR_ROLE) returns (uint256) {
        return _distributePendingIssuance();
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Implementation details:
     * - This function can only be called by Governor role
     * - Accumulates pending issuance up to the specified block, then distributes all accumulated issuance
     * - This function can be called even when the contract is paused
     * - If allocatorMintingAllowance is 0 (all targets are self-minting), pending issuance will be lost
     */
    function distributePendingIssuance(uint256 toBlockNumber) external onlyRole(GOVERNOR_ROLE) returns (uint256) {
        accumulatePendingIssuance(toBlockNumber);
        return _distributePendingIssuance();
    }

    /**
     * @notice Distributes any pending accumulated issuance
     * @dev Called from _distributeIssuance to handle accumulated issuance from pause periods.
     * @return Block number up to which issuance has been distributed
     */
    function _distributePendingIssuance() private returns (uint256) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        uint256 pendingAmount = $.pendingAccumulatedAllocatorIssuance;
        $.lastDistributionBlock = $.lastAccumulationBlock;

        if (pendingAmount == 0) return $.lastDistributionBlock;
        $.pendingAccumulatedAllocatorIssuance = 0;

        if ($.totalAllocatorMintingPPM == 0) return $.lastDistributionBlock;

        for (uint256 i = 0; i < $.targetAddresses.length; ++i) {
            address target = $.targetAddresses[i];
            AllocationTarget storage targetData = $.allocationTargets[target];

            if (0 < targetData.allocatorMintingPPM) {
                // There can be a small rounding loss here. This is acceptable.
                // Pending issuance is distributed in proportion to allocator-minting portion of total available allocation.
                uint256 targetIssuance = (pendingAmount * targetData.allocatorMintingPPM) /
                    (MILLION - $.totalSelfMintingPPM);
                GRAPH_TOKEN.mint(target, targetIssuance);
                emit IssuanceDistributed(target, targetIssuance);
            }
        }

        return $.lastDistributionBlock;
    }

    /**
     * @notice Accumulates pending issuance for allocator-minting targets to the current block
     * @dev Used to accumulate pending issuance while paused prior to a rate or allocator-minting allocation change.
     * @return The block number that has been accumulated to
     */
    function accumulatePendingIssuance() private returns (uint256) {
        return accumulatePendingIssuance(block.number);
    }

    /**
     * @notice Accumulates pending issuance for allocator-minting targets during pause periods
     * @dev Accumulates pending issuance for allocator-minting targets during pause periods.
     * @param toBlockNumber The block number to accumulate to (must be >= lastIssuanceAccumulationBlock and <= current block).
     * @return The block number that has been accumulated to
     */
    function accumulatePendingIssuance(uint256 toBlockNumber) private returns (uint256) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        // solhint-disable-next-line gas-strict-inequalities
        require($.lastAccumulationBlock <= toBlockNumber && toBlockNumber <= block.number, ToBlockOutOfRange());

        uint256 blocksToAccumulate = toBlockNumber - $.lastAccumulationBlock;
        if (0 < blocksToAccumulate) {
            uint256 totalIssuance = $.issuancePerBlock * blocksToAccumulate;
            // There can be a small rounding loss here. This is acceptable.
            $.pendingAccumulatedAllocatorIssuance += (totalIssuance * (MILLION - $.totalSelfMintingPPM)) / MILLION;
            $.lastAccumulationBlock = toBlockNumber;
        }

        return $.lastAccumulationBlock;
    }

    // -- View Functions --

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function issuancePerBlock() external view override returns (uint256) {
        return _getIssuanceAllocatorStorage().issuancePerBlock;
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function lastIssuanceDistributionBlock() external view override returns (uint256) {
        return _getIssuanceAllocatorStorage().lastDistributionBlock;
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function lastIssuanceAccumulationBlock() external view override returns (uint256) {
        return _getIssuanceAllocatorStorage().lastAccumulationBlock;
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function pendingAccumulatedAllocatorIssuance() external view override returns (uint256) {
        return _getIssuanceAllocatorStorage().pendingAccumulatedAllocatorIssuance;
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function getTargetCount() external view override returns (uint256) {
        return _getIssuanceAllocatorStorage().targetAddresses.length;
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function getTargets() external view override returns (address[] memory) {
        return _getIssuanceAllocatorStorage().targetAddresses;
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function getTargetAt(uint256 index) external view override returns (address) {
        return _getIssuanceAllocatorStorage().targetAddresses[index];
    }

    /**
     * @notice Get target data for a specific target (implementation-specific)
     * @dev This function exposes internal AllocationTarget struct for operator use
     * @param target Address of the target
     * @return AllocationTarget struct containing target information including lastChangeNotifiedBlock
     */
    function getTargetData(address target) external view returns (AllocationTarget memory) {
        return _getIssuanceAllocatorStorage().allocationTargets[target];
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function getTargetAllocation(address target) external view override returns (Allocation memory) {
        AllocationTarget storage targetData = _getIssuanceAllocatorStorage().allocationTargets[target];
        return
            Allocation({
                totalAllocationPPM: targetData.allocatorMintingPPM + targetData.selfMintingPPM,
                allocatorMintingPPM: targetData.allocatorMintingPPM,
                selfMintingPPM: targetData.selfMintingPPM
            });
    }

    /**
     * @inheritdoc IIssuanceAllocationDistribution
     */
    function getTargetIssuancePerBlock(address target) external view override returns (TargetIssuancePerBlock memory) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[target];

        // There can be small losses due to rounding. This is acceptable.
        return
            TargetIssuancePerBlock({
                allocatorIssuancePerBlock: ($.issuancePerBlock * targetData.allocatorMintingPPM) / MILLION,
                allocatorIssuanceBlockAppliedTo: $.lastDistributionBlock,
                selfIssuancePerBlock: ($.issuancePerBlock * targetData.selfMintingPPM) / MILLION,
                selfIssuanceBlockAppliedTo: block.number
            });
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function getTotalAllocation() external view override returns (Allocation memory) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        return
            Allocation({
                totalAllocationPPM: $.totalAllocatorMintingPPM + $.totalSelfMintingPPM,
                allocatorMintingPPM: $.totalAllocatorMintingPPM,
                selfMintingPPM: $.totalSelfMintingPPM
            });
    }
}
