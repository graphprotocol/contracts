# Rewards Conditions Test Plan

> **Status: DRAFT WIP** — Under review. Test steps and pass criteria may change.

> **Navigation**: [← Back to REO Testing](README.md) | [BaselineTestPlan](BaselineTestPlan.md) | [SubgraphDenialTestPlan](SubgraphDenialTestPlan.md)

Tests for the reclaim system, signal-related conditions, POI presentation paths, allocation lifecycle changes, and observability improvements introduced in the issuance upgrade.

These tests cover all reward conditions **except** `INDEXER_INELIGIBLE` (covered by [ReoTestPlan](ReoTestPlan.md)) and `SUBGRAPH_DENIED` (covered by [SubgraphDenialTestPlan](SubgraphDenialTestPlan.md)).

> All contract reads use `cast call`. All addresses must be **lowercase**. Replace placeholder addresses with actual deployed addresses for your network.

## Contract Addresses

| Contract                | Arbitrum Sepolia                             | Arbitrum One                                 |
| ----------------------- | -------------------------------------------- | -------------------------------------------- |
| RewardsManager (proxy)  | `0x1f49cae7669086c8ba53cc35d1e9f80176d67e79` | `0x971b9d3d0ae3eca029cab5ea1fb0f72c85e6a525` |
| SubgraphService (proxy) | `0xc24a3dac5d06d771f657a48b20ce1a671b78f26b` | `0xb2bb92d0de618878e438b55d5846cfecd9301105` |
| GraphToken (L2)         | `0xf8c05dcf59e8b28bfd5eed176c562bebcfc7ac04` | `0x9623063377ad1b27544c965ccd7342f7ea7e88c7` |
| Controller              | `0x9db3ee191681f092607035d9bda6e59fbeaca695` | `0x0a8491544221dd212964fbb96487467291b2c97e` |

### RPC

| Network          | RPC URL                                  |
| ---------------- | ---------------------------------------- |
| Arbitrum Sepolia | `https://sepolia-rollup.arbitrum.io/rpc` |

---

## Background

The issuance upgrade introduces a `RewardsCondition` system that classifies every situation where rewards cannot be distributed normally. Instead of silently dropping undistributable rewards, each condition has a defined handling path:

- **Reclaim**: Mint to a configured address (per-condition or default fallback)
- **Defer**: Preserve for later collection (snapshot not advanced)

This test plan validates the reclaim infrastructure, each condition's handling, and the new observability features.

---

## Prerequisites

- [Baseline tests](BaselineTestPlan.md) Cycles 1-7 pass
- Governor access for reclaim address configuration
- SAO or Governor access for `setMinimumSubgraphSignal()`
- At least two indexers with active allocations
- Access to subgraph deployments with varying signal levels

---

## Test Sequence Overview

| Cycle | Area                         | Tests     | Notes                                              |
| ----- | ---------------------------- | --------- | -------------------------------------------------- |
| 1     | Reclaim System Configuration | 1.1 - 1.5 | Governor access needed                             |
| 2     | Below-Minimum Signal         | 2.1 - 2.4 | Governor/SAO access; signal threshold changes      |
| 3     | Zero Allocated Tokens        | 3.1 - 3.3 | Requires subgraph with signal but no allocations   |
| 4     | POI Presentation Paths       | 4.1 - 4.5 | Requires mature and young allocations              |
| 5     | Allocation Lifecycle         | 5.1 - 5.3 | Resize and close operations                        |
| 6     | Observability                | 6.1 - 6.3 | Event and view function verification               |
| 7     | Zero Global Signal           | 7.1 - 7.2 | Difficult on shared testnet; may be unit-test only |

---

## Cycle 1: Reclaim System Configuration

### 1.1 Configure per-condition reclaim addresses

**Objective**: Set reclaim addresses for each condition and verify the routing.

**Steps**:

