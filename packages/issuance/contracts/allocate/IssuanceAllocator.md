# IssuanceAllocator

The IssuanceAllocator is a smart contract responsible for allocating token issuance to different components of The Graph protocol. It calculates issuance for all targets based on their configured rates (tokens per block) and handles minting for allocator-minting targets.

## Overview

The contract operates as a central distribution hub for newly minted Graph tokens, ensuring that different protocol components receive their allocated share of token issuance according to configured rates. It maintains a 100% allocation invariant through a default target mechanism, where any unallocated portion automatically goes to the default target. It supports both allocator-minting targets (recommended for new targets) and self-minting targets (for backwards compatibility), with the ability to have mixed allocations primarily for migration scenarios.

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
- **Accumulation begins**: Self-minting allowances accumulate in `selfMintingOffset`, reducing the allocator-minting budget. When distribution resumes, current rates are applied retroactively to the entire undistributed period.
- **Self-minting continues**: Self-minting targets can still query their allocation, but should check the `blockAppliedTo` fields to respect pause state. Because RewardsManager does not check `blockAppliedTo` and will mint tokens even when the allocator is paused, the initial implementation does not pause self-minting targets. (This behavior is subject to change in future versions, and new targets should check `blockAppliedTo`.) Note that RewardsManager is independently pausable.
- **Configuration allowed**: Governance functions like `setIssuancePerBlock()` and `setTargetAllocation()` still work. Rate changes apply immediately. When distribution resumes (either automatically when unpaused or manually via `distributePendingIssuance()`), the current rates are used retroactively for the entire undistributed period from `lastDistributionBlock` to the distribution block.
- **Notifications continue**: Targets are still notified of allocation changes even when paused, and should check the `blockAppliedTo` fields to correctly apply changes.

#### Accumulation Logic

During pause periods, the contract tracks self-minting allowances that reduce the allocator-minting budget:

- `lastSelfMintingBlock`: Updated to current block whenever self-minting advances (continuously, even when paused)
- `selfMintingOffset`: Accumulates self-minting amounts that will reduce the allocator-minting budget when distribution resumes
- Calculation: `totalSelfMintingRate * blocksSinceLastSelfMinting`
- **Conservative accumulation**: Once accumulation starts (during pause), it continues through any unpaused periods until distribution clears it.

#### Recovery Process

When distribution resumes:

1. **Automatic distribution**: `distributeIssuance()` detects accumulated self-minting and triggers retroactive distribution
2. **Manual distribution**: `distributePendingIssuance()` can be called directly by governance, even while paused
3. **Retroactive application**: Current rates are applied retroactively to the entire undistributed period
4. **Budget reduction**: Accumulated self-minting reduces the allocator-minting budget for the period
5. **Priority distribution**: Non-default targets receive their full rates first (if budget allows), default target receives remainder
6. **Clean slate**: After distribution to current block, `selfMintingOffset` is reset to 0

#### Use Cases

This system enables:

- **Rapid response**: Pause immediately during operational issues without losing track of issuance
- **Investigation time**: Allow time to investigate and resolve issues while maintaining issuance accounting
- **Gradual recovery**: Distribute accumulated issuance manually or automatically when ready
- **Target changes**: Modify allocations during pause periods, with accumulated issuance distributed according to updated allocations

### Storage

The contract uses ERC-7201 namespaced storage to prevent storage collisions in upgradeable contracts:

- `issuancePerBlock`: Total token issuance rate per block across all targets (tokens per block)
- `lastDistributionBlock`: Last block when allocator-minting issuance was distributed
- `lastSelfMintingBlock`: Last block when self-minting allowances were calculated and tracked
- `selfMintingOffset`: Accumulated self-minting that offsets allocator-minting budget (starts during pause, clears on distribution)
- `allocationTargets`: Maps target addresses to their allocation data (allocatorMintingRate, selfMintingRate, lastChangeNotifiedBlock)
- `targetAddresses`: Array of all target addresses (index 0 is always the default target, indices 1+ are explicitly allocated targets)
- `totalSelfMintingRate`: Sum of self-minting rates across all targets (tokens per block)

