# Reward Conditions: Collection and Reclaim Reference

Quick reference for all reward conditions and how they are handled across RewardsManager and AllocationManager.

## Summary Table

| Condition              | Identifier                          | Handled By        | Action                    | Rewards Outcome                        |
| ---------------------- | ----------------------------------- | ----------------- | ------------------------- | -------------------------------------- |
| `NONE`                 | `bytes32(0)`                        | —                 | Normal path               | Claimed by indexer                     |
| `NO_SIGNAL`            | `keccak256("NO_SIGNAL")`            | RewardsManager    | Reclaim                   | To reclaim address                     |
| `SUBGRAPH_DENIED`      | `keccak256("SUBGRAPH_DENIED")`      | Both              | Reclaim (RM) / Defer (AM) | New: reclaimed; Uncollected: preserved |
| `BELOW_MINIMUM_SIGNAL` | `keccak256("BELOW_MINIMUM_SIGNAL")` | RewardsManager    | Reclaim                   | To reclaim address                     |
| `NO_ALLOCATED_TOKENS`  | `keccak256("NO_ALLOCATED_TOKENS")`  | RewardsManager    | Reclaim                   | To reclaim address                     |
| `INDEXER_INELIGIBLE`   | `keccak256("INDEXER_INELIGIBLE")`   | RewardsManager    | Reclaim                   | To reclaim address                     |
| `STALE_POI`            | `keccak256("STALE_POI")`            | AllocationManager | Reclaim                   | To reclaim address                     |
| `ZERO_POI`             | `keccak256("ZERO_POI")`             | AllocationManager | Reclaim                   | To reclaim address                     |
| `ALLOCATION_TOO_YOUNG` | `keccak256("ALLOCATION_TOO_YOUNG")` | AllocationManager | Defer                     | Preserved for later                    |
| `CLOSE_ALLOCATION`     | `keccak256("CLOSE_ALLOCATION")`     | AllocationManager | Reclaim                   | To reclaim address                     |

## Reward Distribution Levels

Rewards flow through three levels, with reclaim possible at each:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Level 0: Global Issuance                                           │
│  ─────────────────────────────────────────────────────────────────  │
│  updateAccRewardsPerSignal()                                        │
│                                                                     │
│  Reclaim: NO_SIGNAL (when total signalled tokens = 0)               │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ proportional to signal
┌─────────────────────────────────────────────────────────────────────┐
│  Level 1: Subgraph                                                  │
│  ─────────────────────────────────────────────────────────────────  │
│  onSubgraphSignalUpdate() / onSubgraphAllocationUpdate()            │
│                                                                     │
│  Reclaim: SUBGRAPH_DENIED, BELOW_MINIMUM_SIGNAL, NO_ALLOCATED_TOKENS      │
│                                                                     │
│  Behavior:                                                          │
│  - accRewardsForSubgraph only increases when claimable              │
│  - accRewardsPerAllocatedToken only increases when claimable        │
│  - Non-claimable rewards are reclaimed immediately, not stored      │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ proportional to allocated tokens
┌─────────────────────────────────────────────────────────────────────┐
│  Level 2: Allocation                                                │
│  ─────────────────────────────────────────────────────────────────  │
│  takeRewards() / reclaimRewards() / _presentPoi()                   │
│                                                                     │
│  Reclaim: INDEXER_INELIGIBLE (at takeRewards)                       │
│           STALE_POI, ZERO_POI, CLOSE_ALLOCATION (at _presentPoi)    │
│                                                                     │
│  Defer:   SUBGRAPH_DENIED, ALLOCATION_TOO_YOUNG (preserves state)   │
└─────────────────────────────────────────────────────────────────────┘
```

## Condition Details

### Global Level (RewardsManager.updateAccRewardsPerSignal)

#### NO_SIGNAL

- **Trigger**: Total signalled tokens across all subgraphs = 0
- **Effect**: Issuance cannot be distributed proportionally to signal
- **Handling**: Reclaim to configured address (or drop if unconfigured)

### Subgraph Level (RewardsManager.onSubgraphAllocationUpdate)

#### SUBGRAPH_DENIED

- **Trigger**: `isDenied(subgraphDeploymentId)` returns true
- **Effect**: `accRewardsPerAllocatedToken` stops increasing
- **Handling**: New rewards reclaimed; accumulator frozen (uncollected rewards preserved)
- **Note**: If no SUBGRAPH_DENIED reclaim address AND signal < minimum, reclaims as BELOW_MINIMUM_SIGNAL instead

**Reward disposition by period:**

| Period        | Disposition                                              |
| ------------- | -------------------------------------------------------- |
| Before denial | Claimable after undeny                                   |
| During denial | Reclaimed to protocol (or dropped if no reclaim address) |
| Post-undeny   | Claimable normally                                       |

**Effect on allocations:**

- _Existing allocations_: Uncollected rewards preserved (accumulator frozen, snapshot unchanged); cannot claim while denied; claimable after undeny
- _New allocations (created while denied)_: Start with frozen baseline; only earn rewards after undeny
- _POI presentation_: Indexers should continue presenting POIs to prevent staleness (returns 0 but maintains allocation health)

**Edge cases:**

| Scenario                           | Behavior                                                  |
| ---------------------------------- | --------------------------------------------------------- |
| All allocations close while denied | Frozen state preserved; new allocations use that baseline |
| Redundant deny/undeny calls        | No state change (idempotent)                              |
| Zero reclaim address               | Denial-period rewards dropped (never minted)              |

#### BELOW_MINIMUM_SIGNAL

- **Trigger**: Subgraph signal < `minimumSubgraphSignal` (and not denied)
- **Effect**: `accRewardsPerAllocatedToken` stops increasing
- **Handling**: Rewards reclaimed to configured address

#### NO_ALLOCATED_TOKENS

- **Trigger**: Subgraph has signal but zero allocated tokens
- **Effect**: Rewards cannot be distributed to allocations
- **Handling**: Reclaim to configured address
- **Note**: Triggered when condition is NONE but no allocations exist, or when original condition has no reclaim address

### Allocation Level (RewardsManager.takeRewards)

#### INDEXER_INELIGIBLE

- **Trigger**: `eligibilityOracle.isEligible(indexer)` returns false at claim time
- **Effect**: Indexer cannot claim earned rewards
- **Handling**: Rewards reclaimed to configured address
- **Precedence**: SUBGRAPH_DENIED takes precedence if both apply

### Allocation Level (AllocationManager.\_presentPoi)

Conditions checked in order (first match wins):

#### STALE_POI

- **Trigger**: `maxPOIStaleness` < Time since last POI
- **Effect**: Allocation locked out due to inactivity
- **Handling**: Rewards reclaimed; allocation snapshotted; pending cleared

#### ZERO_POI

- **Trigger**: POI submitted is `bytes32(0)`
- **Effect**: No proof of indexing work provided
- **Handling**: Rewards reclaimed; allocation snapshotted; pending cleared

#### ALLOCATION_TOO_YOUNG

- **Trigger**: `currentEpoch <= allocation.createdAtEpoch`
- **Effect**: Allocation hasn't existed for a full epoch
- **Handling**: **Deferred** (returns 0, no snapshot update, rewards preserved)

#### SUBGRAPH_DENIED (soft deny)

- **Trigger**: `isDenied(subgraphDeploymentId)` at POI presentation
- **Effect**: Cannot claim while denied
- **Handling**: **Deferred** (returns 0, no snapshot update, uncollected rewards preserved)

#### CLOSE_ALLOCATION

- **Trigger**: Allocation being closed (force or normal)
- **Effect**: Uncollected rewards cannot go to indexer
- **Handling**: Rewards reclaimed; allocation snapshotted

## Action Types

### Reclaim

Rewards are minted to a configured reclaim address:

1. Try reason-specific: `reclaimAddresses[condition]`
2. Fallback: `defaultReclaimAddress`
3. If neither configured: rewards dropped (not minted)

Emits `RewardsReclaimed(reason, rewards, indexer, allocationId, subgraphDeploymentId)`

### Defer

Rewards are preserved for later collection:

- Returns 0 without modifying allocation state
- No snapshot update (preserves claim position)
- Allows claiming when condition clears

### Claim (Normal)

Rewards minted to rewards issuer for distribution:

- Emits `HorizonRewardsAssigned`
- Allocation snapshotted to prevent double-claim
- Pending rewards cleared

## Reclaim Address Configuration

```solidity
// Governor-only functions
setReclaimAddress(bytes32 reason, address newAddress)  // Per-condition
setDefaultReclaimAddress(address newAddress)           // Fallback