```bash
# Compute condition identifiers
NO_SIGNAL=$(cast keccak "NO_SIGNAL")
SUBGRAPH_DENIED=$(cast keccak "SUBGRAPH_DENIED")
BELOW_MINIMUM_SIGNAL=$(cast keccak "BELOW_MINIMUM_SIGNAL")
NO_ALLOCATED_TOKENS=$(cast keccak "NO_ALLOCATED_TOKENS")
STALE_POI=$(cast keccak "STALE_POI")
ZERO_POI=$(cast keccak "ZERO_POI")
CLOSE_ALLOCATION=$(cast keccak "CLOSE_ALLOCATION")
INDEXER_INELIGIBLE=$(cast keccak "INDEXER_INELIGIBLE")

# Set per-condition reclaim addresses (as Governor)
# Using a single address for simplicity; in production these may differ
cast send <REWARDS_MANAGER> "setReclaimAddress(bytes32,address)" $NO_SIGNAL <RECLAIM_ADDRESS> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

cast send <REWARDS_MANAGER> "setReclaimAddress(bytes32,address)" $BELOW_MINIMUM_SIGNAL <RECLAIM_ADDRESS> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

cast send <REWARDS_MANAGER> "setReclaimAddress(bytes32,address)" $NO_ALLOCATED_TOKENS <RECLAIM_ADDRESS> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

cast send <REWARDS_MANAGER> "setReclaimAddress(bytes32,address)" $STALE_POI <RECLAIM_ADDRESS> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

cast send <REWARDS_MANAGER> "setReclaimAddress(bytes32,address)" $ZERO_POI <RECLAIM_ADDRESS> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

cast send <REWARDS_MANAGER> "setReclaimAddress(bytes32,address)" $CLOSE_ALLOCATION <RECLAIM_ADDRESS> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

# Verify each
cast call <REWARDS_MANAGER> "getReclaimAddress(bytes32)(address)" $STALE_POI --rpc-url <RPC>
cast call <REWARDS_MANAGER> "getReclaimAddress(bytes32)(address)" $ZERO_POI --rpc-url <RPC>
cast call <REWARDS_MANAGER> "getReclaimAddress(bytes32)(address)" $CLOSE_ALLOCATION --rpc-url <RPC>
```

**Pass Criteria**:

- Each `setReclaimAddress` transaction succeeds
- `ReclaimAddressSet` event emitted for each
- `getReclaimAddress()` returns the correct address for each condition

---

### 1.2 Configure default reclaim address

**Objective**: Set the fallback reclaim address used when no per-condition address is configured.

**Steps**:

```bash
# Set default reclaim address (as Governor)
cast send <REWARDS_MANAGER> "setDefaultReclaimAddress(address)" <DEFAULT_RECLAIM_ADDRESS> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

# Verify
cast call <REWARDS_MANAGER> "getDefaultReclaimAddress()(address)" --rpc-url <RPC>
```

**Pass Criteria**:

- Transaction succeeds
- `DefaultReclaimAddressSet` event emitted
- `getDefaultReclaimAddress()` returns the configured address

---

### 1.3 Verify fallback routing: unconfigured condition uses default

**Objective**: A condition with no per-condition address should route to the default address.

**Steps**:

```bash
# Use a condition that does NOT have a per-condition address set
# (e.g., skip setting ALTRUISTIC_ALLOCATION in test 1.1)
ALTRUISTIC=$(cast keccak "ALTRUISTIC_ALLOCATION")

# Verify no per-condition address
cast call <REWARDS_MANAGER> "getReclaimAddress(bytes32)(address)" $ALTRUISTIC --rpc-url <RPC>
# Expected: 0x0000...

# The default address should catch this (verified by observing reclaim events when triggered)
cast call <REWARDS_MANAGER> "getDefaultReclaimAddress()(address)" --rpc-url <RPC>
```

**Pass Criteria**:

- Per-condition address = `0x0` (not set)
- Default address is configured (non-zero)
- When this condition is triggered, `RewardsReclaimed` event shows tokens going to default address

---

### 1.4 Unauthorized reclaim address change reverts

