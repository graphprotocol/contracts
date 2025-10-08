# IssuanceAllocator

The IssuanceAllocator is a smart contract responsible for allocating token issuance to different components of The Graph protocol. It calculates issuance for all targets based on their configured proportions and handles minting for non-self-minting targets.

## Overview

The contract operates as a central distribution hub for newly minted Graph tokens, ensuring that different protocol components receive their allocated share of token issuance according to predefined proportions. It supports both allocator-minting targets (recommended for new targets) and self-minting targets (for backwards compatibility), with the ability to have mixed allocations primarily for migration scenarios.

## Architecture

### Allocation Types

The contract supports two types of allocation:

1. **Allocator-minting allocation**: The IssuanceAllocator calculates and mints tokens directly to targets. This is the recommended approach for new targets as it provides robust control over token issuance through the IssuanceAllocator.

2. **Self-minting allocation**: The IssuanceAllocator calculates issuance but does not mint tokens directly. Instead, targets call `getTargetIssuancePerBlock()` to determine their allocation and mint tokens themselves. This feature exists primarily for backwards compatibility with existing contracts like the RewardsManager.

While targets can technically have both types of allocation simultaneously, this is not the expected configuration. (It could be useful for migration scenarios where a self-minting target is gradually transitioning to allocator-minting allocation.)

### Roles

The contract uses role-based access control:

- **GOVERNOR_ROLE**: Can set issuance rates, manage target allocations, notify targets, and perform all governance actions
- **PAUSE_ROLE**: Can pause contract operations (inherited from BaseUpgradeable)

### Pause and Accumulation System

The IssuanceAllocator includes a pause and accumulation system designed to respond to operational issues while preserving issuance integrity:

#### Pause Behavior

When the contract is paused:

- **Distribution stops**: `distributeIssuance()` returns early without minting any tokens, returning the last block when issuance was distributed.
- **Accumulation begins**: Issuance for allocator-minting targets accumulates in `pendingAccumulatedAllocatorIssuance` and will be distributed when the contract is unpaused (or in the interim via `distributePendingIssuance()`) according to their configured proportions at the time of distribution.
- **Self-minting continues**: Self-minting targets can still query their allocation, but should check the `blockAppliedTo` fields to respect pause state. Because RewardsManager does not check `blockAppliedTo` and will mint tokens even when the allocator is paused, the initial implementation does not pause self-minting targets. (This behavior is subject to change in future versions, and new targets should not check `blockAppliedTo`.) Note that RewardsManager is indepently pausable.
- **Configuration allowed**: Governance functions like `setIssuancePerBlock()` and `setTargetAllocation()` still work. However, unlike changes made while unpaused, changes made will be applied from lastIssuanceDistributionBlock rather than the current block.
- **Notifications continue**: Targets are still notified of allocation changes, and should check the `blockAppliedTo` fields to correctly apply changes.

#### Accumulation Logic

During pause periods, the contract tracks:

- `lastIssuanceAccumulationBlock`: Updated to current block whenever accumulation occurs
- `pendingAccumulatedAllocatorIssuance`: Accumulates issuance intended for allocator-minting targets
- Calculation: `(issuancePerBlock * blocksSinceLastAccumulation * totalAllocatorMintingAllocationPPM) / MILLION`

#### Recovery Process

When unpausing or manually distributing:

1. **Automatic distribution**: `distributeIssuance()` first calls `_distributePendingIssuance()` to handle accumulated issuance
2. **Manual distribution**: `distributePendingIssuance()` can be called directly by governance, even while paused
3. **Proportional allocation**: Pending issuance is distributed proportionally among current allocator-minting targets
4. **Clean slate**: After distribution, `pendingAccumulatedAllocatorIssuance` is reset to 0

Note that if there are no allocator-minting targets all pending issuance is lost. If not all of the allocation allowance is used, there will be a proportional amount of accumulated issuance lost.

#### Use Cases

This system enables:

- **Rapid response**: Pause immediately during operational issues without losing track of issuance
- **Investigation time**: Allow time to investigate and resolve issues while maintaining issuance accounting
- **Gradual recovery**: Distribute accumulated issuance manually or automatically when ready
- **Target changes**: Modify allocations during pause periods, with accumulated issuance distributed to according to updated allocations

### Storage

The contract uses ERC-7201 namespaced storage to prevent storage collisions in upgradeable contracts:

- `issuancePerBlock`: Total token issuance per block across all targets
- `lastIssuanceDistributionBlock`: Last block when issuance was distributed
- `lastIssuanceAccumulationBlock`: Last block when issuance was accumulated during pause
- `allocationTargets`: Maps target addresses to their allocation data (allocator-minting PPM, self-minting PPM, notification status)
- `targetAddresses`: Array of all registered target addresses with non-zero total allocations
- `totalAllocationPPM`: Sum of all allocations across all targets (cannot exceed 1,000,000 PPM = 100%)
- `totalAllocatorMintingAllocationPPM`: Sum of allocator-minting allocations across all targets
- `totalSelfMintingAllocationPPM`: Sum of self-minting allocations across all targets
- `pendingAccumulatedAllocatorIssuance`: Accumulated issuance for allocator-minting targets during pause

### Constants

The contract inherits the following constant from `BaseUpgradeable`.

## Core Functions

### Distribution Management

#### `distributeIssuance() → uint256`

- **Access**: Public (no restrictions)
- **Purpose**: Distribute pending issuance to all allocator-minting targets
- **Returns**: Block number that issuance was distributed to (normally current block)
- **Behavior**:
  - First distributes any pending accumulated issuance from pause periods
  - Calculates blocks since last distribution
  - Mints tokens proportionally to allocator-minting targets only
  - Updates `lastIssuanceDistributionBlock` to current block
  - Returns early with current `lastIssuanceDistributionBlock` when paused (no distribution occurs)
  - Returns early if no blocks have passed since last distribution
  - Can be called by anyone to trigger distribution

#### `setIssuancePerBlock(uint256 newIssuancePerBlock, bool evenIfDistributionPending) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set the total token issuance rate per block
- **Parameters**:
  - `newIssuancePerBlock` - New issuance rate in tokens per block
  - `evenIfDistributionPending` - If true, skip distribution requirement (notifications still occur)
- **Returns**: True if applied, false if blocked by pending operations
- **Events**: Emits `IssuancePerBlockUpdated`
- **Notes**:
  - Automatically distributes or accumulates pending issuance before changing rate (unless evenIfDistributionPending=true or paused)
  - Notifies all targets of the upcoming change (unless paused)
  - Returns false if distribution fails and evenIfDistributionPending=false, reverts if notification fails
  - L1GraphTokenGateway must be updated when this changes to maintain bridge functionality
  - No-op if new rate equals current rate (returns true immediately)

### Target Management

The contract provides multiple overloaded functions for setting target allocations:

#### `setTargetAllocation(address target, uint256 allocatorMintingPPM) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set allocator-minting allocation only (selfMintingPPM=0, evenIfDistributionPending=false)
- **Parameters**:
  - `target` - Target contract address (must support IIssuanceTarget interface)
  - `allocatorMintingPPM` - Allocator-minting allocation in PPM (0 removes target if no self-minting allocation)

#### `setTargetAllocation(address target, uint256 allocatorMintingPPM, uint256 selfMintingPPM) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set both allocator-minting and self-minting allocations (evenIfDistributionPending=false)
- **Parameters**:
  - `target` - Target contract address (must support IIssuanceTarget interface)
  - `allocatorMintingPPM` - Allocator-minting allocation in PPM
  - `selfMintingPPM` - Self-minting allocation in PPM

#### `setTargetAllocation(address target, uint256 allocatorMintingPPM, uint256 selfMintingPPM, bool evenIfDistributionPending) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set both allocations with full control over distribution requirements
- **Parameters**:
  - `target` - Target contract address (must support IIssuanceTarget interface)
  - `allocatorMintingPPM` - Allocator-minting allocation in PPM
  - `selfMintingPPM` - Self-minting allocation in PPM
  - `evenIfDistributionPending` - If true, skip distribution requirement (notifications still occur)
- **Returns**: True if applied, false if blocked by pending operations
- **Events**: Emits `TargetAllocationUpdated` with total allocation (allocatorMintingPPM + selfMintingPPM)
- **Behavior**:
  - Validates target supports IIssuanceTarget interface (for non-zero total allocations)
  - No-op if new allocations equal current allocations (returns true immediately)
  - Distributes or accumulates pending issuance before changing allocation (unless evenIfDistributionPending=true)
  - Notifies target of upcoming change (always occurs unless overridden by `forceTargetNoChangeNotificationBlock()`)
  - Returns false if distribution fails (when evenIfDistributionPending=false), reverts if notification fails
  - Validates total allocation doesn't exceed MILLION after notification (prevents reentrancy issues)
  - Adds target to registry if total allocation > 0 and not already present
  - Removes target from registry if total allocation = 0 (uses swap-and-pop for gas efficiency)
  - Deletes allocation data when removing target from registry

