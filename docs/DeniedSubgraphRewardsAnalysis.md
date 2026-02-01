# Denied Subgraph Rewards - Implementation Analysis

## Overview

This document analyzes the implementation that prevents indexers from claiming rewards earned during a subgraph's denied period, while allowing pre-denial rewards to be collected after undeny.

## Key Changes

### 1. `_setDenied()` (RewardsManager.sol)

```solidity
function _setDenied(bytes32 subgraphDeploymentId, bool deny) private {
  onSubgraphAllocationUpdate(subgraphDeploymentId); // Snapshot/reclaim BEFORE state change

  bool stateChange = deny == (denylist[subgraphDeploymentId] == 0);
  if (stateChange) {
    uint256 sinceBlock = deny ? block.number : 0;
    denylist[subgraphDeploymentId] = sinceBlock;
    emit RewardsDenylistUpdated(subgraphDeploymentId, sinceBlock);
  }
}
```

Calls `onSubgraphAllocationUpdate()` **before** changing denylist state, ensuring:

- On deny: snapshots current rewards state while `isDenied()` = false
- On undeny: reclaims remaining denied-period rewards while `isDenied()` = true

**Idempotency guard:** The `stateChange` check ensures that redundant calls are no-ops:

- Calling `setDenied(id, true)` when already denied does not update `denylist` or emit `RewardsDenylistUpdated`
- Calling `setDenied(id, false)` when already not denied does not update `denylist` or emit `RewardsDenylistUpdated`
- In both cases, `onSubgraphAllocationUpdate()` is still called (snapshot/reclaim still occurs), but the denylist state itself is unchanged
- This prevents the block number from being overwritten on redundant deny calls (which would lose the original deny timestamp)

### 2. `onSubgraphAllocationUpdate()` (RewardsManager.sol)

```solidity
function onSubgraphAllocationUpdate(bytes32 _subgraphDeploymentID) public override returns (uint256) {
    Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];
    (uint256 accRewardsPerAllocatedToken, uint256 accRewardsForSubgraph) = getAccRewardsPerAllocatedToken(
        _subgraphDeploymentID
    );

    if (isDenied(_subgraphDeploymentID)) {
        // Reclaim new rewards instead of crediting to allocators
        if (subgraph.accRewardsForSubgraphSnapshot < accRewardsForSubgraph)
            _reclaimRewards(RewardsCondition.SUBGRAPH_DENIED,
                accRewardsForSubgraph - subgraph.accRewardsForSubgraphSnapshot, ...);
    } else {
        subgraph.accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
    }
    subgraph.accRewardsForSubgraphSnapshot = accRewardsForSubgraph;
    return subgraph.accRewardsPerAllocatedToken;
}
```

When denied:

- Reclaims `accRewardsForSubgraph - accRewardsForSubgraphSnapshot` (actual GRT amount)
- Does NOT update `accRewardsPerAllocatedToken` (keeps it frozen)
- Updates `accRewardsForSubgraphSnapshot` to prevent double-counting

When not denied:

- Normal operation: updates both `accRewardsPerAllocatedToken` and snapshot

---

## State Flow Scenarios

### Scenario 1: Subgraph Gets Denied

```
T1: Normal operation
    - accRewardsPerAllocatedToken = 100
    - accRewardsForSubgraphSnapshot = 1000

T2: setDenied(subgraph, true) called
    - onSubgraphAllocationUpdate() called with isDenied() = FALSE
    - Normal path: accRewardsPerAllocatedToken updated to 150
    - Snapshot updated
    - THEN denylist set
```

### Scenario 2: Allocation Operations While Denied

```
T3: Any allocation operation (allocate/close/resize/collect)
    - onSubgraphAllocationUpdate() called with isDenied() = TRUE
    - New rewards (accRewardsForSubgraph - snapshot) are RECLAIMED
    - accRewardsPerAllocatedToken stays FROZEN at 150
    - Snapshot updated (prevents double-counting)
```

### Scenario 3: Subgraph Gets Undenied

```
T4: setDenied(subgraph, false) called
    - onSubgraphAllocationUpdate() called with isDenied() = TRUE
    - Remaining denied-period rewards are RECLAIMED
    - THEN denylist cleared

T5: Next allocation operation
    - isDenied() = FALSE
    - Normal operation resumes from frozen state
```

### Scenario 4: Reward Collection

```
While denied:
    - takeRewards() → _calcAllocationRewards() → onSubgraphAllocationUpdate()
    - Returns frozen accRewardsPerAllocatedToken
    - Allocation rewards = tokens × (frozen_value - allocation_snapshot)
    - Only pre-denial rewards are calculated
    - Collection may be blocked by soft deny in takeRewards()

After undeny:
    - Normal collection resumes
    - Indexers get pre-denial rewards only (frozen value)
```

---

## Paths That Call `onSubgraphAllocationUpdate()`