**Allocation Invariant:** The contract maintains a 100% allocation invariant:

- A default target exists at `targetAddresses[0]` (initially `address(0)`)
- Total allocator-minting rate + total self-minting rate always equals `issuancePerBlock`
- The default target automatically receives any unallocated portion
- When the default address is `address(0)`, the unallocated portion is not minted

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
  - Updates `lastDistributionBlock` to current block when not paused
  - Returns `lastDistributionBlock` when paused (no distribution occurs, block number frozen)
  - Returns early if no blocks have passed since last distribution
  - Can be called by anyone to trigger distribution

#### `setIssuancePerBlock(uint256 newIssuancePerBlock) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set the total token issuance rate per block
- **Parameters**:
  - `newIssuancePerBlock` - New issuance rate in tokens per block
- **Returns**: True if applied
- **Events**: Emits `IssuancePerBlockUpdated`
- **Notes**:
  - Requires distribution to have reached `block.number`
  - Automatically distributes pending issuance before changing rate
  - Notifies the default target of the upcoming change
  - Only the default target's rate changes; other targets' rates remain fixed
  - L1GraphTokenGateway must be updated when this changes to maintain bridge functionality
  - No-op if new rate equals current rate (returns true immediately)

#### `setIssuancePerBlock(uint256 newIssuancePerBlock, uint256 minDistributedBlock) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set the total token issuance rate per block, requiring distribution has reached at least the specified block
- **Parameters**:
  - `newIssuancePerBlock` - New issuance rate in tokens per block
  - `minDistributedBlock` - Minimum block number that distribution must have reached
- **Returns**: True if applied, false if distribution hasn't reached `minDistributedBlock`
- **Events**: Emits `IssuancePerBlockUpdated`
- **Notes**:
  - Allows configuration changes while paused: first call `distributePendingIssuance(blockNumber)`, then this function with same or lower blockNumber
  - Rate changes apply immediately and are used retroactively when distribution resumes

### Target Management

The contract provides multiple overloaded functions for setting target allocations:

#### `setTargetAllocation(IIssuanceTarget target, uint256 allocatorMintingRate) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set allocator-minting rate only (selfMintingRate=0)
- **Parameters**:
  - `target` - Target contract address (must support IIssuanceTarget interface)
  - `allocatorMintingRate` - Allocator-minting rate in tokens per block (0 removes target if no self-minting rate)
- **Returns**: True if applied
- **Events**: Emits `TargetAllocationUpdated`
- **Notes**:
  - Requires distribution to have reached `block.number`
  - Cannot be used for the default target (use `setDefaultTarget()` instead)

#### `setTargetAllocation(IIssuanceTarget target, uint256 allocatorMintingRate, uint256 selfMintingRate) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set both allocator-minting and self-minting rates
- **Parameters**:
  - `target` - Target contract address (must support IIssuanceTarget interface)
  - `allocatorMintingRate` - Allocator-minting rate in tokens per block
  - `selfMintingRate` - Self-minting rate in tokens per block
- **Returns**: True if applied
- **Events**: Emits `TargetAllocationUpdated`
- **Notes**:
  - Requires distribution to have reached `block.number`
  - Cannot be used for the default target (use `setDefaultTarget()` instead)

#### `setTargetAllocation(IIssuanceTarget target, uint256 allocatorMintingRate, uint256 selfMintingRate, uint256 minDistributedBlock) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set both rates, requiring distribution has reached at least the specified block
- **Parameters**:
  - `target` - Target contract address (must support IIssuanceTarget interface)
  - `allocatorMintingRate` - Allocator-minting rate in tokens per block
  - `selfMintingRate` - Self-minting rate in tokens per block
  - `minDistributedBlock` - Minimum block number that distribution must have reached
