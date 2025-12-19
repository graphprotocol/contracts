// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import {
    TargetIssuancePerBlock,
    Allocation,
    AllocationTarget,
    DistributionState
} from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocatorTypes.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceAllocationAdministration } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationAdministration.sol";
import { IIssuanceAllocationStatus } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationStatus.sol";
import { IIssuanceAllocationData } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationData.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { ReentrancyGuardTransientUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title IssuanceAllocator
 * @author Edge & Node
 * @notice This contract is responsible for allocating token issuance to different components
 * of the protocol. It calculates issuance for all targets based on their configured rates
 * (tokens per block) and handles minting for allocator-minting targets.
 *
 * @dev The contract maintains a 100% allocation invariant through a default target mechanism:
 * - A default target target exists at targetAddresses[0] (initialized to address(0))
 * - The default target automatically receives any unallocated portion of issuance
 * - Total allocation across all targets always equals issuancePerBlock (tracked as absolute rates)
 * - The default target address can be changed via setDefaultAllocationAddress()
 * - When the default address is address(0), this 'unallocated' portion is not minted
 * - Regular targets cannot be set as the default target address
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
 * @dev Pause Behavior:
 * - Allocator-minting: Completely suspended during pause. No tokens minted, lastDistributionBlock frozen.
 *   When unpaused, distributes retroactively using current rates for entire undistributed period. (Distribution will be triggered by calling distributeIssuance() when not paused.)
 * - Self-minting: Continues tracking via events and accumulation during pause. Accumulated self-minting
 *   reduces allocator-minting budget when distribution resumes, ensuring total issuance conservation.
 * - Ongoing accumulation: Once accumulation starts (during pause), continues through any unpaused
 *   periods until distribution clears it, preventing loss of self-minting allowances across pause cycles.
 * - Tracking divergence: lastSelfMintingBlock advances during pause (for allowance tracking) while
 *   lastDistributionBlock stays frozen (no allocator-minting). This is intentional and correct.
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
 *
 * @dev Reentrancy Protection:
 * The contract code is designed to be reentrant-safe and should be carefully reviewed and maintained
 * to preserve this property. However, reentrancy guards (using transient storage per EIP-1153) are
 * applied to governance functions that modify configuration or state as an additional layer of defense.
 * This provides protection against potential issues if the multi-sig governor role were to have known
 * signatures that could be exploited by malicious actors to trigger reentrant calls.
 *
 * The `distributeIssuance()` function intentionally does NOT have a reentrancy guard to allow
 * legitimate use cases where targets call it during notifications (e.g., to claim pending issuance
 * before allocation changes). This is safe because distributeIssuance() has built-in block-tracking
 * protection (preventing double-distribution in the same block), makes no external calls that could
 * expose inconsistent state, and does not modify allocations.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any bugs. We might have an active bug bounty program.
 */
contract IssuanceAllocator is
    BaseUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    IIssuanceAllocationDistribution,
    IIssuanceAllocationAdministration,
    IIssuanceAllocationStatus,
    IIssuanceAllocationData
{
    // -- Namespaced Storage --

    /// @notice ERC-7201 storage location for IssuanceAllocator
    bytes32 private constant ISSUANCE_ALLOCATOR_STORAGE_LOCATION =
        // solhint-disable-next-line gas-small-strings
        keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.IssuanceAllocator")) - 1)) &
            ~bytes32(uint256(0xff));

    /// @notice Main storage structure for IssuanceAllocator using ERC-7201 namespaced storage
    /// @param issuancePerBlock Total issuance per block across all targets
    /// @param lastDistributionBlock Last block when allocator-minting issuance was distributed
    /// @param lastSelfMintingBlock Last block when self-minting was advanced
    /// @param selfMintingOffset Self-minting that offsets allocator-minting budget (accumulates during pause, clears on distribution)
    /// @param allocationTargets Mapping of target addresses to their allocation data
    /// @param targetAddresses Array of all target addresses (including default target at index 0)
    /// @param totalSelfMintingRate Total self-minting rate (tokens per block) across all targets
    /// @dev Design invariant: totalAllocatorRate + totalSelfMintingRate == issuancePerBlock (always 100% allocated)
    /// @dev Design invariant: targetAddresses[0] is always the default target address
    /// @dev Design invariant: 1 <= targetAddresses.length (default target always exists)
    /// @dev Design invariant: default target (targetAddresses[0]) is automatically adjusted to maintain 100% total
    /// @custom:storage-location erc7201:graphprotocol.storage.IssuanceAllocator
    struct IssuanceAllocatorData {
        uint256 issuancePerBlock;
        uint256 lastDistributionBlock;
        uint256 lastSelfMintingBlock;
        uint256 selfMintingOffset;
        mapping(address => AllocationTarget) allocationTargets;
        address[] targetAddresses;
        uint256 totalSelfMintingRate;
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

    /// @notice Thrown when the total allocation would exceed available budget
    /// @param requested The total requested allocation (allocator + self minting)
    /// @param available The available budget for this target
    error InsufficientAllocationAvailable(uint256 requested, uint256 available);

    /// @notice Thrown when attempting to decrease issuance rate without sufficient unallocated budget
    /// @param oldRate The current issuance rate
    /// @param newRate The proposed new issuance rate
    /// @param unallocated The unallocated budget available to absorb the decrease
    error InsufficientUnallocatedForRateDecrease(uint256 oldRate, uint256 newRate, uint256 unallocated);

    /// @notice Thrown when a target does not support the IIssuanceTarget interface
    /// @param target The target address that doesn't support the interface
    error TargetDoesNotSupportIIssuanceTarget(address target);

    /// @notice Thrown when toBlockNumber is out of valid range for accumulation
    /// @param toBlock The invalid block number provided
    /// @param minBlock The minimum valid block number (lastDistributionBlock)
    /// @param maxBlock The maximum valid block number (current block)
    error ToBlockOutOfRange(uint256 toBlock, uint256 minBlock, uint256 maxBlock);

    /// @notice Thrown when attempting to set allocation for the default target target
    /// @param defaultTarget The address of the default target
    error CannotSetAllocationForDefaultTarget(address defaultTarget);

    /// @notice Thrown when attempting to set default target address to a normally allocated target
    /// @param target The target address that already has an allocation
    error CannotSetDefaultToAllocatedTarget(address target);

    // -- Events --

    /// @notice Emitted when issuance is distributed to a target
    /// @param target The address of the target that received issuance
    /// @param amount The amount of tokens distributed
    /// @param fromBlock First block included in this distribution (inclusive)
    /// @param toBlock Last block included in this distribution (inclusive). Range is [fromBlock, toBlock]
    event IssuanceDistributed(
        address indexed target,
        uint256 amount,
        uint256 indexed fromBlock,
        uint256 indexed toBlock
    ); // solhint-disable-line gas-indexed-events

    /// @notice Emitted when a target's allocation is updated
    /// @param target The address of the target whose allocation was updated
    /// @param newAllocatorMintingRate The new allocator-minting rate (tokens per block) for the target
    /// @param newSelfMintingRate The new self-minting rate (tokens per block) for the target
    event TargetAllocationUpdated(address indexed target, uint256 newAllocatorMintingRate, uint256 newSelfMintingRate); // solhint-disable-line gas-indexed-events
    // Do not need to index rate values

    /// @notice Emitted when the issuance per block is updated
    /// @param oldIssuancePerBlock The previous issuance per block amount
    /// @param newIssuancePerBlock The new issuance per block amount
    event IssuancePerBlockUpdated(uint256 oldIssuancePerBlock, uint256 newIssuancePerBlock); // solhint-disable-line gas-indexed-events
    // Do not need to index issuance per block values

    /// @notice Emitted when the default target is updated
    /// @param oldAddress The previous default target address
    /// @param newAddress The new default target address
    event DefaultTargetUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when self-minting allowance is calculated for a target
    /// @param target The address of the target with self-minting allocation
    /// @param amount The amount of tokens available for self-minting
    /// @param fromBlock First block included in this allowance period (inclusive)
    /// @param toBlock Last block included in this allowance period (inclusive). Range is [fromBlock, toBlock]
    event IssuanceSelfMintAllowance(
        address indexed target,
        uint256 amount,
        uint256 indexed fromBlock,
        uint256 indexed toBlock
    ); // solhint-disable-line gas-indexed-events

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
     * @dev Initializes with a default target at index 0 set to address(0)
     * @dev default target will receive all unallocated issuance (initially 0 until rate is set)
     * @dev Initialization: lastDistributionBlock is set to block.number as a safety guard against
     * pausing before configuration. lastSelfMintingBlock defaults to 0. issuancePerBlock is 0.
     * Once setIssuancePerBlock() is called, it triggers _distributeIssuance() which updates
     * lastDistributionBlock to current block, establishing the starting point for issuance tracking.
     * @dev Rate changes while paused: Rate changes are stored but distributeIssuance() will NOT
     * apply them while paused - it returns immediately with frozen lastDistributionBlock. When
     * distribution eventually resumes (via unpause or manual distributePendingIssuance()), the
     * CURRENT rates at that time are applied retroactively to the entire undistributed period.
     * Governance must exercise caution when changing rates while paused to ensure they are applied
     * to the correct block range. See setIssuancePerBlock() documentation for details.
     */
    function initialize(address _governor) external virtual initializer {
        __BaseUpgradeable_init(_governor);
        __ReentrancyGuardTransient_init();

        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        // Initialize default target at index 0 with address(0)
        // Rates are 0 initially; default gets remainder when issuancePerBlock is set
        $.targetAddresses.push(address(0));

        // To guard against extreme edge case of pausing before setting issuancePerBlock, we initialize
        // lastDistributionBlock to block.number. This should be updated to the correct starting block
        // during configuration by governance.
        $.lastDistributionBlock = block.number;
    }

    // -- Core Functionality --

    /**
     * @inheritdoc ERC165Upgradeable
     * @dev Supports the four IssuanceAllocator sub-interfaces
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IIssuanceAllocationDistribution).interfaceId ||
            interfaceId == type(IIssuanceAllocationAdministration).interfaceId ||
            interfaceId == type(IIssuanceAllocationStatus).interfaceId ||
            interfaceId == type(IIssuanceAllocationData).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @inheritdoc IIssuanceAllocationDistribution
     * @dev Implementation details:
     * - For allocator-minting targets, tokens are minted and transferred directly to targets based on their allocation rate
     * - For self-minting targets (like the legacy RewardsManager), it does not mint tokens directly. Instead, these contracts are expected to handle minting themselves
     * - The self-minting allocation is intended only for backwards compatibility with existing contracts and should not be used for new targets. New targets should use allocator-minting allocation to ensure robust control of token issuance by the IssuanceAllocator
     * @dev Pause behavior:
     * - When paused: Self-minting allowances tracked via events/accumulation, but no allocator-minting tokens distributed.
     *   Returns lastDistributionBlock (frozen at pause point). lastSelfMintingBlock advances to current block.
     * - When unpaused: Normal distribution if no accumulated self-minting, otherwise retroactive distribution
     *   using current rates for entire undistributed period, with accumulated self-minting reducing allocator budget.
     * - Unless paused, always advances lastDistributionBlock to block.number, even if no issuance to distribute.
     * @dev Reentrancy: This function intentionally does NOT have a reentrancy guard to allow targets to
     * legitimately call it during notifications (e.g., to claim pending issuance before their allocation changes).
     * This is safe because the function has built-in block-tracking protection that prevents double-distribution
     * within the same block, makes no external calls that could expose inconsistent state, and does not modify allocations.
     */
    function distributeIssuance() external override returns (uint256) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        // Optimize common case: if already distributed this block, return immediately (~60% gas savings).
        // Multiple targets may call this in the same block; first call distributes, rest are no-ops.
        return $.lastDistributionBlock == block.number ? block.number : _distributeIssuance();
    }

    /**
     * @notice Advances self-minting block and emits allowance events
     * @dev When paused, accumulates self-minting amounts. This accumulation reduces the allocator-minting
     * budget when distribution resumes, ensuring total issuance stays within bounds.
     * When not paused, just emits self-minting allowance events.
     * Called by _distributeIssuance() which anyone can call.
     * Optimized for no-op cases: very cheap when already at current block.
     */
    function _advanceSelfMintingBlock() private {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        uint256 previousBlock = $.lastSelfMintingBlock;
        if (previousBlock == block.number) return;

        uint256 blocks = block.number - previousBlock;

        // Accumulate if currently paused OR if there's existing accumulated balance.
        // Once accumulation starts (during pause), continue through any unpaused periods
        // until distribution clears the accumulation. This is conservative and allows
        // better recovery when distribution is delayed through pause/unpause cycles.
        if (paused() || 0 < $.selfMintingOffset) $.selfMintingOffset += $.totalSelfMintingRate * blocks;
        $.lastSelfMintingBlock = block.number;
        uint256 fromBlock = previousBlock + 1;

        // Emit self-minting allowance events
        if (0 < $.totalSelfMintingRate) {
            for (uint256 i = 0; i < $.targetAddresses.length; ++i) {
                address target = $.targetAddresses[i];
                AllocationTarget storage targetData = $.allocationTargets[target];

                if (0 < targetData.selfMintingRate) {
                    uint256 amount = targetData.selfMintingRate * blocks;
                    emit IssuanceSelfMintAllowance(target, amount, fromBlock, block.number);
                }
            }
        }
    }

    /**
     * @notice Internal implementation for `distributeIssuance`
     * @dev Handles the actual distribution logic.
     * @dev Always calls _advanceSelfMintingBlock() first (advances lastSelfMintingBlock, tracks self-minting).
     * @dev If paused: Returns lastDistributionBlock without distributing allocator-minting (frozen state).
     * @dev If unpaused: Chooses distribution path based on accumulated self-minting:
     *      - With accumulation: retroactive distribution path (current rates, reduced allocator budget)
     *      - Without accumulation: normal distribution path (simple per-block minting)
     * @return Block number distributed to
     */
    function _distributeIssuance() private returns (uint256) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        _advanceSelfMintingBlock();

        if (paused()) return $.lastDistributionBlock;

        return 0 < $.selfMintingOffset ? _distributePendingIssuance(block.number) : _performNormalDistribution();
    }

    /**
     * @notice Performs normal (non-pending) issuance distribution
     * @dev Distributes allocator-minting issuance to all targets based on their rates
     * @dev Assumes contract is not paused and pending issuance has already been distributed
     * @return Block number distributed to
     */
    function _performNormalDistribution() private returns (uint256) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        uint256 blocks = block.number - $.lastDistributionBlock;
        if (blocks == 0) return $.lastDistributionBlock;

        uint256 fromBlock = $.lastDistributionBlock + 1;

        for (uint256 i = 0; i < $.targetAddresses.length; ++i) {
            address target = $.targetAddresses[i];
            if (target == address(0)) continue;

            AllocationTarget storage targetData = $.allocationTargets[target];
            if (0 < targetData.allocatorMintingRate) {
                uint256 amount = targetData.allocatorMintingRate * blocks;
                GRAPH_TOKEN.mint(target, amount);
                emit IssuanceDistributed(target, amount, fromBlock, block.number);
            }
        }

        $.lastDistributionBlock = block.number;
        return block.number;
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     */
    function distributePendingIssuance() external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (uint256) {
        return _distributePendingIssuance(block.number);
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     */
    function distributePendingIssuance(
        uint256 toBlockNumber
    ) external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (uint256) {
        return _distributePendingIssuance(toBlockNumber);
    }

    /**
     * @notice Internal implementation for distributing pending accumulated allocator-minting issuance
     * @param toBlockNumber Block number to distribute up to
     * @dev Distributes allocator-minting issuance for undistributed period using current rates
     * (retroactively applied to from lastDistributionBlock to toBlockNumber, inclusive of both endpoints).
     * @dev Called when 0 < self-minting offset, which occurs after pause periods or when
     * distribution is delayed across pause/unpause cycles. Conservative accumulation strategy
     * continues accumulating through unpaused periods until distribution clears it.
     * The undistributed period (lastDistributionBlock to toBlockNumber) could theoretically span multiple pause/unpause cycles. In practice this is unlikely if there are active targets that call distributeIssuance().
     * @dev Current rate is always applied retroactively to undistributed period, to the extent possible given the accumulated self-minting offset.
     * If any interim rate was higher than current rate, there might be insufficient allocation
     * to satisfy required allocations. In this case, we make the best match to honour the current rate.
     * There will never more issuance relative to what the max interim issuance rate was, but in some circumstances the current rate is insufficient to satisfy the accumulated self-minting. In other cases, to satisfy the current rate, we distribute proportionally less to non-default targets than their current allocation rate.
     * @dev Constraint: cannot distribute more than total issuance for the period.
     * @dev Shortfall: When accumulated self-minting exceeds what current rate allows for the period,
     * the total issuance already exceeded current rate expectations. No allocator-minting distributed.
     * @dev When allocator-minting is available, there are two distribution cases:
     * (1) available < allowance: proportional distribution among non-default, default gets zero
     * (2) allowance <= available: full rates to non-default, remainder to default
     * Where allowance is allocator rate (for non-default targets) * blocks, and available is total issuance for period minus accumulated self-minting.
     * @return Block number that issuance was distributed up to
     */
    function _distributePendingIssuance(uint256 toBlockNumber) private returns (uint256) {
        _advanceSelfMintingBlock();
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        require(
            $.lastDistributionBlock <= toBlockNumber && toBlockNumber <= block.number, // solhint-disable-line gas-strict-inequalities
            ToBlockOutOfRange(toBlockNumber, $.lastDistributionBlock, block.number)
        );

        uint256 blocks = toBlockNumber - $.lastDistributionBlock;
        if (blocks == 0) return toBlockNumber;

        // Overflow is not possible with reasonable parameters. For example, with issuancePerBlock
        // at 1e24 (1 million GRT with 18 decimals) and blocks at 1e9 (hundreds of years), the product is
        // ~1e33, well below uint256 max (~1e77). Similar multiplications throughout this contract operate
        // under the same range assumptions.
        uint256 totalForPeriod = $.issuancePerBlock * blocks;
        uint256 selfMintingOffset = $.selfMintingOffset;

        uint256 available = selfMintingOffset < totalForPeriod ? totalForPeriod - selfMintingOffset : 0;

        if (0 < available) {
            // Calculate non-default allocated rate using the allocation invariant.
            // Since totalAllocatorRate + totalSelfMintingRate == issuancePerBlock (100% invariant),
            // and default target is part of totalAllocatorRate, we can derive:
            // allocatedRate = issuancePerBlock - totalSelfMintingRate - defaultAllocatorRate
            address defaultAddress = $.targetAddresses[0];
            AllocationTarget storage defaultTarget = $.allocationTargets[defaultAddress];
            uint256 allocatedRate = $.issuancePerBlock - $.totalSelfMintingRate - defaultTarget.allocatorMintingRate;

            uint256 allocatedTotal = allocatedRate * blocks;

            if (available < allocatedTotal) _distributePendingProportionally(available, allocatedRate, toBlockNumber);
            else _distributePendingWithFullRate(blocks, available, allocatedTotal, toBlockNumber);
        }

        $.lastDistributionBlock = toBlockNumber;

        // Update accumulated self-minting after distribution.
        // Subtract the period budget used (min of accumulated and totalForPeriod).
        // When caught up to current block, clear all since nothing remains to distribute.
        if (toBlockNumber == block.number) $.selfMintingOffset = 0;
        else $.selfMintingOffset = totalForPeriod < selfMintingOffset ? selfMintingOffset - totalForPeriod : 0;

        return toBlockNumber;
    }

    /**
     * @notice Distribute pending issuance with full rates to non-default targets
     * @param blocks Number of blocks in the distribution period
     * @param available Total available allocator-minting budget for the period
     * @param allocatedTotal Total amount allocated to non-default targets at full rate
     * @param toBlockNumber Block number distributing to
     * @dev Sufficient budget: non-default targets get full rates, default gets remainder
     */
    function _distributePendingWithFullRate(
        uint256 blocks,
        uint256 available,
        uint256 allocatedTotal,
        uint256 toBlockNumber
    ) internal {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        uint256 fromBlock = $.lastDistributionBlock + 1;

        // Give non-default targets their full rates
        for (uint256 i = 1; i < $.targetAddresses.length; ++i) {
            address target = $.targetAddresses[i];
            AllocationTarget storage targetData = $.allocationTargets[target];

            if (0 < targetData.allocatorMintingRate) {
                uint256 amount = targetData.allocatorMintingRate * blocks;
                GRAPH_TOKEN.mint(target, amount);
                emit IssuanceDistributed(target, amount, fromBlock, toBlockNumber);
            }
        }

        // Default target gets remainder (may be 0 if exactly matched)
        uint256 remainingForDefault = available - allocatedTotal;
        if (0 < remainingForDefault) {
            address defaultAddress = $.targetAddresses[0];
            if (defaultAddress != address(0)) {
                GRAPH_TOKEN.mint(defaultAddress, remainingForDefault);
                emit IssuanceDistributed(defaultAddress, remainingForDefault, fromBlock, toBlockNumber);
            }
        }
    }

    /**
     * @notice Distribute pending issuance proportionally among non-default targets
     * @param available Total available allocator-minting budget for the period
     * @param allocatedRate Total rate allocated to non-default targets
     * @param toBlockNumber Block number distributing to
     * @dev Insufficient budget: non-default targets get proportional shares, default gets zero
     * @dev Proportional distribution may result in rounding loss (dust), which is acceptable
     */
    function _distributePendingProportionally(
        uint256 available,
        uint256 allocatedRate,
        uint256 toBlockNumber
    ) internal {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        // Defensive: prevent division by zero and handle edge cases. Should not be reachable based on
        // caller logic (only called when available < allocatedTotal and both available > 0, blocks > 0).
        if (allocatedRate == 0 || available == 0) return;

        uint256 fromBlock = $.lastDistributionBlock + 1;

        // Non-default targets get proportional shares (reduced amounts)
        // Default is excluded (receives zero)
        for (uint256 i = 1; i < $.targetAddresses.length; ++i) {
            address target = $.targetAddresses[i];
            AllocationTarget storage targetData = $.allocationTargets[target];

            if (0 < targetData.allocatorMintingRate) {
                // Proportional distribution using integer division causes rounding loss.
                // Since Solidity division always floors (truncates toward zero), this can ONLY lose tokens,
                // never over-distribute. The lost tokens (dust) remain unallocated.
                // This is acceptable because:
                // 1. The amount is negligible (< number of targets)
                // 2. It maintains safety (never over-mint)
                // 3. Alternative of tracking and distributing dust adds complexity without significant benefit
                uint256 amount = (available * targetData.allocatorMintingRate) / allocatedRate;
                GRAPH_TOKEN.mint(target, amount);
                emit IssuanceDistributed(target, amount, fromBlock, toBlockNumber);
            }
        }
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     */
    function setIssuancePerBlock(
        uint256 newIssuancePerBlock
    ) external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (bool) {
        return _setIssuancePerBlock(newIssuancePerBlock, block.number);
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Implementation details:
     * - Requires distribution to have reached at least minDistributedBlock
     * - This allows configuration changes after calling distributePendingIssuance(blockNumber) while paused
     * - Only the default target is notified (target rates don't change, only default target changes)
     * - Target rates stay fixed; default target absorbs the change
     * - Whenever the rate is changed, the updateL2MintAllowance function _must_ be called on the L1GraphTokenGateway in L1, to ensure the bridge can mint the right amount of tokens
     */
    function setIssuancePerBlock(
        uint256 newIssuancePerBlock,
        uint256 minDistributedBlock
    ) external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (bool) {
        return _setIssuancePerBlock(newIssuancePerBlock, minDistributedBlock);
    }

    /**
     * @notice Internal implementation for setting issuance per block
     * @param newIssuancePerBlock New issuance per block
     * @param minDistributedBlock Minimum block number that distribution must have reached
     * @return True if the value is applied
     */
    function _setIssuancePerBlock(uint256 newIssuancePerBlock, uint256 minDistributedBlock) private returns (bool) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        uint256 oldIssuancePerBlock = $.issuancePerBlock;
        if (newIssuancePerBlock == oldIssuancePerBlock) return true;

        if (_distributeIssuance() < minDistributedBlock) return false;

        _notifyTarget($.targetAddresses[0]);

        AllocationTarget storage defaultTarget = $.allocationTargets[$.targetAddresses[0]];
        uint256 unallocated = defaultTarget.allocatorMintingRate;

        require(
            oldIssuancePerBlock <= newIssuancePerBlock + unallocated, // solhint-disable-line gas-strict-inequalities
            InsufficientUnallocatedForRateDecrease(oldIssuancePerBlock, newIssuancePerBlock, unallocated)
        );

        defaultTarget.allocatorMintingRate = unallocated + newIssuancePerBlock - oldIssuancePerBlock;
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
     * @return True if notification was sent or already sent for this block. Always returns true for address(0) without notifying.
     */
    function _notifyTarget(address target) private returns (bool) {
        // Skip notification for zero address (default target when unset)
        if (target == address(0)) return true;

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
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Implementation details:
     * - The target will be notified at most once per block to prevent reentrancy looping
     * - Will revert if target notification reverts
     */
    function notifyTarget(address target) external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (bool) {
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
     */
    function setTargetAllocation(
        IIssuanceTarget target,
        uint256 allocatorMintingRate
    ) external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (bool) {
        return _setTargetAllocation(address(target), allocatorMintingRate, 0, block.number);
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     */
    function setTargetAllocation(
        IIssuanceTarget target,
        uint256 allocatorMintingRate,
        uint256 selfMintingRate
    ) external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (bool) {
        return _setTargetAllocation(address(target), allocatorMintingRate, selfMintingRate, block.number);
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     * @dev Implementation details:
     * - Requires distribution has reached at least minDistributedBlock issuance to change allocation
     * - This allows configuration changes while paused by being deliberate about which block to distribute to
     * - If the new allocations are the same as the current allocations, this function is a no-op
     * - If both allocations are 0 and the target doesn't exist, this function is a no-op
     * - If both allocations are 0 and the target exists, the target will be removed
     * - If any allocation is non-zero and the target doesn't exist, the target will be added
     * - Will revert if the total allocation would exceed available capacity (default target + current target allocation)
     * - Will revert if attempting to add a target that doesn't support IIssuanceTarget
     *
     * Self-minting allocation is a special case for backwards compatibility with
     * existing contracts like the RewardsManager. The IssuanceAllocator calculates
     * issuance for self-minting targets but does not mint tokens directly for them. Self-minting targets
     * should call getTargetIssuancePerBlock to determine their issuance amount and mint
     * tokens accordingly. For example, the RewardsManager contract is expected to call
     * getTargetIssuancePerBlock in its takeRewards function to calculate the correct
     * amount of tokens to mint. Self-minting targets are responsible for adhering to
     * the issuance schedule and should not mint more tokens than allocated.
     */
    function setTargetAllocation(
        IIssuanceTarget target,
        uint256 allocatorMintingRate,
        uint256 selfMintingRate,
        uint256 minDistributedBlock
    ) external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (bool) {
        return _setTargetAllocation(address(target), allocatorMintingRate, selfMintingRate, minDistributedBlock);
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     */
    function setDefaultTarget(
        address newAddress
    ) external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (bool) {
        return _setDefaultTarget(newAddress, block.number);
    }

    /**
     * @inheritdoc IIssuanceAllocationAdministration
     */
    function setDefaultTarget(
        address newAddress,
        uint256 minDistributedBlock
    ) external override onlyRole(GOVERNOR_ROLE) nonReentrant returns (bool) {
        return _setDefaultTarget(newAddress, minDistributedBlock);
    }

    /**
     * @notice Internal implementation for setting default target
     * @param newAddress The address to set as the new default target
     * @param minDistributedBlock Minimum block number that distribution must have reached
     * @return True if the value is applied (including if already the case), false if not applied due to paused state
     * @dev The default target automatically receives the portion of issuance not allocated to other targets
     * @dev This maintains the invariant that total allocation always equals issuancePerBlock
     * @dev Reverts if attempting to set to an address that has a normal (non-default) allocation
     * @dev Allocation data is copied from the old default to the new default, including lastChangeNotifiedBlock
     * @dev No-op if setting to the same address
     */
    function _setDefaultTarget(address newAddress, uint256 minDistributedBlock) internal returns (bool) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        address oldAddress = $.targetAddresses[0];
        if (newAddress == oldAddress) return true;

        // Cannot set default target to a normally allocated target
        // Check if newAddress is in targetAddresses (excluding index 0 which is the default)
        // Note: This is O(n) for the number of targets, which could become expensive as targets increase.
        // However, distribution operations already loop through all targets and
        // would encounter gas issues first. Recovery mechanisms exist.
        for (uint256 i = 1; i < $.targetAddresses.length; ++i) {
            require($.targetAddresses[i] != newAddress, CannotSetDefaultToAllocatedTarget(newAddress));
        }

        if (_distributeIssuance() < minDistributedBlock) return false;

        // Notify both old and new addresses of the allocation change
        _notifyTarget(oldAddress);
        _notifyTarget(newAddress);

        // Preserve the notification block of newAddress before copying old address data
        uint256 newAddressNotificationBlock = $.allocationTargets[newAddress].lastChangeNotifiedBlock;

        // Update the default target at index 0
        // This copies allocation data from old to new, including allocatorMintingRate and selfMintingRate
        $.targetAddresses[0] = newAddress;
        $.allocationTargets[newAddress] = $.allocationTargets[oldAddress];
        delete $.allocationTargets[oldAddress];

        // Restore the notification block for newAddress (regard as target-specific, not about default)
        $.allocationTargets[newAddress].lastChangeNotifiedBlock = newAddressNotificationBlock;

        emit DefaultTargetUpdated(oldAddress, newAddress);
        return true;
    }

    /**
     * @notice Internal implementation for setting target allocation
     * @param target Address of the target to update
     * @param allocatorMintingRate Allocator-minting rate for the target (tokens per block)
     * @param selfMintingRate Self-minting rate for the target (tokens per block)
     * @param minDistributedBlock Minimum block number that distribution must have reached
     * @return True if the value is applied (including if already the case), false if not applied due to paused state
     */
    function _setTargetAllocation(
        address target,
        uint256 allocatorMintingRate,
        uint256 selfMintingRate,
        uint256 minDistributedBlock
    ) internal returns (bool) {
        if (!_validateAllocationChange(target, allocatorMintingRate, selfMintingRate)) return true;

        if (_distributeIssuance() < minDistributedBlock) return false;

        _notifyTarget(target);

        // Total allocation calculation and check is delayed until after notifications.
        // Distributing and notifying unnecessarily is harmless, but we need to prevent
        // reentrancy from looping and changing allocations mid-calculation.
        // (Would not be likely to be exploitable due to only governor being able to
        // make a call to set target allocation, but better to be paranoid.)
        // Validate totals and auto-adjust default allocation BEFORE updating target data
        // so we can read the old allocation values
        _validateAndUpdateTotalAllocations(target, allocatorMintingRate, selfMintingRate);

        // Then update the target's allocation data
        _updateTargetAllocationData(target, allocatorMintingRate, selfMintingRate);

        emit TargetAllocationUpdated(target, allocatorMintingRate, selfMintingRate);
        return true;
    }

    /**
     * @notice Validates allocation change for a target
     * @param target Address of the target to validate
     * @param allocatorMintingRate Allocator-minting rate for the target (tokens per block)
     * @param selfMintingRate Self-minting rate for the target (tokens per block)
     * @return True if validation passes and allocation change is needed, false if allocation is already set to these values
     * @dev Reverts if target is address(0), default target, or doesn't support IIssuanceTarget (for non-zero rates)
     */
    function _validateAllocationChange(
        address target,
        uint256 allocatorMintingRate,
        uint256 selfMintingRate
    ) private view returns (bool) {
        require(target != address(0), TargetAddressCannotBeZero());

        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        require(target != $.targetAddresses[0], CannotSetAllocationForDefaultTarget($.targetAddresses[0]));

        AllocationTarget storage targetData = $.allocationTargets[target];

        if (targetData.allocatorMintingRate == allocatorMintingRate && targetData.selfMintingRate == selfMintingRate)
            return false; // No change needed

        if (allocatorMintingRate != 0 || selfMintingRate != 0)
            require(
                IERC165(target).supportsInterface(type(IIssuanceTarget).interfaceId),
                TargetDoesNotSupportIIssuanceTarget(target)
            );

        return true;
    }

    /**
     * @notice Updates global allocation totals and auto-adjusts default target to maintain 100% invariant
     * @param target Address of the target being updated
     * @param allocatorMintingRate New allocator-minting rate for the target (tokens per block)
     * @param selfMintingRate New self-minting rate for the target (tokens per block)
     * @dev The default target (at targetAddresses[0]) is automatically adjusted to ensure total allocation equals issuancePerBlock
     * @dev This function is called BEFORE the target's allocation data has been updated so we can read old values
     */
    function _validateAndUpdateTotalAllocations(
        address target,
        uint256 allocatorMintingRate,
        uint256 selfMintingRate
    ) private {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[target];
        AllocationTarget storage defaultTarget = $.allocationTargets[$.targetAddresses[0]];

        // Calculations occur after notifications in the caller to prevent reentrancy issues

        // availableRate comprises the default target's current allocator-minting rate,
        // the target's current allocator-minting rate, and the target's current self-minting rate.
        // This maintains the 100% allocation invariant by calculating how much can be reallocated
        // to the target without exceeding total available allocation.
        uint256 availableRate = defaultTarget.allocatorMintingRate +
            targetData.allocatorMintingRate +
            targetData.selfMintingRate;
        require(
            allocatorMintingRate + selfMintingRate <= availableRate, // solhint-disable-line gas-strict-inequalities
            InsufficientAllocationAvailable(allocatorMintingRate + selfMintingRate, availableRate)
        );

        defaultTarget.allocatorMintingRate = availableRate - allocatorMintingRate - selfMintingRate;
        $.totalSelfMintingRate = $.totalSelfMintingRate - targetData.selfMintingRate + selfMintingRate;
    }

    /**
     * @notice Sets target allocation values and adds/removes target from active list
     * @param target Address of the target being updated
     * @param allocatorMintingRate New allocator-minting rate for the target (tokens per block)
     * @param selfMintingRate New self-minting rate for the target (tokens per block)
     * @dev This function is never called for the default target (at index 0), which is handled separately
     */
    function _updateTargetAllocationData(
        address target,
        uint256 allocatorMintingRate,
        uint256 selfMintingRate
    ) private {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[target];

        // Internal design invariants:
        // - targetAddresses[0] is always the default target and is never removed
        // - targetAddresses[1..] contains all non-default targets with explicitly set non-zero allocations
        // - targetAddresses does not contain duplicates
        // - allocationTargets mapping contains allocation data for all targets in targetAddresses
        // - default target is automatically adjusted by _validateAndUpdateTotalAllocations
        // - Governance actions can create allocationTarget mappings with lastChangeNotifiedBlock set for targets not in targetAddresses. This is valid.
        // Therefore:
        // - Only add a non-default target to the list if it previously had no allocation
        // - Remove a non-default target from the list when setting both allocations to 0
        // - Delete allocationTargets mapping entry when removing a target from targetAddresses
        // - Do not set lastChangeNotifiedBlock in this function
        if (allocatorMintingRate != 0 || selfMintingRate != 0) {
            // Add to list if previously had no allocation
            if (targetData.allocatorMintingRate == 0 && targetData.selfMintingRate == 0) $.targetAddresses.push(target);

            targetData.allocatorMintingRate = allocatorMintingRate;
            targetData.selfMintingRate = selfMintingRate;
        } else {
            // Remove target completely (from list and mapping)
            _removeTarget(target);
        }
    }

    /**
     * @notice Removes target from targetAddresses array and deletes its allocation data
     * @param target Address of the target to remove
     * @dev Starts at index 1 since index 0 is always the default target and should never be removed
     * @dev Uses swap-and-pop for gas efficiency
     */
    function _removeTarget(address target) private {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        for (uint256 i = 1; i < $.targetAddresses.length; ++i) {
            if ($.targetAddresses[i] == target) {
                $.targetAddresses[i] = $.targetAddresses[$.targetAddresses.length - 1];
                $.targetAddresses.pop();
                delete $.allocationTargets[target];
                break;
            }
        }
    }

    // -- View Functions --

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function getIssuancePerBlock() external view override returns (uint256) {
        return _getIssuanceAllocatorStorage().issuancePerBlock;
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     */
    function getDistributionState() external view override returns (DistributionState memory) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        return
            DistributionState({
                lastDistributionBlock: $.lastDistributionBlock,
                lastSelfMintingBlock: $.lastSelfMintingBlock,
                selfMintingOffset: $.selfMintingOffset
            });
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
     * @inheritdoc IIssuanceAllocationData
     */
    function getTargetData(address target) external view override returns (AllocationTarget memory) {
        return _getIssuanceAllocatorStorage().allocationTargets[target];
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     * @dev Returns assigned allocation regardless of whether target is address(0) or the default.
     * @dev For address(0), no minting occurs but the allocation represents the unallocated portion.
     * @dev For effective allocations excluding unmintable portion, use getTotalAllocation().
     */
    function getTargetAllocation(address target) external view override returns (Allocation memory) {
        AllocationTarget storage targetData = _getIssuanceAllocatorStorage().allocationTargets[target];
        return
            Allocation({
                totalAllocationRate: targetData.allocatorMintingRate + targetData.selfMintingRate,
                allocatorMintingRate: targetData.allocatorMintingRate,
                selfMintingRate: targetData.selfMintingRate
            });
    }

    /**
     * @inheritdoc IIssuanceAllocationDistribution
     * @dev Returns assigned issuance rates regardless of whether target is address(0) or the default.
     * @dev For address(0), no minting occurs but rates reflect what would be issued if mintable.
     * @dev selfIssuanceBlockAppliedTo reflects the last block for which self-minting allowances have been
     * calculated and emitted (lastSelfMintingBlock). This advances continuously, unaffected by pause state.
     */
    function getTargetIssuancePerBlock(address target) external view override returns (TargetIssuancePerBlock memory) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();
        AllocationTarget storage targetData = $.allocationTargets[target];

        return
            TargetIssuancePerBlock({
                allocatorIssuanceRate: targetData.allocatorMintingRate,
                allocatorIssuanceBlockAppliedTo: $.lastDistributionBlock,
                selfIssuanceRate: targetData.selfMintingRate,
                selfIssuanceBlockAppliedTo: $.lastSelfMintingBlock
            });
    }

    /**
     * @inheritdoc IIssuanceAllocationStatus
     * @dev For reporting purposes, if the default target target is address(0), its allocation
     * @dev is treated as "unallocated" since address(0) cannot receive minting.
     * @dev When default is address(0): returns actual allocated amounts (may be less than issuancePerBlock)
     * @dev When default is a real address: returns issuancePerBlock
     * @dev Note: Internally, the contract always maintains 100% allocation invariant, even when default is address(0)
     */
    function getTotalAllocation() external view override returns (Allocation memory allocation) {
        IssuanceAllocatorData storage $ = _getIssuanceAllocatorStorage();

        // If default is address(0), exclude its allocation from reported totals
        // since it doe not receive minting (so it is considered unallocated).
        // Address(0) will only have non-zero allocation when it is the default target,
        // so we can directly subtract zero address allocation.
        allocation.totalAllocationRate = $.issuancePerBlock - $.allocationTargets[address(0)].allocatorMintingRate;
        allocation.selfMintingRate = $.totalSelfMintingRate;
        allocation.allocatorMintingRate = allocation.totalAllocationRate - allocation.selfMintingRate;
    }
}
