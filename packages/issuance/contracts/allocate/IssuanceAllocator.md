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

**Automated Deployment**

The deployment is automated using hardhat-deploy scripts in `packages/issuance/deploy/deploy/`.

**Prerequisites:**

- GraphToken contract deployed (provide via `deployments/<network>/GraphToken.json`)
- RewardsManager deployed (optional, for automatic rate configuration)
- Governor and pauseGuardian addresses configured in `hardhat.config.ts` namedAccounts

**Deployment command:**

```bash
cd packages/issuance/deploy
npx hardhat deploy --tags issuance --network <network>
```

**Architecture:**

- Default target starts as `address(0)` (will not be minted to), allowing safe initial configuration
- Deployment uses atomic initialization via proxy constructor (prevents front-running)
- Contracts initialized with governor address (receives GOVERNOR_ROLE directly)
- Granting of minter role delayed until configuration verified
- **Governance control**: Uses OpenZeppelin's TransparentUpgradeableProxy pattern. GraphIssuanceProxyAdmin (owned by governor) controls upgrades, while GOVERNOR_ROLE controls operations

#### Deployment Sequence

The following scripts run in order (automated via hardhat-deploy):

**Component Deployment (Automated):**

1. **00_proxy_admin.ts** - Deploy GraphIssuanceProxyAdmin
   - Owned by governor address
   - Controls all issuance proxy upgrades

2. **01_issuance_allocator.ts** - Deploy IssuanceAllocator
   - Deploy implementation with GraphToken constructor parameter
   - Deploy TransparentUpgradeableProxy with atomic initialization
   - Initialize with governor address (receives GOVERNOR_ROLE)
   - Automatically creates default target at `address(0)` with zero allocation
   - Sets `lastDistributionBlock = block.number`

3. **02_pilot_allocation.ts** - Deploy PilotAllocation
   - Uses DirectAllocation implementation
   - Deployed as TransparentUpgradeableProxy
   - Optional test allocation target

4. **03_rewards_eligibility_oracle.ts** - Deploy RewardsEligibilityOracle
   - Deployed as TransparentUpgradeableProxy
   - Initialized with governor address

5. **04_verify_governance.ts** - Verify governance configuration
   - Verify governor has GOVERNOR_ROLE on all contracts
   - Verify pause guardian has PAUSE_ROLE (or will be granted)
   - Verify IssuanceAllocator configuration state
   - Verify ProxyAdmin ownership

6. **05_configure_issuance_allocator.ts** - Configure IssuanceAllocator
   - Set issuance rate (from RewardsManager if available)
   - Configure RewardsManager as self-minting target (if available)
   - Call `distributeIssuance()` to initialize distribution state
   - Grant PAUSE_ROLE to pause guardian

7. **06_deploy_reclaim_addresses.ts** - Deploy DirectAllocation instances
   - Deploy reclaim addresses as allocation targets
   - Each instance is a TransparentUpgradeableProxy using DirectAllocation implementation
   - Can be configured as allocation targets via `setTargetAllocation()`

**Post-Deployment Verification:**

```bash
# View deployment status
npx hardhat deploy --show-stack --network <network>

# Verify contracts on block explorer
npx hardhat etherscan-verify --network <network>
```

**Governance Integration (Cross-Package):**

The following steps require governance execution and are handled by the orchestration package (`packages/deploy`):

- **Configure RewardsManager** - `rewardsManager.setIssuanceAllocator(issuanceAllocatorAddress)`
- **Grant minter role** - `graphToken.grantRole(MINTER_ROLE, issuanceAllocator)`
- **Set default target** - `issuanceAllocator.setDefaultTarget(targetAddress)` (optional)

See `packages/deploy` for governance integration tasks:

```bash
# Generate Safe transaction batch for governance
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --rewards-manager-implementation <address> \
  --network <network>

# Verify governance executed integration
npx hardhat issuance:verify-integration --network <network>
```

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
