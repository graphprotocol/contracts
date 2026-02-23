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
- Use `forceTargetNoChangeNotificationBlock()` to skip notification for malfunctioning targets before removing them
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

## Usage Patterns

### Initial Setup

**Note: This section is a work-in-progress discussion document for planning deployment, not finalized implementation documentation.**

**The verification steps documented here are minimal deployment verification checks. These should be complemented by appropriate functional testing and verification as needed for production deployment.**

**Prerequisites:**

- GraphToken contract deployed
- RewardsManager upgraded with `setIssuanceAllocator()` function
- GraphIssuanceProxyAdmin deployed with protocol governance as owner

To safely replicate existing issuance configuration during RewardsManager migration:

- Default target starts as `address(0)` (that will not be minted to), allowing initial configuration without minting to any targets
- Deployment uses atomic initialization via proxy constructor (prevents front-running)
- Deployment account performs initial configuration, then transfers control to governance
- Granting of minter role can be delayed until replication of initial configuration with upgraded RewardsManager is verified to allow seamless transition to use of IssuanceAllocator
- **Governance control**: This contract uses OpenZeppelin's TransparentUpgradeableProxy pattern (not custom GraphProxy). GraphIssuanceProxyAdmin (owned by protocol governance) controls upgrades, while GOVERNOR_ROLE controls operations. The same governance address should have both roles.

**Deployment sequence:**

1. **Deploy and initialize** (deployment account)
   - Deploy IssuanceAllocator implementation with GraphToken address
   - Deploy TransparentUpgradeableProxy with implementation, GraphIssuanceProxyAdmin, and initialization data
   - **Atomic initialization**: `initialize(deploymentAccountAddress)` called via proxy constructor
   - Deployment account receives GOVERNOR_ROLE (temporary, for configuration)
   - Automatically creates default target at `targetAddresses[0] = address(0)`
   - Sets `lastDistributionBlock = block.number`
   - **Security**: Front-running prevented by atomic deployment + initialization
2. **Set issuance rate** (deployment account)
   - Query current rate from RewardsManager: `rate = rewardsManager.issuancePerBlock()`
   - Call `setIssuancePerBlock(rate)` to replicate existing rate
   - All issuance allocated to default target (`address(0)`)
   - No tokens minted (default target cannot receive mints)
3. **Assign RewardsManager allocation** (deployment account)
   - Call `setTargetAllocation(rewardsManagerAddress, 0, issuancePerBlock)`
   - `allocatorMintingRate = 0` (RewardsManager will self-mint)
   - `selfMintingRate = issuancePerBlock` (RewardsManager receives 100% allocation)
   - Default target automatically adjusts to zero allocation
4. **Verify configuration before transfer** (deployment account)
   - Verify contract is not paused (`paused()` returns false)
   - Verify `getIssuancePerBlock()` returns expected rate (matches RewardsManager)
   - Verify `getTargetAllocation(rewardsManager)` shows correct self-minting configuration
   - Verify only two targets exist: `targetAddresses[0] = address(0)` and `targetAddresses[1] = rewardsManager`
   - Verify default target is `address(0)` with zero allocation
   - Contract is ready to transfer control to governance
5. **Distribute issuance** (anyone - no role required)
   - Call `distributeIssuance()` to bring contract to fully current state
   - Updates `lastDistributionBlock` to current block
   - Verifies distribution mechanism is functioning correctly
   - No tokens minted (no minter role yet, all allocation to self-minting RM)
6. **Set pause controls and transfer governance** (deployment account)
   - Grant PAUSE_ROLE to pause guardian (same account as used for RewardsManager pause control)
   - Grant GOVERNOR_ROLE to actual governor address (protocol governance multisig)
   - Revoke GOVERNOR_ROLE from deployment account (MUST grant to governance first, then revoke)
   - **Note**: Upgrade control (via GraphIssuanceProxyAdmin) is separate from GOVERNOR_ROLE
7. **Verify deployment and configuration** (governor)
   - **Bytecode verification**: Verify deployed implementation bytecode matches expected contract
   - **Access control**:
     - Verify governance address has GOVERNOR_ROLE
     - Verify deployment account does NOT have GOVERNOR_ROLE
     - Verify pause guardian has PAUSE_ROLE
     - **Off-chain**: Review all RoleGranted events since deployment to verify no other addresses have GOVERNOR_ROLE or PAUSE_ROLE
   - **Pause state**: Verify contract is not paused (`paused()` returns false)
   - **Issuance rate**: Verify `getIssuancePerBlock()` matches RewardsManager rate exactly
   - **Target configuration**:
     - Verify only two targets exist: `targetAddresses[0] = address(0)` and `targetAddresses[1] = rewardsManager`
     - Verify default target is `address(0)` with zero allocation
     - Verify `getTargetAllocation(rewardsManager)` shows correct self-minting allocation (100%)
   - **Proxy configuration**:
     - Verify GraphIssuanceProxyAdmin controls the proxy
     - Verify GraphIssuanceProxyAdmin owner is protocol governance
8. **Configure RewardsManager** (governor)
   - Call `rewardsManager.setIssuanceAllocator(issuanceAllocatorAddress)`
   - RewardsManager will now query IssuanceAllocator for its issuance rate
   - RewardsManager continues to mint tokens itself (self-minting)
9. **Grant minter role** (governor, only when configuration verified)
   - Grant minter role to IssuanceAllocator on Graph Token
10. **Set default target** (governor, optional, recommended)

- Call `setDefaultTarget()` to receive future unallocated issuance

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