**Objective**: Only the Governor can set reclaim addresses.

**Steps**:

```bash
# Non-governor attempts to set reclaim address
cast send <REWARDS_MANAGER> "setReclaimAddress(bytes32,address)" $STALE_POI <RANDOM_ADDRESS> --rpc-url <RPC> --private-key <RANDOM_KEY>

# Non-governor attempts to set default reclaim address
cast send <REWARDS_MANAGER> "setDefaultReclaimAddress(address)" <RANDOM_ADDRESS> --rpc-url <RPC> --private-key <RANDOM_KEY>
```

**Pass Criteria**:

- Both transactions revert

---

### 1.5 Record baseline balances

**Objective**: Record GRT balances of all reclaim addresses for comparison during later tests.

**Steps**:

```bash
cast call <GRAPH_TOKEN> "balanceOf(address)(uint256)" <RECLAIM_ADDRESS> --rpc-url <RPC>
cast call <GRAPH_TOKEN> "balanceOf(address)(uint256)" <DEFAULT_RECLAIM_ADDRESS> --rpc-url <RPC>
```

**Pass Criteria**:

- Balances recorded for comparison

---

## Cycle 2: Below-Minimum Signal

### 2.1 Verify current minimum signal threshold

**Objective**: Check the current `minimumSubgraphSignal` value and identify subgraphs near the threshold.

**Steps**:

```bash
# Check current threshold
cast call <REWARDS_MANAGER> "minimumSubgraphSignal()(uint256)" --rpc-url <RPC>
```

**Verification Query** (find subgraphs near the threshold):

```graphql
{
  subgraphDeployments(orderBy: signalledTokens, orderDirection: asc, where: { signalledTokens_gt: 0 }) {
    ipfsHash
    signalledTokens
    stakedTokens
    indexingRewardAmount
  }
}
```

**Pass Criteria**:

- Threshold value known
- At least one subgraph identified that is close to (or can be made to fall below) the threshold

---

### 2.2 Raise threshold to trigger BELOW_MINIMUM_SIGNAL

**Objective**: Increase `minimumSubgraphSignal` so that a target subgraph falls below the threshold, then verify rewards are reclaimed.

> **Important**: Before changing the threshold, call `onSubgraphSignalUpdate()` on affected subgraphs to snapshot accumulators under the current rules. This prevents retroactive application over a long period.

**Steps**:

```bash
# Record accumulator for target subgraph
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <LOW_SIGNAL_DEPLOYMENT_ID> --rpc-url <RPC>

# Snapshot accumulators before threshold change
cast send <REWARDS_MANAGER> "onSubgraphSignalUpdate(bytes32)" <LOW_SIGNAL_DEPLOYMENT_ID> --rpc-url <RPC> --private-key <ANY_KEY>

# Raise threshold (as Governor or SAO)
cast send <REWARDS_MANAGER> "setMinimumSubgraphSignal(uint256)" <NEW_HIGHER_THRESHOLD> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

# Verify threshold changed
cast call <REWARDS_MANAGER> "minimumSubgraphSignal()(uint256)" --rpc-url <RPC>
```

**Pass Criteria**:

- Threshold changed successfully
- Target subgraph signal is now below the new threshold

---

### 2.3 Accumulator freezes for below-threshold subgraph

**Objective**: After the threshold increase, the below-threshold subgraph's accumulators should freeze and new rewards should be reclaimed.

**Steps**:

```bash
# Wait some time, then check accumulators
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <LOW_SIGNAL_DEPLOYMENT_ID> --rpc-url <RPC>

# Trigger accumulator update to process reclaim
cast send <REWARDS_MANAGER> "onSubgraphSignalUpdate(bytes32)" <LOW_SIGNAL_DEPLOYMENT_ID> --rpc-url <RPC> --private-key <ANY_KEY>

# Check for RewardsReclaimed events
RECLAIM_EVENT_SIG=$(cast sig-event "RewardsReclaimed(bytes32,uint256,address,address,bytes32)")
cast logs --from-block <THRESHOLD_CHANGE_BLOCK> --to-block latest --address <REWARDS_MANAGER> --topic0 $RECLAIM_EVENT_SIG --rpc-url <RPC>
```