- **Returns**: True if applied, false if distribution hasn't reached `minDistributedBlock`
- **Events**: Emits `TargetAllocationUpdated`
- **Behavior**:
  - Validates target supports IIssuanceTarget interface (for non-zero total rates)
  - No-op if new rates equal current rates (returns true immediately)
  - Distributes pending issuance before changing allocation
  - Notifies target of upcoming change (always occurs unless overridden by `forceTargetNoChangeNotificationBlock()`)
  - Reverts if notification fails
  - Validates requested rates don't exceed available budget (prevents exceeding 100% invariant)
  - Adds target to registry if total rate > 0 and not already present
  - Removes target from registry if total rate = 0 (uses swap-and-pop for gas efficiency)
  - Deletes allocation data when removing target from registry
  - Default target automatically adjusted to maintain 100% invariant
  - Allows configuration changes while paused: first call `distributePendingIssuance(blockNumber)`, then this function

#### `setDefaultTarget(address newAddress) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set the address that receives the default portion of issuance (unallocated to other targets)
- **Parameters**:
  - `newAddress` - The new default target address (can be `address(0)`)
- **Returns**: True if applied
- **Events**: Emits `DefaultTargetUpdated`
- **Notes**:
  - Requires distribution to have reached `block.number`
  - The default target automatically receives any unallocated portion to maintain 100% invariant
  - When set to `address(0)`, the unallocated portion is not minted
  - Cannot set default to an address that already has an explicit allocation
  - Notifies both old and new addresses

#### `setDefaultTarget(address newAddress, uint256 minDistributedBlock) → bool`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Set the default target address, requiring distribution has reached at least the specified block
- **Parameters**:
  - `newAddress` - The new default target address (can be `address(0)`)
  - `minDistributedBlock` - Minimum block number that distribution must have reached
- **Returns**: True if applied, false if distribution hasn't reached `minDistributedBlock`
- **Events**: Emits `DefaultTargetUpdated`
- **Notes**:
  - Allows configuration changes while paused: first call `distributePendingIssuance(blockNumber)`, then this function

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
- **Purpose**: Distribute pending accumulated allocator-minting issuance using current rates
- **Returns**: Block number up to which issuance has been distributed
- **Notes**:
  - Distributes retroactively using current rates for the entire undistributed period
  - Can be called even when the contract is paused
  - Prioritizes non-default targets getting full rates; default gets remainder
  - Finalizes self-minting accumulation for the distributed period

#### `distributePendingIssuance(uint256 toBlockNumber) → uint256`

- **Access**: GOVERNOR_ROLE only
- **Purpose**: Distribute pending accumulated allocator-minting issuance up to a specific block
- **Parameters**:
  - `toBlockNumber` - Block number to distribute up to (must be >= lastDistributionBlock and <= current block)
- **Returns**: Block number up to which issuance has been distributed
- **Notes**:
  - Distributes retroactively using current rates from lastDistributionBlock to toBlockNumber
  - Can be called even when the contract is paused
  - Will revert with `ToBlockOutOfRange()` if toBlockNumber is invalid
  - Useful for gradual catch-up during pause or for setting up configuration changes

### View Functions

#### `getTargetAllocation(address target) → Allocation`

- **Purpose**: Get current allocation for a target
- **Returns**: Allocation struct containing:
  - `totalAllocationRate`: Total allocation rate (allocatorMintingRate + selfMintingRate) in tokens per block
  - `allocatorMintingRate`: Allocator-minting rate in tokens per block
  - `selfMintingRate`: Self-minting rate in tokens per block
- **Notes**: Returns assigned allocation regardless of whether target is `address(0)` or the default target

#### `getTotalAllocation() → Allocation`

- **Purpose**: Get current global allocation totals
- **Returns**: Allocation struct with totals across all targets
- **Notes**: When default target is `address(0)`, its allocation is excluded from reported totals (treated as unallocated since `address(0)` cannot receive minting)

#### `getTargets() → address[]`

- **Purpose**: Get all target addresses (including default target at index 0)
- **Returns**: Array of target addresses

#### `getTargetAt(uint256 index) → address`

