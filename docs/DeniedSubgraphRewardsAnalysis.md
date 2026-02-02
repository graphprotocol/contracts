# Subgraph Denial: Reward Behaviour

## Overview

When a subgraph is denied, indexers cannot claim rewards for the denial period, but pre-denial rewards remain claimable after the subgraph is undenied.

## Reward Disposition by Period

| Period            | Rewards                       | Disposition                                              |
| ----------------- | ----------------------------- | -------------------------------------------------------- |
| **Pre-denial**    | Rewards accrued before denial | Claimable after undeny                                   |
| **During denial** | Rewards issued while denied   | Reclaimed to protocol (or dropped if no reclaim address) |
| **Post-undeny**   | Rewards accrued after undeny  | Claimable normally                                       |

## How Denial Affects Allocations

### Existing Allocations (created before denial)

- Pre-denial rewards are preserved in the allocation's snapshot
- Cannot claim while denied (returns 0)
- After undeny, can claim pre-denial rewards
- Denial-period rewards are not available (reclaimed at protocol level)

### New Allocations (created while denied)

- Created with current frozen reward state as baseline
- Only earn rewards after subgraph is undenied
- Cannot earn backdated rewards for denial period

### POI Presentation While Denied

- Indexers can (and should) continue presenting POIs
- Prevents allocations from becoming stale
- Returns 0 rewards but maintains allocation health

## Two-Layer Denial System

### Hard Deny (RewardsManager)

- Freezes `accRewardsPerAllocatedToken` - no new rewards credited to allocations
- Reclaims ongoing issuance to configured reclaim address
- Operates at subgraph level (affects all allocations)

### Soft Deny (AllocationManager)

- Skips `takeRewards()` call when subgraph is denied
- Preserves allocation state for future claiming
- Returns early without modifying allocation snapshots

Together: hard deny prevents new rewards accumulating; soft deny preserves pre-denial rewards.

## Edge Cases

| Scenario                           | Behavior                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------- |
| All allocations close while denied | Frozen reward state preserved; new allocations after undeny use frozen baseline |
| Redundant deny call                | No state change; original deny block preserved                                  |
| Redundant undeny call              | No state change                                                                 |
| Zero reclaim address               | Denial-period rewards dropped (never minted)                                    |

## Safety Guarantees

1. **No double-counting**: Snapshot mechanism ensures each reward period is counted once
2. **No lost pre-denial rewards**: Frozen state preserves indexer's earned rewards
3. **Idempotent operations**: Redundant deny/undeny calls are safe no-ops