**Pass Criteria**:

- `accRewardsForSubgraph` frozen (not increasing)
- `RewardsReclaimed` event with reason = `BELOW_MINIMUM_SIGNAL`
- Reclaim address balance increased

---

### 2.4 Restore threshold and verify resumption

**Objective**: Lower the threshold back so the subgraph is above minimum. Accumulators should resume.

**Steps**:

```bash
# Snapshot before change
cast send <REWARDS_MANAGER> "onSubgraphSignalUpdate(bytes32)" <LOW_SIGNAL_DEPLOYMENT_ID> --rpc-url <RPC> --private-key <ANY_KEY>

# Restore threshold
cast send <REWARDS_MANAGER> "setMinimumSubgraphSignal(uint256)" <ORIGINAL_THRESHOLD> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

# Wait, then check accumulators
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <LOW_SIGNAL_DEPLOYMENT_ID> --rpc-url <RPC>
```

**Pass Criteria**:

- Threshold restored to original value
- `accRewardsForSubgraph` resumes increasing
- Allocations on this subgraph can claim rewards again

---

## Cycle 3: Zero Allocated Tokens

### 3.1 Identify subgraph with signal but no allocations

**Objective**: Find or create a subgraph deployment that has curation signal but zero allocated tokens.

**Verification Query**:

```graphql
{
  subgraphDeployments(where: { signalledTokens_gt: 0, stakedTokens: 0 }) {
    ipfsHash
    signalledTokens
    stakedTokens
  }
}
```

Alternatively, close all allocations on a test subgraph while leaving signal intact.

**Pass Criteria**:

- Subgraph deployment identified with `signalledTokens > 0` and `stakedTokens = 0`

---

### 3.2 Verify NO_ALLOCATED_TOKENS reclaim

**Objective**: When a subgraph has signal but no allocations, rewards for that signal share are reclaimed as `NO_ALLOCATED_TOKENS`.

**Steps**:

```bash
# Trigger accumulator update for the zero-allocation subgraph
cast send <REWARDS_MANAGER> "onSubgraphAllocationUpdate(bytes32)" <ZERO_ALLOC_DEPLOYMENT_ID> --rpc-url <RPC> --private-key <ANY_KEY>

# Check for RewardsReclaimed events
NO_ALLOCATED_TOKENS=$(cast keccak "NO_ALLOCATED_TOKENS")
RECLAIM_EVENT_SIG=$(cast sig-event "RewardsReclaimed(bytes32,uint256,address,address,bytes32)")
cast logs --from-block <TX_BLOCK> --to-block <TX_BLOCK> --address <REWARDS_MANAGER> --topic0 $RECLAIM_EVENT_SIG --rpc-url <RPC>
```

**Pass Criteria**:

- `RewardsReclaimed` event with reason = `NO_ALLOCATED_TOKENS`
- Reclaim address received tokens

---

### 3.3 Allocations resume from stored baseline

**Objective**: When a new allocation is created on a subgraph that previously had zero allocations, `accRewardsPerAllocatedToken` resumes from its stored value rather than resetting to zero.

**Steps**:

```bash
# Record current accRewardsPerAllocatedToken
cast call <REWARDS_MANAGER> "getAccRewardsPerAllocatedToken(bytes32)(uint256,uint256)" <ZERO_ALLOC_DEPLOYMENT_ID> --rpc-url <RPC>

# Create allocation
graph indexer allocations create <ZERO_ALLOC_DEPLOYMENT_IPFS> <AMOUNT>

# Check accRewardsPerAllocatedToken after creation
cast call <REWARDS_MANAGER> "getAccRewardsPerAllocatedToken(bytes32)(uint256,uint256)" <ZERO_ALLOC_DEPLOYMENT_ID> --rpc-url <RPC>
```