#### `notifyTarget(address target) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Manually notify a specific target about allocation changes
- **Returns**: True if notification sent or already sent this block
- **Notes**: Used for gas limit recovery scenarios. Will revert if target notification fails.

#### `forceTargetNoChangeNotificationBlock(address target, uint256 blockNumber) → uint256`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Override the last notification block for a target
- **Parameters**:
  - `target` - Target address to update
  - `blockNumber` - Block number to set (past = allow re-notification, future = prevent notification)
- **Returns**: The block number that was set
- **Notes**: Used for gas limit recovery scenarios

#### `distributePendingIssuance() → uint256`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Distribute any pending accumulated issuance to allocator-minting targets
- **Returns**: Block number up to which issuance has been distributed
- **Notes**:
  - Distributes issuance that accumulated while paused
  - Can be called even when the contract is paused
  - No-op if there is no pending issuance or all targets are self-minting

### View Functions

#### `getTargetAllocation(address target) → Allocation`

- **Purpose**: Get current allocation for a target
- **Returns**: Allocation struct containing:
  - `totalAllocationPPM`: Total allocation (allocatorMintingAllocationPPM + selfMintingAllocationPPM)
  - `allocatorMintingAllocationPPM`: Allocator-minting allocation in PPM
  - `selfMintingAllocationPPM`: Self-minting allocation in PPM

#### `getTotalAllocation() → Allocation`

- **Purpose**: Get current global allocation totals
- **Returns**: Allocation struct with totals across all targets

#### `getTargets() → address[]`

- **Purpose**: Get all target addresses with non-zero total allocations
- **Returns**: Array of target addresses

#### `getTargetAt(uint256 index) → address`

- **Purpose**: Get a specific target address by index
- **Returns**: Target address at the specified index

#### `getTargetCount() → uint256`

- **Purpose**: Get the number of allocated targets
- **Returns**: Total number of targets with non-zero allocations

#### `getTargetIssuancePerBlock(address target) → TargetIssuancePerBlock`

- **Purpose**: Get issuance per block information for a target
- **Returns**: TargetIssuancePerBlock struct containing:
  - `allocatorIssuancePerBlock`: Issuance per block for allocator-minting portion
  - `allocatorIssuanceBlockAppliedTo`: Block up to which allocator issuance has been applied
  - `selfIssuancePerBlock`: Issuance per block for self-minting portion
  - `selfIssuanceBlockAppliedTo`: Block up to which self issuance has been applied (always current block)
- **Notes**:
  - Does not revert when paused - callers should check blockAppliedTo fields
  - If allocatorIssuanceBlockAppliedTo is not current block, allocator issuance is paused
  - Self-minting targets should use this to determine how much to mint

#### `issuancePerBlock() → uint256`

- **Purpose**: Get the current total issuance per block
- **Returns**: Current issuance per block across all targets

#### `lastIssuanceDistributionBlock() → uint256`

- **Purpose**: Get the last block where issuance was distributed
- **Returns**: Last distribution block number

#### `lastIssuanceAccumulationBlock() → uint256`

- **Purpose**: Get the last block where issuance was accumulated during pause
- **Returns**: Last accumulation block number

#### `pendingAccumulatedAllocatorIssuance() → uint256`

- **Purpose**: Get the amount of pending accumulated allocator issuance
- **Returns**: Amount of issuance accumulated during pause periods

#### `getTargetData(address target) → AllocationTarget`

- **Purpose**: Get internal target data (implementation-specific)
- **Returns**: AllocationTarget struct containing allocatorMintingPPM, selfMintingPPM, and lastChangeNotifiedBlock
- **Notes**: Primarily for operator use and debugging

## Allocation Logic

### Distribution Calculation

For each target during distribution, only the allocator-minting portion is distributed:

```solidity
targetIssuance = (totalNewIssuance * targetAllocatorMintingPPM) / MILLION
```

For self-minting targets, they query their allocation via `getTargetIssuancePerBlock()`:

```solidity
selfIssuancePerBlock = (issuancePerBlock * targetSelfMintingPPM) / MILLION
```

Where:

- `totalNewIssuance = issuancePerBlock * blocksSinceLastDistribution`
- `targetAllocatorMintingPPM` is the target's allocator-minting allocation in PPM
- `targetSelfMintingPPM` is the target's self-minting allocation in PPM
- `MILLION = 1,000,000` (representing 100%)