- **Purpose**: Get a specific target address by index
- **Returns**: Target address at the specified index
- **Notes**: Index 0 is always the default target

#### `getTargetCount() → uint256`

- **Purpose**: Get the number of targets (including default target)
- **Returns**: Total number of targets (always >= 1)

#### `getTargetIssuancePerBlock(address target) → TargetIssuancePerBlock`

- **Purpose**: Get issuance rate information for a target
- **Returns**: TargetIssuancePerBlock struct containing:
  - `allocatorIssuanceRate`: Allocator-minting rate in tokens per block
  - `allocatorIssuanceBlockAppliedTo`: Block up to which allocator issuance has been distributed (`lastDistributionBlock`)
  - `selfIssuanceRate`: Self-minting rate in tokens per block
  - `selfIssuanceBlockAppliedTo`: Block up to which self-minting allowances have been calculated (`lastSelfMintingBlock`)
- **Notes**:
  - Does not revert when paused - callers should check blockAppliedTo fields
  - If `allocatorIssuanceBlockAppliedTo < block.number`, allocator distribution is behind (likely paused)
  - Self-minting targets should use this to determine their issuance rate
  - Returns assigned rates regardless of whether target is `address(0)` or the default

#### `getIssuancePerBlock() → uint256`

- **Purpose**: Get the current total issuance rate per block
- **Returns**: Current issuance rate in tokens per block across all targets

#### `getDistributionState() → DistributionState`

- **Purpose**: Get pending issuance distribution state
- **Returns**: DistributionState struct containing:
  - `lastDistributionBlock`: Last block where allocator-minting issuance was distributed
  - `lastSelfMintingBlock`: Last block where self-minting allowances were calculated
  - `selfMintingOffset`: Accumulated self-minting that will reduce allocator-minting budget

#### `getTargetData(address target) → AllocationTarget`

- **Purpose**: Get internal target data (implementation-specific)
- **Returns**: AllocationTarget struct containing allocatorMintingRate, selfMintingRate, and lastChangeNotifiedBlock
- **Notes**: Primarily for operator use and debugging

## Allocation Logic

### Rate-Based System

The contract uses absolute rates (tokens per block) rather than proportional allocations:

- Each target has an `allocatorMintingRate` (tokens per block for allocator-minting)
- Each target has a `selfMintingRate` (tokens per block for self-minting)
- The default target automatically receives: `issuancePerBlock - sum(all other targets' rates)`

### Distribution Calculation

For each target during normal distribution, only the allocator-minting portion is distributed:

```solidity
targetIssuance = targetAllocatorMintingRate * blocksSinceLastDistribution
```

For self-minting targets, they query their rate via `getTargetIssuancePerBlock()`:

```solidity
selfIssuanceRate = targetSelfMintingRate
```

### Allocation Constraints and Invariants

- **100% Invariant**: `sum(all allocatorMintingRates) + sum(all selfMintingRates) == issuancePerBlock` (always)
- **Default Target**: Automatically adjusted to maintain the 100% invariant when other allocations change
- **Available Budget**: When setting a target's allocation, available budget = default target's allocator rate + target's current total rate
- **Removing Targets**: Setting both rates to 0 removes the target from the active list (except default target)
- **Rounding**: Small rounding losses may occur during proportional distribution (when budget is insufficient)
- **Mixed Allocations**: Each target can have both allocator-minting and self-minting rates, though typically only one is used

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
- Notifications always occur when allocations change (even when paused)
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
4. **Controlled distribution**: Functions accept `minDistributedBlock` parameter to allow configuration changes while paused (after calling `distributePendingIssuance(blockNumber)`)
5. **Target removal**: Use `forceTargetNoChangeNotificationBlock()` to skip notification, then remove malfunctioning targets by setting both rates to 0
6. **Pending issuance distribution**: `distributePendingIssuance()` can be called manually to distribute accumulated issuance

## Events