**Pass Criteria**:

- New allocation created successfully
- `accRewardsPerAllocatedToken` not reset to zero (maintains stored value)
- New allocation starts accruing from current accumulator value

---

## Cycle 4: POI Presentation Paths

The issuance upgrade introduces three distinct POI presentation outcomes: **claim**, **reclaim**, and **defer**. Each condition routes to one of these paths.

### 4.1 Normal claim path (NONE condition)

**Objective**: Verify that a valid POI on a non-denied, signal-above-threshold, non-stale allocation claims rewards normally. The `POIPresented` event should show `condition = bytes32(0)`.

**Prerequisites**: Active allocation, open 2+ epochs, not stale, on a non-denied subgraph with signal above threshold.

**Steps**:

```bash
# Confirm allocation is healthy
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID> --rpc-url <RPC>
# Expected: non-zero

# Close allocation (presents POI and claims)
graph indexer allocations close <ALLOCATION_ID>
```

**Verification**: Check transaction for `POIPresented` event:

```bash
POI_EVENT_SIG=$(cast sig-event "POIPresented(address,address,bytes32,bytes32,bytes,bytes32)")
cast logs --from-block <TX_BLOCK> --to-block <TX_BLOCK> --address <SUBGRAPH_SERVICE> --topic0 $POI_EVENT_SIG --rpc-url <RPC>
```

**Pass Criteria**:

- `POIPresented` event emitted with `condition = 0x00...00` (NONE)
- `indexingRewards` non-zero
- Normal `HorizonRewardsAssigned` event emitted

---

### 4.2 Reclaim path: STALE_POI

**Objective**: When an allocation is stale (no POI presented within `maxPOIStaleness`), presenting a POI reclaims rewards instead of claiming them.

**Prerequisites**: An allocation that has not had a POI presented for longer than `maxPOIStaleness`.

**Steps**:

```bash
# Check maxPOIStaleness
cast call <SUBGRAPH_SERVICE> "maxPOIStaleness()(uint256)" --rpc-url <RPC>

# Find or wait for a stale allocation
# (Let an allocation go without POI presentation for maxPOIStaleness seconds)

# Close the stale allocation
graph indexer allocations close <STALE_ALLOCATION_ID>
```

**Pass Criteria**:

- `POIPresented` event emitted with `condition = keccak256("STALE_POI")`
- `indexingRewards` = 0 (rewards not claimed by indexer)
- `RewardsReclaimed` event with reason = `STALE_POI`
- Reclaim address received the tokens
- Allocation snapshot advanced (pending rewards cleared)

---

### 4.3 Reclaim path: ZERO_POI

**Objective**: Submitting a zero POI (`bytes32(0)`) reclaims rewards.

**Prerequisites**: Active allocation, mature (2+ epochs).

**Steps**:

```bash
# Close allocation with explicit zero POI
graph indexer allocations close <ALLOCATION_ID> --poi 0x0000000000000000000000000000000000000000000000000000000000000000
```

**Pass Criteria**:

- `POIPresented` event emitted with `condition = keccak256("ZERO_POI")`
- `indexingRewards` = 0
- `RewardsReclaimed` event with reason = `ZERO_POI`
- Reclaim address received the tokens
- Allocation snapshot advanced (pending rewards cleared)

---

### 4.4 Defer path: ALLOCATION_TOO_YOUNG

**Objective**: Presenting a POI for an allocation created in the current epoch defers — returns 0 without advancing the snapshot, preserving rewards for later.

**Prerequisites**: Create a new allocation and attempt POI presentation in the same epoch.

**Steps**:

```bash
# Create allocation
graph indexer allocations create <DEPLOYMENT_IPFS_HASH> <AMOUNT>

# Immediately attempt POI presentation (same epoch)
# (via manual cast send or indexer agent action)
```

**Pass Criteria**:

- `POIPresented` event emitted with `condition = keccak256("ALLOCATION_TOO_YOUNG")`
- Returns 0 rewards
- **Critical**: Allocation snapshot NOT advanced (rewards preserved for later)
- Allocation remains open and healthy
- After waiting for epoch boundary: normal claim succeeds

---

### 4.5 POI presentation always updates timestamp

**Objective**: Verify that the POI presentation timestamp is recorded regardless of the condition outcome. This means even reclaimed or deferred presentations reset the staleness clock.

**Steps**:

1. Present a POI that results in a defer (e.g., too young)
2. Check that the staleness timer reset
3. Present a POI that results in a reclaim (e.g., zero POI)
4. Check that the staleness timer reset

**Pass Criteria**:

- Staleness timer resets on every POI presentation, regardless of outcome
- An allocation that regularly presents POIs (even deferred ones) does not become stale

---

## Cycle 5: Allocation Lifecycle

### 5.1 Allocation resize reclaims stale rewards

**Objective**: Resizing a stale allocation reclaims pending rewards as `STALE_POI` and clears them. This prevents stale allocations from silently accumulating rewards through repeated resizes.

**Prerequisites**: An allocation that is stale (no POI for `maxPOIStaleness`). The allocation has pending rewards from before it went stale.

**Steps**:

```bash
# Confirm allocation is stale
# (Check last POI timestamp vs maxPOIStaleness)

# Check pending rewards before resize
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <STALE_ALLOCATION_ID> --rpc-url <RPC>

# Resize the allocation
graph indexer allocations reallocate <STALE_ALLOCATION_ID> <NEW_AMOUNT>
```

**Pass Criteria**:

- `RewardsReclaimed` event with reason = `STALE_POI`
- Pending rewards cleared (not carried forward through resize)
- Reclaim address received the stale rewards
- New allocation starts fresh (no carried-over stale rewards)

---

### 5.2 Allocation resize does NOT reclaim for non-stale allocation

**Objective**: Resizing a healthy (non-stale) allocation should accumulate pending rewards normally, not reclaim them.

**Prerequisites**: Active, non-stale allocation with pending rewards.

**Steps**:

```bash
# Check pending rewards
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <HEALTHY_ALLOCATION_ID> --rpc-url <RPC>

# Resize
graph indexer allocations reallocate <HEALTHY_ALLOCATION_ID> <NEW_AMOUNT>

# Check that no STALE_POI reclaim event occurred
```

**Pass Criteria**:

- No `RewardsReclaimed` event with reason = `STALE_POI`
- Pending rewards accumulated into `accRewardsPending` (carried through resize)
- New allocation can claim accumulated rewards on next close

---

### 5.3 Allocation close reclaims uncollected rewards

**Objective**: When an allocation is closed, any uncollected rewards are reclaimed as `CLOSE_ALLOCATION` before the allocation is finalized. This prevents rewards from being permanently lost on close.

**Prerequisites**: An allocation with uncollected rewards (e.g., the indexer has not presented a POI recently, or rewards accumulated since last POI).

**Steps**:

```bash
# Record reclaim address balance
cast call <GRAPH_TOKEN> "balanceOf(address)(uint256)" <RECLAIM_ADDRESS> --rpc-url <RPC>

# Close allocation
graph indexer allocations close <ALLOCATION_ID>

# Check for CLOSE_ALLOCATION reclaim
CLOSE_ALLOC=$(cast keccak "CLOSE_ALLOCATION")
RECLAIM_EVENT_SIG=$(cast sig-event "RewardsReclaimed(bytes32,uint256,address,address,bytes32)")
cast logs --from-block <TX_BLOCK> --to-block <TX_BLOCK> --address <REWARDS_MANAGER> --topic0 $RECLAIM_EVENT_SIG --rpc-url <RPC>

# Check reclaim address balance increased
cast call <GRAPH_TOKEN> "balanceOf(address)(uint256)" <RECLAIM_ADDRESS> --rpc-url <RPC>
```

**Pass Criteria**:

- `RewardsReclaimed` event with reason = `CLOSE_ALLOCATION`
- Reclaim address balance increased
- Rewards not permanently lost (either claimed by indexer via POI or reclaimed to protocol)

---

## Cycle 6: Observability

### 6.1 POIPresented event emitted on every presentation

**Objective**: Verify that every POI presentation emits a `POIPresented` event with the determined condition, regardless of outcome.

**Steps**:

Collect events across multiple scenarios from previous cycles:

```bash
POI_EVENT_SIG=$(cast sig-event "POIPresented(address,address,bytes32,bytes32,bytes,bytes32)")

# Query all POIPresented events from the test session
cast logs --from-block <SESSION_START_BLOCK> --to-block latest --address <SUBGRAPH_SERVICE> --topic0 $POI_EVENT_SIG --rpc-url <RPC>
```

**Pass Criteria**:

- Every POI presentation (from Cycles 4-5) has a corresponding `POIPresented` event
- Each event contains:
  - `indexer`: correct indexer address
  - `allocationId`: correct allocation
  - `subgraphDeploymentId`: correct deployment
  - `poi`: the submitted POI value
  - `condition`: matches the expected outcome (NONE, STALE_POI, ZERO_POI, ALLOCATION_TOO_YOUNG, SUBGRAPH_DENIED)

---

### 6.2 RewardsReclaimed events include full context

**Objective**: Verify that `RewardsReclaimed` events contain all necessary context for off-chain accounting.

**Steps**:

```bash
RECLAIM_EVENT_SIG=$(cast sig-event "RewardsReclaimed(bytes32,uint256,address,address,bytes32)")

# Query all RewardsReclaimed events from the test session
cast logs --from-block <SESSION_START_BLOCK> --to-block latest --address <REWARDS_MANAGER> --topic0 $RECLAIM_EVENT_SIG --rpc-url <RPC>
```

**Pass Criteria**:

- Each `RewardsReclaimed` event contains:
  - `reason`: valid `RewardsCondition` identifier (not zero)
  - `amount`: non-zero GRT amount
  - `indexer`: address of the affected indexer (or zero for subgraph-level reclaims)
  - `allocationID`: address of the affected allocation (or zero for subgraph-level reclaims)
  - `subgraphDeploymentID`: deployment hash

---

### 6.3 View functions reflect frozen state accurately

**Objective**: Verify that `getAccRewardsForSubgraph()`, `getAccRewardsPerAllocatedToken()`, and `getRewards()` correctly return frozen values for non-claimable subgraphs and growing values for claimable ones.

**Steps**:

```bash
# For a denied subgraph (if one is still denied from SubgraphDenialTestPlan)
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <DENIED_DEPLOYMENT> --rpc-url <RPC>
# Wait, read again — should be unchanged

# For a below-threshold subgraph (if one is still below from Cycle 2)
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <BELOW_THRESHOLD_DEPLOYMENT> --rpc-url <RPC>
# Wait, read again — should be unchanged

# For a healthy subgraph (control)
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <HEALTHY_DEPLOYMENT> --rpc-url <RPC>
# Wait, read again — should have increased

# getRewards for allocation on non-claimable subgraph
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ON_NON_CLAIMABLE> --rpc-url <RPC>
```

**Pass Criteria**:

- Non-claimable subgraphs: view functions return frozen (non-increasing) values
- Claimable subgraphs: view functions return growing values
- `getRewards()` for allocations on non-claimable subgraphs returns a frozen value
- Pre-existing `accRewardsPending` from prior resizes is still included in `getRewards()` even for non-claimable subgraphs

---

## Cycle 7: Zero Global Signal

> **Note**: These tests require zero total curation signal across the entire network, which is impractical on a shared testnet. They are documented here for completeness and should be validated via Foundry unit tests or on a dedicated test network.

### 7.1 NO_SIGNAL detection

**Objective**: When total curation signal across all subgraphs is zero, issuance during that period should be reclaimed as `NO_SIGNAL`.