| Path                        | Location                        | Description                          |
| --------------------------- | ------------------------------- | ------------------------------------ |
| `_allocate()`               | AllocationManager.sol:231       | Creating new allocation              |
| `_closeAllocation()`        | AllocationManager.sol:302, 439  | Closing allocation (normal or force) |
| `_resizeAllocation()`       | AllocationManager.sol:389       | Resizing allocation                  |
| `_collectIndexingRewards()` | Via takeRewards()               | Collecting rewards                   |
| `_setDenied()`              | RewardsManager.sol:330          | Deny/undeny subgraph                 |
| `_calcAllocationRewards()`  | RewardsManager.sol:593          | Calculating rewards                  |
| Legacy Staking              | Staking.sol:897                 | Legacy allocation operations         |
| Legacy Staking              | HorizonStakingExtension.sol:288 | Legacy extension                     |

## Paths That Call `onSubgraphSignalUpdate()`

| Path                    | Location                        | Description            |
| ----------------------- | ------------------------------- | ---------------------- |
| Curation mint/burn      | Curation.sol:435                | Signal changes         |
| L2 Curation             | L2Curation.sol:485              | L2 signal changes      |
| Query fees collection   | SubgraphService.sol:547         | Curation fees          |
| Legacy close allocation | Staking.sol:862                 | Curation fees on close |
| Legacy extension        | HorizonStakingExtension.sol:458 | Curation fees          |

**Note:** `onSubgraphSignalUpdate()` updates `accRewardsForSubgraph` and `accRewardsPerSignalSnapshot`, which is separate from allocation reward accounting.

## Operations That Do NOT Affect Allocation Rewards

| Operation              | Reason                                                |
| ---------------------- | ----------------------------------------------------- |
| Slashing               | Only affects stake on HorizonStaking, not allocations |
| Delegation             | Separate from allocation rewards                      |
| Stake deposit/withdraw | Separate from allocation accounting                   |

---

## Accounting Invariants

1. **While denied:**
   - `accRewardsPerAllocatedToken` is frozen
   - New rewards are reclaimed via `_reclaimRewards()`
   - `accRewardsForSubgraphSnapshot` is updated to prevent double-counting

2. **Allocation snapshots:**
   - Each allocation stores its `accRewardsPerAllocatedToken` at creation
   - Rewards = `tokens × (current - snapshot) / SCALING_FACTOR`
   - When denied, `current` = frozen value, so only pre-denial rewards

3. **No double-counting:**
   - Each `onSubgraphAllocationUpdate()` call updates snapshot
   - Reclaim amount = `accRewardsForSubgraph - accRewardsForSubgraphSnapshot`
   - After reclaim, snapshot = current, so next call starts fresh

4. **No bypasses:**
   - All allocation-affecting operations go through `onSubgraphAllocationUpdate()`
   - Signal changes (`onSubgraphSignalUpdate`) are separate accounting

---

## Edge Cases

### All allocations close while denied

- `getAccRewardsPerAllocatedToken()` returns 0 when no allocated tokens
- But we don't update `accRewardsPerAllocatedToken` when denied
- Frozen value is preserved for new allocations after undeny

### Allocation created while denied

- Gets snapshot = frozen `accRewardsPerAllocatedToken`
- After undeny, rewards = (new value - frozen value)
- Only gets post-undeny rewards ✓

### Multiple reclaims while denied

- Each call reclaims only NEW rewards since last call
- Snapshot updated after each reclaim
- No double-counting ✓

### Redundant deny/undeny calls (idempotency)

- `setDenied(id, true)` when already denied: no state change, no event emitted
- `setDenied(id, false)` when not denied: no state change, no event emitted
- `onSubgraphAllocationUpdate()` is still called in both cases (side effect on reward snapshots/reclaims)
- Original deny block number is preserved on redundant deny calls ✓

### Zero rewards to reclaim

- Condition: `subgraph.accRewardsForSubgraphSnapshot < accRewardsForSubgraph`
- If equal, no reclaim (nothing to reclaim)
- Prevents zero-amount reclaims ✓

---

## Soft Deny in AllocationManager

### Location

`AllocationManager.sol:_presentPOI()` (line 283)

### Code

```solidity
bool canClaimNow = allocation.createdAtEpoch < _graphEpochManager().currentEpoch()
    && !_graphRewardsManager().isDenied(allocation.subgraphDeploymentId);
```

### Behavior When Denied

When `isDenied() = true`, `canClaimNow = false`, which causes:

1. **`takeRewards()` is NOT called** (line 288-289 skipped)
   - No rewards are minted to indexer
   - No rewards are reclaimed via takeRewards path

2. **Stale/Zero POI still reclaimed** (lines 284-287)

   ```solidity
   if (allocation.isStale(maxPOIStaleness)) {
       _graphRewardsManager().reclaimRewards(RewardsCondition.STALE_POI, _allocationId, "");
   } else if (_poi == bytes32(0)) {
       _graphRewardsManager().reclaimRewards(RewardsCondition.ZERO_POI, _allocationId, "");
   }
   ```

   - These reclaims go through `_calcAllocationRewards()` → `onSubgraphAllocationUpdate()`
   - While denied, `onSubgraphAllocationUpdate()` reclaims subgraph-level rewards

