# Reward Accounting Safety

This document describes the mechanisms that prevent reward mis-accounting (double-counting or unintentional loss).

## Two-Level Accumulation Model

Rewards flow through two levels before reaching allocations:

```
Global Issuance
    │
    ▼ (proportional to signal)
┌──────────────────────────────────────────────┐
│  Level 1: Signal → Subgraph                  │
│  accRewardsPerSignal → accRewardsForSubgraph │
└──────────────────────────────────────────────┘
    │
    ▼ (proportional to allocated tokens)
┌─────────────────────────────────────────┐
│  Level 2: Subgraph → Allocation         │
│  accRewardsPerAllocatedToken → claim    │
└─────────────────────────────────────────┘
```

Each level uses the same pattern: an accumulator increases over time, and participants snapshot their starting point to calculate their share.

## Core Safety Mechanism: Snapshots

**Principle**: Rewards = (current_accumulator - snapshot) × tokens

Snapshots prevent double-counting by recording each participant's starting point:

| Component  | Accumulator                   | Snapshot                      | Prevents                                      |
| ---------- | ----------------------------- | ----------------------------- | --------------------------------------------- |
| Subgraph   | `accRewardsPerSignal`         | `accRewardsPerSignalSnapshot` | Same rewards credited to multiple subgraphs   |
| Allocation | `accRewardsPerAllocatedToken` | Stored in allocation state    | Same rewards claimed twice by same allocation |

After any update, snapshot = current accumulator. Next calculation starts from zero delta.

## Key Invariants

### 1. Monotonic Accumulators

`accRewardsPerSignal` and `accRewardsPerAllocatedToken` only increase (never decrease).

**Exception**: `accRewardsPerAllocatedToken` freezes (stops increasing) when subgraph is denied or below minimum signal. It never decreases.

**Why it matters**: Decreasing accumulators would cause negative reward calculations or allow re-claiming past rewards.

### 2. Snapshot Consistency

After every state update, snapshot equals current accumulator value.

**Why it matters**: Stale snapshots would allow the same reward period to be counted multiple times.

### 3. Update-Before-Change

Accumulators must be updated BEFORE any state change that affects reward distribution:

- Before `issuancePerBlock` changes → call `updateAccRewardsPerSignal()`
- Before signal changes → call `onSubgraphSignalUpdate()`
- Before allocation changes → call `onSubgraphAllocationUpdate()`

**Why it matters**: Changing distribution parameters without first crediting accrued rewards would lose or misattribute those rewards.

## Critical Call Ordering

### Allocation Creation

```solidity
// In AllocationManager._allocate():
_allocationData = _getAllocationData(_subgraphDeploymentId);  // ① Calls onSubgraphAllocationUpdate
_allocations.create(...);                                       // ② Creates allocation
_allocations.snapshotRewards(..., onSubgraphAllocationUpdate()); // ③ Updates snapshot
```

**Why this order matters**:

- Step ① with zero allocations → triggers NO_ALLOCATION reclaim for gap period
- Step ② creates allocation → now allocatedTokens > 0
- Step ③ same block → newRewards ≈ 0, just confirms snapshot

**If reversed**: Gap-period rewards would be distributed to accumulator but no allocation could claim them (all snapshots would be at/above post-distribution level).

### Reward Claiming

```solidity
// In AllocationManager._presentPoi():
rewards = takeRewards(_allocationId);                           // ① Mints rewards
snapshotRewards(_allocationId, onSubgraphAllocationUpdate(...)); // ② Updates snapshot
clearPendingRewards(_allocationId);                              // ③ Clears pending
```

**Why this order matters**:

- Step ① calculates and mints based on current snapshot
- Step ② updates snapshot to current accumulator
- Future claims start from new snapshot (zero delta for same block)

## Reclaim as Safety Net

Every reward path that cannot reach an allocation has a reclaim handler:

| Condition            | When Triggered                                          | Reclaim Reason           |
| -------------------- | ------------------------------------------------------- | ------------------------ |
| No global signal     | `updateAccRewardsPerSignal()` with signalledTokens = 0  | `NO_SIGNAL`              |
| Subgraph denied      | `onSubgraphAllocationUpdate()`                          | `SUBGRAPH_DENIED`        |
| Below minimum signal | `onSubgraphAllocationUpdate()`                          | `BELOW_MINIMUM_SIGNAL`   |
| No allocations       | `onSubgraphAllocationUpdate()` with allocatedTokens = 0 | `NO_ALLOCATION`          |
| Indexer ineligible   | `takeRewards()`                                         | `INDEXER_INELIGIBLE`     |
| Stale/zero POI       | `_presentPoi()`                                         | `STALE_POI` / `ZERO_POI` |
| Allocation close     | `_closeAllocation()`                                    | `CLOSE_ALLOCATION`       |

**Reclaim priority**: reason-specific address → defaultReclaimAddress → dropped (no mint)

## Potential Failure Modes (Mitigated)

| Failure Mode                 | How Prevented                                                                    |
| ---------------------------- | -------------------------------------------------------------------------------- |
| Double-mint same rewards     | Snapshot updated after every claim; same-block calls return ~0                   |
| Rewards stuck in accumulator | NO_ALLOCATION reclaim before allocation creation                                 |
| Gap period loss              | `_getAllocationData` calls `onSubgraphAllocationUpdate` before allocation exists |
| Denial-period accumulation   | `accRewardsPerAllocatedToken` freezes; new rewards reclaimed                     |
| Signal change mid-period     | `onSubgraphSignalUpdate` hook called before signal changes                       |

## Division of Responsibility

RewardsManager and issuers share responsibility for correct reward accounting:

**RewardsManager** handles what it can observe:

- Reclaims rewards when subgraph conditions prevent distribution (denied, below minimum, zero allocations)
- Denies rewards at claim time when indexer is ineligible
- Maintains accumulator and snapshot state

**Issuers** control claim timing and can defer:

- AllocationManager defers claims for `SUBGRAPH_DENIED` and `ALLOCATION_TOO_YOUNG` by returning early
- This preserves allocation state so rewards remain claimable after conditions change
- RM cannot know issuer intent, so issuers must decide when to attempt claims

**Example - Subgraph Denial**:

1. RM freezes `accRewardsPerAllocatedToken` and reclaims new subgraph-level rewards
2. AM detects denial and skips `takeRewards()` call entirely (soft deny)
3. Pre-denial rewards preserved in allocation snapshot
4. After undeny, AM can claim the preserved rewards

## Issuer Requirements

RewardsManager relies on issuers to maintain shared state correctly.

**Required hook**:

| Hook                         | When to Call              |
| ---------------------------- | ------------------------- |
| `onSubgraphAllocationUpdate` | Before allocation changes |

Note: If the issuer collects curation fees (`curation.collect()`), it must also call `onSubgraphSignalUpdate` before the collect since that changes signal. SubgraphService does this in `_collectQueryFees`.

**Allocation snapshot management**:

Allocation snapshots are stored in issuer contracts, not RewardsManager. After each `takeRewards()` or `reclaimRewards()` call, issuers must update the allocation's snapshot to the current `accRewardsPerAllocatedToken`. Failure to snapshot allows the same rewards to be claimed again.

**Authorized issuers**: SubgraphService (active), Staking (deprecated, legacy allocations only)

## Other Hook Callers

| Hook                        | Caller                    | Trigger                                        |
| --------------------------- | ------------------------- | ---------------------------------------------- |
| `updateAccRewardsPerSignal` | RewardsManager (internal) | Before `issuancePerBlock` or allocator changes |
| `onSubgraphSignalUpdate`    | Curation                  | Before mint/burn signal                        |