### Allocation Constraints

- Total allocation across all targets cannot exceed 1,000,000 PPM (100%)
- Individual target allocations (allocator-minting + self-minting) can be any value from 0 to 1,000,000 PPM
- Setting both allocations to 0 removes the target from the registry
- Allocations are measured in PPM for precision (1 PPM = 0.0001%)
- Small rounding losses may occur in calculations due to integer division (this is acceptable)
- Each target can have both allocator-minting and self-minting allocations, though typically only one is used

## Change Notification System

Before any allocation changes, targets are notified via the `IIssuanceTarget.beforeIssuanceAllocationChange()` function. This allows targets to:

- Update their internal state to the current block
- Prepare for the allocation change
- Ensure consistency in their reward calculations

### Notification Rules

- Each target is notified at most once per block (unless overridden via `forceTargetNoChangeNotificationBlock()`)
- Notifications are tracked per target using `lastChangeNotifiedBlock`
- Failed notifications cause the entire transaction to revert
- Use `forceTargetNoChangeNotificationBlock()` to skip notification for broken targets before removing them
- Notifications cannot be skipped (the `evenIfDistributionPending` parameter only affects distribution requirements)
- Failed notifications cause the entire transaction to revert
- Use `forceNoChangeNotificationBlock()` to skip notification for malfunctioning targets before removing them
- Notifications cannot be skipped (the `force` parameter only affects distribution requirements)
- Manual notification is available for gas limit recovery via `notifyTarget()`

## Gas Limit Recovery

The contract includes several mechanisms to handle potential gas limit issues:

### Potential Issues

1. **Large target arrays**: Many targets could exceed gas limits during distribution
2. **Expensive notifications**: Target notification calls could consume too much gas
3. **Malfunctioning targets**: Target contracts that revert when notified

### Recovery Mechanisms

1. **Pause functionality**: Contract can be paused to stop operations during recovery
2. **Individual target notification**: `notifyTarget()` allows notifying targets one by one (will revert if target notification reverts)
3. **Force notification override**: `forceTargetNoChangeNotificationBlock()` can skip problematic targets
4. **Force parameters**: Both `setIssuancePerBlock()` and `setTargetAllocation()` accept `evenIfDistributionPending` flags to skip distribution requirements
5. **Target removal**: Use `forceTargetNoChangeNotificationBlock()` to skip notification, then remove malfunctioning targets by setting both allocations to 0
6. **Pending issuance distribution**: `distributePendingIssuance()` can be called manually to distribute accumulated issuance

## Events

```solidity
event IssuanceDistributed(address indexed target, uint256 amount);
event TargetAllocationUpdated(address indexed target, uint256 newAllocation);
event IssuancePerBlockUpdated(uint256 oldIssuancePerBlock, uint256 newIssuancePerBlock);
```

## Error Conditions

```solidity
error IssuanceAllocatorTargetAddressCannotBeZero();
error IssuanceAllocatorInsufficientAllocationAvailable();
error IssuanceAllocatorTargetDoesNotSupportIIssuanceTarget();
```

## Usage Patterns

### Initial Setup

1. Deploy contract with Graph Token address
2. Initialize with governor address
3. Set initial issuance per block rate
4. Add targets with their allocations
5. Grant minter role to IssuanceAllocator on Graph Token

### Normal Operation

1. Targets or external actors call `distributeIssuance()` periodically
2. Governor adjusts issuance rates as needed via `setIssuancePerBlock()`
3. Governor adds/removes/modifies targets via `setTargetAllocation()` overloads
4. Self-minting targets query their allocation via `getTargetIssuancePerBlock()`

### Emergency Scenarios

- **Gas limit issues**: Use pause, individual notifications, and `evenIfDistributionPending` parameters
- **Target failures**: Use `forceTargetNoChangeNotificationBlock()` to skip notification, then remove problematic targets by setting both allocations to 0
- **Rate changes**: Use `evenIfDistributionPending` parameter to bypass distribution requirements

### For L1 Bridge Integration

When `setIssuancePerBlock()` is called, the L1GraphTokenGateway's `updateL2MintAllowance()` function must be called to ensure the bridge can mint the correct amount of tokens on L2.

## Security Considerations

- Only governor can modify allocations and issuance rates
- Interface validation prevents adding incompatible targets
- Total allocation limits prevent over-allocation
- Pause functionality provides emergency stop capability
- Notification system ensures targets can prepare for changes
- Self-minting targets must respect paused state to prevent unauthorized minting