3. **Early return at line 297**

   ```solidity
   if (!canClaimNow) return 0;
   ```

   - Does NOT snapshot allocation rewards
   - Does NOT clear pending rewards
   - Allocation state preserved for future collection

4. **POI is still recorded** (line 294)

   ```solidity
   _allocations.presentPOI(_allocationId);
   ```

   - Prevents allocation from becoming stale
   - Indexer can keep presenting POIs while denied

### Flow Summary

```
_presentPOI() called while denied:
├── Stale POI? → reclaimRewards(STALE_POI) → onSubgraphAllocationUpdate() reclaims
├── Zero POI?  → reclaimRewards(ZERO_POI)  → onSubgraphAllocationUpdate() reclaims
├── Valid POI? → canClaimNow = false, skip takeRewards()
├── Record POI (prevents staleness)
└── Return 0 (no snapshot, no clear pending)
```

### Why This Works

1. **Pre-denial rewards preserved:**
   - `accRewardsPerAllocatedToken` frozen in RewardsManager
   - Allocation's pending rewards not cleared
   - After undeny, indexer can collect pre-denial rewards

2. **Denied-period rewards reclaimed:**
   - `onSubgraphAllocationUpdate()` reclaims subgraph-level rewards
   - Called via reclaimRewards() even when valid POI
   - Called via setDenied() on deny/undeny transitions

3. **Indexer keeps allocation healthy:**
   - Can present POIs to avoid staleness
   - Doesn't forfeit allocation by not presenting

### Interaction with RewardsManager

| AllocationManager Action     | RewardsManager Behavior                                           |
| ---------------------------- | ----------------------------------------------------------------- |
| `takeRewards()` skipped      | No rewards minted                                                 |
| `reclaimRewards(STALE/ZERO)` | Calls `_calcAllocationRewards()` → `onSubgraphAllocationUpdate()` |
| POI recorded                 | No RewardsManager interaction                                     |
| Early return                 | No snapshot update in allocation                                  |

---

## Known Limitations and Design Considerations

### 1. takeRewards() Snapshot Control

The current implementation reclaims rewards in `onSubgraphAllocationUpdate()` when a subgraph is denied. However, the calling issuer (e.g., SubgraphService) does not have control over when this reclaim happens - it occurs automatically on any allocation update.

**Alternative approach considered:** RewardsManager could skip reclaiming for denied subgraphs and leave the decision to the calling issuer. This would give issuers more flexibility in how they handle denied-period rewards.

**Current behavior:** RewardsManager automatically reclaims denied-period rewards on every allocation update. This ensures rewards are reclaimed promptly but removes issuer control over the timing.

### 2. Soft Deny vs Hard Deny

The implementation uses two layers:

1. **Hard deny (RewardsManager):** Freezes `accRewardsPerAllocatedToken` and reclaims new rewards
2. **Soft deny (AllocationManager):** Skips `takeRewards()` when denied, allowing pre-denial rewards to be preserved

These layers work together but could potentially diverge if other issuers implement different soft deny behaviors.

### 3. Legacy `_deniedRewards()` Flow

The `isDenied()` check in `_deniedRewards()` is now effectively unused for new SubgraphService allocations since `AllocationManager._presentPOI()` implements soft deny by skipping `takeRewards()` entirely. However, it's still invoked for legacy staking (`Staking.sol`) allocations.

**Potential cleanup:** The `isDenied()` branch in `_deniedRewards()` could be removed if legacy staking support is deprecated, as the new SubgraphService handles denied subgraphs via AllocationManager soft deny.

### 4. Race Conditions on Deny/Undeny

If `setDenied()` is called while an allocation operation is in flight:

- The `onSubgraphAllocationUpdate()` call in `_setDenied()` runs first (before state change)
- This should correctly snapshot/reclaim rewards before the state transition
- However, tight timing with concurrent allocation operations could lead to edge cases

---

## Test Cases Needed

The following test scenarios should be verified:

1. **Basic deny/undeny cycle:**
   - Allocation earns rewards → subgraph denied → allocation can collect pre-denial rewards after undeny

2. **Rewards during denied period:**
   - Subgraph denied → time passes → rewards reclaimed (not available to indexers)

3. **Multiple reclaims while denied:**
   - Multiple allocation operations while denied → each reclaims only new rewards since last operation

4. **Allocation created while denied:**
   - Subgraph denied → new allocation created → subgraph undenied → allocation only earns post-undeny rewards

5. **All allocations close while denied:**
   - All allocations close while denied → frozen `accRewardsPerAllocatedToken` preserved → new allocation after undeny works correctly

6. **Zero rewards scenario:**
   - No new rewards since last update → no reclaim operation (condition check prevents zero-amount reclaims)

7. **POI presentation while denied:**
   - Indexer presents valid POI while denied → returns 0, no snapshot update, allocation state preserved

8. **Idempotent deny/undeny (no-op cases):**
   - Deny already-denied subgraph → no event emitted, denylist block number preserved
   - Undeny already-not-denied subgraph → no event emitted, denylist remains zero
