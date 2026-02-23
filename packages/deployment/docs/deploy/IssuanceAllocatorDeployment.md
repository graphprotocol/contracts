# IssuanceAllocator Deployment

This document describes the deployment sequence for IssuanceAllocator. For contract architecture, behavior, and technical details, see [IssuanceAllocator.md](../../../../issuance/contracts/allocate/IssuanceAllocator.md).

## Prerequisites

- GraphToken contract deployed
- RewardsManager upgraded with `setIssuanceAllocator()` function
- GraphIssuanceProxyAdmin deployed with protocol governance as owner

## Deployment Overview

The deployment strategy safely replicates existing issuance configuration during RewardsManager migration:

- Default target starts as `address(0)` (that will not be minted to), allowing initial configuration without minting to any targets
- Deployment uses atomic initialization via proxy constructor (prevents front-running)
- Deployment account performs initial configuration, then transfers control to governance
- Granting of minter role can be delayed until replication of initial configuration with upgraded RewardsManager is verified to allow seamless transition to use of IssuanceAllocator
- **Governance control**: This contract uses OpenZeppelin's TransparentUpgradeableProxy pattern (not custom GraphProxy). GraphIssuanceProxyAdmin (owned by protocol governance) controls upgrades, while GOVERNOR_ROLE controls operations. The same governance address should have both roles.

For the general governance-gated upgrade workflow, see [GovernanceWorkflow.md](../../../docs/GovernanceWorkflow.md).

## Deployment Sequence

### Step 1: Deploy and Initialize (deployment account)

**Script:** [01_deploy.ts](./01_deploy.ts)

- Deploy IssuanceAllocator implementation with GraphToken address
- Deploy TransparentUpgradeableProxy with implementation, GraphIssuanceProxyAdmin, and initialization data
- **Atomic initialization**: `initialize(deploymentAccountAddress)` called via proxy constructor
- Deployment account receives GOVERNOR_ROLE (temporary, for configuration)
- Automatically creates default target at `targetAddresses[0] = address(0)`
- Sets `lastDistributionBlock = block.number`
- **Security**: Front-running prevented by atomic deployment + initialization

### Step 2: Set Issuance Rate (deployment account)

**Script:** [02_configure.ts](./02_configure.ts)

- Query current rate from RewardsManager: `rate = rewardsManager.issuancePerBlock()`
- Call `setIssuancePerBlock(rate)` to replicate existing rate
- All issuance allocated to default target (`address(0)`)
- No tokens minted (default target cannot receive mints)

### Step 3: Assign RewardsManager Allocation (deployment account)

**Script:** [02_configure.ts](./02_configure.ts)

- Call `setTargetAllocation(rewardsManagerAddress, 0, issuancePerBlock)`
- `allocatorMintingRate = 0` (RewardsManager will self-mint)
- `selfMintingRate = issuancePerBlock` (RewardsManager receives 100% allocation)
- Default target automatically adjusts to zero allocation

### Step 4: Verify Configuration Before Transfer (deployment account)

**Script:** [02_configure.ts](./02_configure.ts)

- Verify contract is not paused (`paused()` returns false)
- Verify `getIssuancePerBlock()` returns expected rate (matches RewardsManager)
- Verify `getTargetAllocation(rewardsManager)` shows correct self-minting configuration
- Verify only two targets exist: `targetAddresses[0] = address(0)` and `targetAddresses[1] = rewardsManager`
- Verify default target is `address(0)` with zero allocation
- Contract is ready to transfer control to governance

### Step 5: Distribute Issuance (anyone - no role required)

**Script:** [02_configure.ts](./02_configure.ts)

- Call `distributeIssuance()` to bring contract to fully current state
- Updates `lastDistributionBlock` to current block
- Verifies distribution mechanism is functioning correctly
- No tokens minted (no minter role yet, all allocation to self-minting RM)

### Step 6: Set Pause Controls and Transfer Governance (deployment account)

**Script:** [03_transfer_governance.ts](./03_transfer_governance.ts)

- Grant PAUSE_ROLE to pause guardian (same account as used for RewardsManager pause control)
- Grant GOVERNOR_ROLE to actual governor address (protocol governance multisig)
- Revoke GOVERNOR_ROLE from deployment account (MUST grant to governance first, then revoke)
- **Note**: Upgrade control (via GraphIssuanceProxyAdmin) is separate from GOVERNOR_ROLE

### Step 7: Verify Deployment and Configuration (governor)

**Script:** [04_verify.ts](./04_verify.ts)

**Bytecode verification:**

- Verify deployed implementation bytecode matches expected contract

**Access control:**

- Verify governance address has GOVERNOR_ROLE
- Verify deployment account does NOT have GOVERNOR_ROLE
- Verify pause guardian has PAUSE_ROLE
- **Off-chain**: Review all RoleGranted events since deployment to verify no other addresses have GOVERNOR_ROLE or PAUSE_ROLE

**Pause state:**

- Verify contract is not paused (`paused()` returns false)

**Issuance rate:**

- Verify `getIssuancePerBlock()` matches RewardsManager rate exactly

**Target configuration:**

- Verify only two targets exist: `targetAddresses[0] = address(0)` and `targetAddresses[1] = rewardsManager`
- Verify default target is `address(0)` with zero allocation
- Verify `getTargetAllocation(rewardsManager)` shows correct self-minting allocation (100%)

**Proxy configuration:**

- Verify GraphIssuanceProxyAdmin controls the proxy
- Verify GraphIssuanceProxyAdmin owner is protocol governance

### Step 8: Configure RewardsManager (governor)

**Script:** [05_configure_rewards_manager.ts](./05_configure_rewards_manager.ts)

- Call `rewardsManager.setIssuanceAllocator(issuanceAllocatorAddress)`
- RewardsManager will now query IssuanceAllocator for its issuance rate
- RewardsManager continues to mint tokens itself (self-minting)

### Step 9: Grant Minter Role (governor, only when configuration verified)

**Script:** [06_grant_minter.ts](./06_grant_minter.ts)

- Grant minter role to IssuanceAllocator on Graph Token

### Step 10: Set Default Target (governor, optional, recommended)

**Script:** [07_set_default_target.ts](./07_set_default_target.ts)

- Call `setDefaultTarget()` to receive future unallocated issuance

## Normal Operation

After deployment:

1. Targets or external actors call `distributeIssuance()` periodically
2. Governor adjusts issuance rates as needed via `setIssuancePerBlock()`
3. Governor adds/removes/modifies targets via `setTargetAllocation()` overloads
4. Self-minting targets query their allocation via `getTargetIssuancePerBlock()`

## Emergency Scenarios

- **Gas limit issues**: Use pause, individual notifications, and `minDistributedBlock` parameters with `distributePendingIssuance()`
- **Target failures**: Use `forceTargetNoChangeNotificationBlock()` to skip notification, then remove problematic targets by setting both rates to 0
- **Configuration while paused**: Call `distributePendingIssuance(blockNumber)` first, then use `minDistributedBlock` parameter in setter functions

## L1 Bridge Integration

When `setIssuancePerBlock()` is called, the L1GraphTokenGateway's `updateL2MintAllowance()` function must be called to ensure the bridge can mint the correct amount of tokens on L2.

## See Also

- [IssuanceAllocator.md](../../../../issuance/contracts/allocate/IssuanceAllocator.md) - Contract architecture and technical details
- [GovernanceWorkflow.md](../../../docs/GovernanceWorkflow.md) - General governance-gated upgrade workflow