**Steps** (dedicated testnet only):

```bash
# Remove all curation signal from all subgraphs
# (Only feasible on a private testnet)

# Wait for blocks to pass (issuance accrues to nobody)

# Trigger accumulator update
cast send <REWARDS_MANAGER> "updateAccRewardsPerSignal()" --rpc-url <RPC> --private-key <ANY_KEY>

# Check for RewardsReclaimed with NO_SIGNAL
NO_SIGNAL=$(cast keccak "NO_SIGNAL")
RECLAIM_EVENT_SIG=$(cast sig-event "RewardsReclaimed(bytes32,uint256,address,address,bytes32)")
cast logs --from-block <TX_BLOCK> --to-block <TX_BLOCK> --address <REWARDS_MANAGER> --topic0 $RECLAIM_EVENT_SIG --rpc-url <RPC>
```

**Pass Criteria**:

- `RewardsReclaimed` event with reason = `NO_SIGNAL`
- Reclaimed amount corresponds to issuance during zero-signal period
- `getNewRewardsPerSignal()` still returns claimable portion only (unchanged from legacy behavior)

---

### 7.2 Signal restoration resumes normal distribution

**Objective**: After signal is restored, rewards distribution resumes normally.

**Steps** (dedicated testnet only):

1. Add curation signal to a subgraph
2. Verify `getNewRewardsPerSignal()` returns non-zero
3. Verify accumulators resume growing

**Pass Criteria**:

- Rewards flow normally after signal restoration
- No rewards from the zero-signal period leak into the normal distribution

---

## Post-Testing Checklist

- [ ] Reclaim addresses verified for all conditions
- [ ] `minimumSubgraphSignal` restored to original value
- [ ] No subgraphs left in unintended denied state
- [ ] Reclaim address balances reconciled with expected amounts
- [ ] All `POIPresented` events collected and categorized
- [ ] Results documented in test tracker

---

## Test Summary

| Condition                | Test(s)   | Cycle | Testnet Feasibility    |
| ------------------------ | --------- | ----- | ---------------------- |
| Reclaim infrastructure   | 1.1 - 1.5 | 1     | Full                   |
| `BELOW_MINIMUM_SIGNAL`   | 2.1 - 2.4 | 2     | Full                   |
| `NO_ALLOCATED_TOKENS`    | 3.1 - 3.3 | 3     | Full                   |
| `NONE` (normal claim)    | 4.1       | 4     | Full                   |
| `STALE_POI`              | 4.2       | 4     | Full (wait needed)     |
| `ZERO_POI`               | 4.3       | 4     | Full                   |
| `ALLOCATION_TOO_YOUNG`   | 4.4       | 4     | Full                   |
| POI timestamp behavior   | 4.5       | 4     | Full                   |
| Stale resize reclaim     | 5.1 - 5.2 | 5     | Full (wait needed)     |
| `CLOSE_ALLOCATION`       | 5.3       | 5     | Full                   |
| `POIPresented` event     | 6.1       | 6     | Full                   |
| `RewardsReclaimed` event | 6.2       | 6     | Full                   |
| View function freeze     | 6.3       | 6     | Full                   |
| `NO_SIGNAL`              | 7.1 - 7.2 | 7     | Dedicated testnet only |

---

## Related Documentation

- [← Back to REO Testing](README.md)
- [SubgraphDenialTestPlan.md](SubgraphDenialTestPlan.md) — Subgraph denial behavior tests
- [BaselineTestPlan.md](BaselineTestPlan.md) — Baseline operational tests (run first)
- [ReoTestPlan.md](ReoTestPlan.md) — REO eligibility tests

---

_Derived from issuance upgrade behavior changes. Source: [RewardsBehaviourChanges.md](/docs/RewardsBehaviourChanges.md), [RewardConditions.md](/docs/RewardConditions.md). Contracts: `packages/contracts/contracts/rewards/RewardsManager.sol`, `packages/subgraph-service/contracts/utilities/AllocationManager.sol`._