```solidity
event IssuanceDistributed(address indexed target, uint256 amount, uint256 indexed fromBlock, uint256 indexed toBlock);

event TargetAllocationUpdated(address indexed target, uint256 newAllocatorMintingRate, uint256 newSelfMintingRate);

event IssuancePerBlockUpdated(uint256 oldIssuancePerBlock, uint256 newIssuancePerBlock);

event DefaultTargetUpdated(address indexed oldAddress, address indexed newAddress);

event IssuanceSelfMintAllowance(
  address indexed target,
  uint256 amount,
  uint256 indexed fromBlock,
  uint256 indexed toBlock
);
```

## Error Conditions

```solidity
error TargetAddressCannotBeZero();
error InsufficientAllocationAvailable(uint256 requested, uint256 available);
error InsufficientUnallocatedForRateDecrease(uint256 oldRate, uint256 newRate, uint256 unallocated);
error TargetDoesNotSupportIIssuanceTarget(address target);
error ToBlockOutOfRange(uint256 toBlock, uint256 minBlock, uint256 maxBlock);
error CannotSetAllocationForDefaultTarget(address defaultTarget);
error CannotSetDefaultToAllocatedTarget(address target);
```

### Error Descriptions

- **TargetAddressCannotBeZero**: Thrown when attempting to set allocation for the zero address (note: zero address can be the default target)
- **InsufficientAllocationAvailable**: Thrown when the requested allocation exceeds available budget (default target allocation + current target allocation)
- **InsufficientUnallocatedForRateDecrease**: Thrown when attempting to decrease issuance rate without sufficient unallocated budget in the default target
- **TargetDoesNotSupportIIssuanceTarget**: Thrown when a target contract does not implement the required IIssuanceTarget interface
- **ToBlockOutOfRange**: Thrown when the `toBlockNumber` parameter in `distributePendingIssuance(uint256)` is outside the valid range (must be >= lastDistributionBlock and <= current block)
- **CannotSetAllocationForDefaultTarget**: Thrown when attempting to use `setTargetAllocation()` on the default target address
- **CannotSetDefaultToAllocatedTarget**: Thrown when attempting to set the default target to an address that already has an explicit allocation

## Usage Patterns

### Initial Setup

1. Deploy contract with Graph Token address
2. Initialize with governor address
   - `lastDistributionBlock` is set to `block.number` at initialization as a safety guard against pausing before configuration
   - This should be updated during initial configuration when `setIssuancePerBlock()` is called
3. Set initial issuance per block rate
   - Updates `lastDistributionBlock` to current block via distribution call
   - This establishes the correct starting point for issuance tracking
4. Add targets with their allocations
5. Grant minter role to IssuanceAllocator on Graph Token

### Normal Operation

1. Targets or external actors call `distributeIssuance()` periodically
2. Governor adjusts issuance rates as needed via `setIssuancePerBlock()`
3. Governor adds/removes/modifies targets via `setTargetAllocation()` overloads
4. Self-minting targets query their allocation via `getTargetIssuancePerBlock()`

### Emergency Scenarios

- **Gas limit issues**: Use pause, individual notifications, and `minDistributedBlock` parameters with `distributePendingIssuance()`
- **Target failures**: Use `forceTargetNoChangeNotificationBlock()` to skip notification, then remove problematic targets by setting both rates to 0
- **Configuration while paused**: Call `distributePendingIssuance(blockNumber)` first, then use `minDistributedBlock` parameter in setter functions

### For L1 Bridge Integration

When `setIssuancePerBlock()` is called, the L1GraphTokenGateway's `updateL2MintAllowance()` function must be called to ensure the bridge can mint the correct amount of tokens on L2.

## Security Considerations

- Only governor can modify allocations and issuance rates
- Interface validation prevents adding incompatible targets
- 100% allocation invariant maintained automatically through default target mechanism
- Budget validation prevents over-allocation
- Pause functionality provides emergency stop capability
- Notification system ensures targets can prepare for changes
- Self-minting targets should respect paused state (check `blockAppliedTo` fields)
- Reentrancy guards protect governance functions
- Default target mechanism ensures total issuance never exceeds configured rate