// Example configuration
reclaimAddresses[SUBGRAPH_DENIED] = treasuryAddress;
reclaimAddresses[INDEXER_INELIGIBLE] = treasuryAddress;
reclaimAddresses[NO_SIGNAL] = treasuryAddress;
defaultReclaimAddress = treasuryAddress;  // Catch-all
```

**Important**: Changes apply retroactively to all future reclaims.

## Parameter Changes: minimumSubgraphSignal

### Retroactive Application Risk

When `minimumSubgraphSignal` is changed via `setMinimumSubgraphSignal()`, existing subgraphs are NOT automatically updated. When subgraphs are later updated (via signal/allocation changes), the **current** threshold is applied to ALL pending rewards since their last update, regardless of historical threshold values.

**Impact:**

| Change Direction    | Effect                                                                   |
| ------------------- | ------------------------------------------------------------------------ |
| Threshold increases | Pending rewards on previously eligible subgraphs are reclaimed           |
| Threshold decreases | Previously ineligible subgraphs retroactively accumulate pending rewards |

### Required Mitigation Process

To prevent retroactive application to long historical periods:

1. **Communicate** the planned threshold change with a specific future date
2. **Wait** - notice period allows participants to adjust signal if desired
3. **Identify** affected subgraphs off-chain (those crossing the threshold)
4. **Call** `onSubgraphSignalUpdate()` for all affected subgraphs to accumulate pending rewards under current eligibility rules
5. **Execute** threshold change via `setMinimumSubgraphSignal()` (promptly after step 4, ideally same block)

**Responsibility:** Governance handles steps 3-5; participants may optionally adjust signal in step 2.

For implementation details, see NatSpec documentation on `RewardsManager.setMinimumSubgraphSignal()`.

## Key Behaviors

### Snapshot Updates

| Action       | Updates Snapshot | Clears Pending |
| ------------ | ---------------- | -------------- |
| Claim (NONE) | Yes              | Yes            |
| Reclaim      | Yes              | Yes            |
| Defer        | No               | No             |

### Accumulator Behavior When Not Claimable

| Field                         | Behavior                                       |
| ----------------------------- | ---------------------------------------------- |
| `accRewardsForSubgraph`       | Does NOT increase (rewards reclaimed directly) |
| `accRewardsPerAllocatedToken` | Does NOT increase (rewards not distributed)    |
| New rewards                   | Reclaimed immediately to configured address    |
| Pre-existing stored rewards   | Still shown as distributable in view functions |

## Related Documentation

- [RewardAccountingSafety.md](./RewardAccountingSafety.md) - Safety mechanisms and invariants
