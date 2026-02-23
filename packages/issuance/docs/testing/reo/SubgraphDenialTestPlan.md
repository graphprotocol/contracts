# Subgraph Denial Test Plan

> **Status: DRAFT WIP** — Under review. Test steps and pass criteria may change.

> **Navigation**: [← Back to REO Testing](README.md) | [BaselineTestPlan](BaselineTestPlan.md) | [RewardsConditionsTestPlan](RewardsConditionsTestPlan.md)

Tests for the subgraph denial behavior changes introduced in the issuance upgrade. Denial handling changed significantly: accumulators now freeze during denial (reclaiming new rewards), while uncollected pre-denial rewards are preserved and become claimable after undeny.

> All contract reads use `cast call`. All addresses must be **lowercase**. Replace placeholder addresses with actual deployed addresses for your network.

## Contract Addresses

| Contract                | Arbitrum Sepolia                             | Arbitrum One                                 |
| ----------------------- | -------------------------------------------- | -------------------------------------------- |
| RewardsManager (proxy)  | `0x1f49cae7669086c8ba53cc35d1e9f80176d67e79` | `0x971b9d3d0ae3eca029cab5ea1fb0f72c85e6a525` |
| SubgraphService (proxy) | `0xc24a3dac5d06d771f657a48b20ce1a671b78f26b` | `0xb2bb92d0de618878e438b55d5846cfecd9301105` |
| GraphToken (L2)         | `0xf8c05dcf59e8b28bfd5eed176c562bebcfc7ac04` | `0x9623063377ad1b27544c965ccd7342f7ea7e88c7` |
| Controller              | `0x9db3ee191681f092607035d9bda6e59fbeaca695` | `0x0a8491544221dd212964fbb96487467291b2c97e` |

**Address sources**: `packages/horizon/addresses.json` (RewardsManager, GraphToken, Controller), `packages/subgraph-service/addresses.json` (SubgraphService).

### RPC

| Network          | RPC URL                                  |
| ---------------- | ---------------------------------------- |
| Arbitrum Sepolia | `https://sepolia-rollup.arbitrum.io/rpc` |

---

## Background

### What Changed

**Before (Horizon baseline):** Denial was a binary gate at `takeRewards()` time. When a subgraph was denied, rewards were returned as 0 and the allocation snapshot advanced, permanently dropping those rewards.

**After (issuance upgrade):** Denial is handled at two levels:

1. **RewardsManager (accumulator level):** When accumulator updates encounter a denied subgraph, `accRewardsForSubgraph` and `accRewardsPerAllocatedToken` freeze. New rewards during denial are reclaimed instead of accumulated. `setDenied()` snapshots accumulators before changing state so the boundary is clean.

2. **AllocationManager (claim level):** POI presentation for a denied subgraph is _deferred_ — returns 0 **without advancing the allocation snapshot**. Uncollected pre-denial rewards are preserved and become claimable after undeny.

### Key Invariants

- Accumulators never decrease (they freeze during denial, not decrease)
- Pre-denial uncollected rewards are preserved through the deny/undeny cycle
- Denial-period rewards are reclaimed (or dropped if no reclaim address)
- `setDenied()` snapshots accumulators before state change (clean boundary)
- Redundant deny/undeny calls are idempotent (no state change)

---

## Prerequisites

- [Baseline tests](BaselineTestPlan.md) Cycles 1-7 pass
- [Reclaim system configured](RewardsConditionsTestPlan.md#cycle-1-reclaim-system-configuration) (Cycle 1 of RewardsConditionsTestPlan) — or configure inline during Cycle 1 below
- At least two indexers with active allocations on rewarded subgraph deployments
- Access to the Governor or SubgraphAvailabilityOracle (SAO) account that can call `setDenied()`
- Allocations must be mature (open for 2+ epochs) before denial tests

### Roles Needed

| Role            | Needed For                                    | Holder                           |
| --------------- | --------------------------------------------- | -------------------------------- |
| Governor or SAO | `setDenied()` calls                           | Check Controller configuration   |
| Governor        | `setReclaimAddress()` (if not yet configured) | Council/NetworkOperator multisig |

### Identifying the SAO

```bash
# The SAO is stored in the Controller as the subgraphAvailabilityOracle
# Alternatively, check who can call setDenied on RewardsManager
cast call <CONTROLLER> "getContractProxy(bytes32)(address)" $(cast keccak "SubgraphAvailabilityOracle") --rpc-url <RPC>
```

---

## Testing Approach

**Dedicated test subgraph**: Use a subgraph deployment that is not critical to other testing. The deployment should have:

- Non-zero curation signal
- At least two active allocations from different indexers
- Signal above `minimumSubgraphSignal` (to isolate denial behavior from signal threshold behavior)

**Epoch timing**: Many tests require waiting for epoch boundaries. On Sepolia, epochs are ~554 blocks (~110 minutes). Plan sessions accordingly.

**Reclaim address monitoring**: Before starting, configure a reclaim address for `SUBGRAPH_DENIED` so reclaimed tokens are observable. If no reclaim address is set, denial-period rewards are silently dropped.

---

## Test Sequence Overview

| Cycle | Area                            | Tests     | Notes                                              |
| ----- | ------------------------------- | --------- | -------------------------------------------------- |
| 1     | Reclaim Setup for Denial        | 1.1 - 1.2 | Governor access needed; skip if already configured |
| 2     | Denial State Management         | 2.1 - 2.4 | SAO or Governor access needed                      |
| 3     | Accumulator Freeze Verification | 3.1 - 3.4 | Read-only after denial; wait for epochs            |
| 4     | Allocation-Level Deferral       | 4.1 - 4.3 | Requires active allocations on denied subgraph     |
| 5     | Undeny and Reward Recovery      | 5.1 - 5.4 | Full deny→undeny→claim lifecycle                   |
| 6     | Edge Cases                      | 6.1 - 6.4 | Advanced scenarios                                 |

---

## Cycle 1: Reclaim Setup for Denial

> Skip this cycle if reclaim addresses are already configured (verify with tests 1.1 reads).

### 1.1 Configure SUBGRAPH_DENIED reclaim address

**Objective**: Set a reclaim address for `SUBGRAPH_DENIED` so that denial-period rewards are minted to a trackable address instead of being silently dropped.

**Steps**:

```bash
# Compute the SUBGRAPH_DENIED condition identifier
SUBGRAPH_DENIED=$(cast keccak "SUBGRAPH_DENIED")

# Check current reclaim address (expect zero if unconfigured)
cast call <REWARDS_MANAGER> "getReclaimAddress(bytes32)(address)" $SUBGRAPH_DENIED --rpc-url <RPC>

# Set reclaim address (as Governor)
cast send <REWARDS_MANAGER> "setReclaimAddress(bytes32,address)" $SUBGRAPH_DENIED <RECLAIM_ADDRESS> --rpc-url <RPC> --private-key <GOVERNOR_KEY>

# Verify
cast call <REWARDS_MANAGER> "getReclaimAddress(bytes32)(address)" $SUBGRAPH_DENIED --rpc-url <RPC>
```

**Pass Criteria**:

- `ReclaimAddressSet` event emitted with correct reason and address
- `getReclaimAddress(SUBGRAPH_DENIED)` returns the configured address

---

### 1.2 Record reclaim address GRT balance

**Objective**: Record the starting GRT balance of the reclaim address so we can measure tokens reclaimed during denial.

**Steps**:

```bash
cast call <GRAPH_TOKEN> "balanceOf(address)(uint256)" <RECLAIM_ADDRESS> --rpc-url <RPC>
```

**Pass Criteria**:

- Balance recorded for later comparison

---

## Cycle 2: Denial State Management

### 2.1 Verify subgraph is not denied (pre-test)

**Objective**: Confirm the test subgraph deployment is currently not denied and accumulators are growing.

**Steps**:

```bash
# Check denial status
cast call <REWARDS_MANAGER> "isDenied(bytes32)(bool)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>

# Record current accumulator values
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>

cast call <REWARDS_MANAGER> "getAccRewardsPerAllocatedToken(bytes32)(uint256,uint256)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>
```

**Pass Criteria**:

- `isDenied` = `false`
- Accumulator values recorded as baseline

---

### 2.2 Deny subgraph deployment

**Objective**: Deny a subgraph and verify the state transition. Confirm `setDenied()` snapshots accumulators before applying denial.

**Steps**:

```bash
# Deny the subgraph (as SAO or Governor)
cast send <REWARDS_MANAGER> "setDenied(bytes32,bool)" <SUBGRAPH_DEPLOYMENT_ID> true --rpc-url <RPC> --private-key <SAO_KEY>

# Verify denial
cast call <REWARDS_MANAGER> "isDenied(bytes32)(bool)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>
```

**Verification**: Check for `RewardsDenylistUpdated` event:

```bash
# Check the transaction receipt for RewardsDenylistUpdated event
cast receipt <TX_HASH> --rpc-url <RPC>
```

**Pass Criteria**:

- Transaction succeeds
- `isDenied` = `true`
- `RewardsDenylistUpdated(subgraphDeploymentID, sinceBlock)` event emitted with `sinceBlock` = block number of the transaction

---

### 2.3 Redundant deny is idempotent

**Objective**: Calling `setDenied(true)` on an already-denied subgraph should not change state or emit new events.

**Steps**:

```bash
# Deny again (already denied)
cast send <REWARDS_MANAGER> "setDenied(bytes32,bool)" <SUBGRAPH_DEPLOYMENT_ID> true --rpc-url <RPC> --private-key <SAO_KEY>

# Verify still denied
cast call <REWARDS_MANAGER> "isDenied(bytes32)(bool)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>
```

**Pass Criteria**:

- Transaction succeeds (does not revert)
- `isDenied` still = `true`
- No additional `RewardsDenylistUpdated` event (or event has unchanged `sinceBlock`)

---

### 2.4 Unauthorized deny reverts

**Objective**: Only the SAO or Governor can deny subgraphs.

**Steps**:

```bash
# Attempt deny from unauthorized account
cast send <REWARDS_MANAGER> "setDenied(bytes32,bool)" <SUBGRAPH_DEPLOYMENT_ID> true --rpc-url <RPC> --private-key <RANDOM_KEY>
```

**Pass Criteria**:

- Transaction reverts

---

## Cycle 3: Accumulator Freeze Verification

> **Timing**: These tests require waiting for time to pass after denial. At minimum, wait for part of an epoch (~30-60 minutes on Sepolia) between reads to observe that accumulators have stopped growing.

### 3.1 Accumulators freeze after denial

**Objective**: Verify that `accRewardsForSubgraph` and `accRewardsPerAllocatedToken` stop growing for a denied subgraph.

**Prerequisites**: Subgraph denied in test 2.2. Wait at least 30 minutes.

**Steps**:

```bash
# Read accumulators (should match or be very close to values recorded at denial time)
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>

cast call <REWARDS_MANAGER> "getAccRewardsPerAllocatedToken(bytes32)(uint256,uint256)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>

# Compare with a non-denied subgraph (should be growing)
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <NON_DENIED_DEPLOYMENT_ID> --rpc-url <RPC>
```

**Pass Criteria**:

- Denied subgraph: `accRewardsForSubgraph` has NOT increased since denial
- Denied subgraph: `accRewardsPerAllocatedToken` has NOT increased since denial
- Non-denied subgraph: accumulators continue to increase normally (control)

---

### 3.2 getRewards returns frozen value for allocations on denied subgraph

**Objective**: Verify that `getRewards()` for an allocation on a denied subgraph returns a frozen value (no new rewards accumulate).

**Steps**:

```bash
# Check pending rewards for allocation on denied subgraph
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID_ON_DENIED> --rpc-url <RPC>

# Wait some time, check again
# (wait 30+ minutes)
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID_ON_DENIED> --rpc-url <RPC>
```

**Pass Criteria**:

- Both reads return the same value (frozen — no new rewards accruing)
- The value represents pre-denial uncollected rewards (may be non-zero)

---

### 3.3 Denial-period rewards reclaimed

**Objective**: Verify that rewards that would have gone to the denied subgraph are being reclaimed to the configured address.

**Prerequisites**: Reclaim address configured in Cycle 1. Some time has passed since denial.

**Steps**:

```bash
# Trigger an accumulator update that processes the denied subgraph
# This happens automatically on signal/allocation changes, but can be forced:
cast send <REWARDS_MANAGER> "onSubgraphSignalUpdate(bytes32)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC> --private-key <ANY_KEY>

# Check reclaim address balance
cast call <GRAPH_TOKEN> "balanceOf(address)(uint256)" <RECLAIM_ADDRESS> --rpc-url <RPC>
```

**Verification**: Check for `RewardsReclaimed` events:

```bash
RECLAIM_EVENT_SIG=$(cast sig-event "RewardsReclaimed(bytes32,uint256,address,address,bytes32)")
cast logs --from-block <DENIAL_BLOCK> --to-block latest --address <REWARDS_MANAGER> --topic0 $RECLAIM_EVENT_SIG --rpc-url <RPC>
```

**Pass Criteria**:

- `RewardsReclaimed` event(s) emitted with reason = `SUBGRAPH_DENIED`
- Reclaim address GRT balance has increased from the Cycle 1 baseline
- Reclaimed amount is proportional to the denied subgraph's signal share and denial duration

---

### 3.4 Non-denied subgraphs unaffected

**Objective**: Confirm that denying one subgraph does not affect reward accumulation for other subgraphs.

**Steps**:

```bash
# Check a non-denied subgraph's accumulator
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <NON_DENIED_DEPLOYMENT_ID> --rpc-url <RPC>

# Check allocation rewards on non-denied subgraph
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID_ON_NON_DENIED> --rpc-url <RPC>
```

**Pass Criteria**:

- Non-denied subgraph accumulators continue increasing
- Allocation rewards on non-denied subgraph continue accruing

---

## Cycle 4: Allocation-Level Deferral

### 4.1 POI presentation on denied subgraph defers (returns 0, preserves state)

**Objective**: When an indexer presents a POI for a denied subgraph, the allocation should return 0 rewards WITHOUT advancing the snapshot. The `POIPresented` event should show `condition = SUBGRAPH_DENIED`.

**Prerequisites**: Indexer has an active allocation on the denied subgraph. Allocation is mature (open 2+ epochs).

**Steps**:

1. Record the allocation's current reward snapshot (via view functions)
2. Close or present POI for the allocation on the denied subgraph

```bash
# Check pending rewards before POI presentation
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID> --rpc-url <RPC>

# Present POI (via indexer agent or manual close attempt)
# The exact mechanism depends on your indexer setup
graph indexer allocations close <ALLOCATION_ID>
```

**Verification**: Check transaction logs for `POIPresented` event:

```bash
POI_EVENT_SIG=$(cast sig-event "POIPresented(address,address,bytes32,bytes32,bytes,bytes32)")
cast logs --from-block <TX_BLOCK> --to-block <TX_BLOCK> --address <SUBGRAPH_SERVICE> --topic0 $POI_EVENT_SIG --rpc-url <RPC>
```

**Pass Criteria**:

- `POIPresented` event emitted with `condition` = `keccak256("SUBGRAPH_DENIED")`
- Rewards returned = 0
- **Critical**: Allocation snapshot NOT advanced (pre-denial rewards preserved)
- Allocation remains open if this was a POI presentation (not a force-close)

---

### 4.2 Multiple POI presentations while denied do not lose rewards

**Objective**: An indexer can present POIs multiple times while a subgraph is denied without losing any pre-denial rewards. Each presentation should defer without advancing the snapshot.

**Steps**:

```bash
# First POI presentation (while denied)
# Record getRewards value
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID> --rpc-url <RPC>

# Present POI
# (use indexer agent or cast send to SubgraphService)

# Second POI presentation (still denied, next epoch)
# Wait one epoch
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID> --rpc-url <RPC>

# Present POI again
```

**Pass Criteria**:

- `getRewards()` returns the same frozen value across all presentations
- No `RewardsReclaimed` events for the allocation's pre-denial rewards
- Pre-denial rewards remain preserved through multiple POI cycles

---

### 4.3 Indexers should continue presenting POIs during denial

**Objective**: Document that continuing POI presentation during denial prevents staleness. The POI timestamp is updated even on deferred presentations.

**Steps**:

1. Confirm the denied subgraph has active allocations
2. Present POI normally (via indexer agent)
3. Verify the allocation's last POI timestamp is updated

**Pass Criteria**:

- POI presentation succeeds (transaction does not revert)
- Allocation does not become stale during denial period
- When subgraph is later undenied, the allocation is still healthy (not stale)

---

## Cycle 5: Undeny and Reward Recovery

### 5.1 Undeny subgraph deployment

**Objective**: Remove denial and verify accumulators resume growing.

**Steps**:

```bash
# Record accumulators just before undeny
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>

# Undeny
cast send <REWARDS_MANAGER> "setDenied(bytes32,bool)" <SUBGRAPH_DEPLOYMENT_ID> false --rpc-url <RPC> --private-key <SAO_KEY>

# Verify
cast call <REWARDS_MANAGER> "isDenied(bytes32)(bool)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>
```

**Verification**: Check for `RewardsDenylistUpdated` event with `sinceBlock = 0`.

**Pass Criteria**:

- `isDenied` = `false`
- `RewardsDenylistUpdated(subgraphDeploymentID, 0)` event emitted

---

### 5.2 Accumulators resume after undeny

**Objective**: Verify that accumulators start growing again after undeny.

**Prerequisites**: Subgraph undenied in test 5.1. Wait at least 30 minutes.

**Steps**:

```bash
# Read accumulators (should now be growing again)
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>

cast call <REWARDS_MANAGER> "getAccRewardsPerAllocatedToken(bytes32)(uint256,uint256)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>
```

**Pass Criteria**:

- `accRewardsForSubgraph` has increased since undeny
- `accRewardsPerAllocatedToken` has increased since undeny
- Growth rate is consistent with the subgraph's signal proportion

---

### 5.3 Pre-denial rewards claimable after undeny

**Objective**: Verify that uncollected rewards from before the denial period are now claimable. This is the critical test: the new behavior preserves these rewards rather than dropping them.

**Prerequisites**: Indexer has allocation that was open before denial and still active. Subgraph is now undenied. Wait 1-2 epochs after undeny.

**Steps**:

```bash
# Check pending rewards (should include pre-denial uncollected + post-undeny new rewards)
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID> --rpc-url <RPC>

# Close allocation to claim
graph indexer allocations close <ALLOCATION_ID>
```

**Verification Query**:

```graphql
{
  allocations(where: { id: "ALLOCATION_ID" }) {
    id
    status
    indexingRewards
    closedAtEpoch
  }
}
```

**Pass Criteria**:

- `indexingRewards` is non-zero
- Reward amount includes:
  - Pre-denial uncollected rewards (accumulated before deny)
  - Post-undeny rewards (accumulated after undeny)
- Reward amount does NOT include denial-period rewards (those were reclaimed in Cycle 3)
- `POIPresented` event shows `condition = NONE` (normal claim)

---

### 5.4 Denial-period rewards are NOT included in claim

**Objective**: Verify that the claimed rewards exclude the denial period. Compare the claimed amount against what a continuously-active allocation would have earned.

**Steps**:

1. Calculate expected rewards:
   - Pre-denial period: from allocation creation to deny block
   - Post-undeny period: from undeny block to close block
   - Denial period: from deny block to undeny block (should be excluded)
2. Compare actual `indexingRewards` from test 5.3

**Pass Criteria**:

- Claimed rewards approximate (pre-denial + post-undeny) only
- Denial-period rewards were reclaimed (verified in Cycle 3)
- Total of (claimed + reclaimed) approximately equals what would have been earned with no denial

---

## Cycle 6: Edge Cases

### 6.1 New allocation created while subgraph is denied

**Objective**: An allocation opened on a denied subgraph starts with a frozen baseline. It should only earn rewards after undeny.

**Prerequisites**: Subgraph currently denied.

**Steps**:

```bash
# Create allocation on denied subgraph
graph indexer allocations create <DENIED_DEPLOYMENT_IPFS_HASH> <AMOUNT>

# Check rewards immediately
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <NEW_ALLOCATION_ID> --rpc-url <RPC>

# Wait some time (still denied)
# Check rewards again
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <NEW_ALLOCATION_ID> --rpc-url <RPC>

# Undeny
cast send <REWARDS_MANAGER> "setDenied(bytes32,bool)" <SUBGRAPH_DEPLOYMENT_ID> false --rpc-url <RPC> --private-key <SAO_KEY>

# Wait 1-2 epochs after undeny
# Check rewards again
cast call <REWARDS_MANAGER> "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <NEW_ALLOCATION_ID> --rpc-url <RPC>
```

**Pass Criteria**:

- While denied: `getRewards()` returns 0 (no rewards accumulate)
- After undeny: `getRewards()` starts increasing (rewards resume from undeny point)
- Allocation only earns post-undeny rewards

---

### 6.2 All allocations close while denied, then new allocation after undeny

**Objective**: When all allocations close during denial, the frozen accumulator state is preserved. A new allocation after undeny should use that preserved baseline.

**Steps**:

1. Deny subgraph (if not already denied)
2. Close all allocations on the denied subgraph
3. Undeny subgraph
4. Create new allocation
5. Wait 1-2 epochs, close, check rewards

**Pass Criteria**:

- New allocation earns rewards only for the post-undeny period
- Frozen state was correctly preserved through the "no allocations" period
- No rewards are double-counted or lost at the transition

---

### 6.3 Deny and undeny in rapid succession

**Objective**: A quick deny→undeny cycle correctly handles the boundary. Accumulators are snapshotted on each transition.

**Steps**:

```bash
# Record accumulators
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>

# Deny
cast send <REWARDS_MANAGER> "setDenied(bytes32,bool)" <SUBGRAPH_DEPLOYMENT_ID> true --rpc-url <RPC> --private-key <SAO_KEY>

# Undeny (in next block or shortly after)
cast send <REWARDS_MANAGER> "setDenied(bytes32,bool)" <SUBGRAPH_DEPLOYMENT_ID> false --rpc-url <RPC> --private-key <SAO_KEY>

# Check accumulators
cast call <REWARDS_MANAGER> "getAccRewardsForSubgraph(bytes32)(uint256)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>
```

**Pass Criteria**:

- Both transactions succeed
- Accumulators resume growing after undeny
- Minimal reward loss (only the few blocks between deny and undeny)
- No contract reverts or unexpected state

---

### 6.4 Denial interaction with indexer eligibility

**Objective**: Subgraph denial takes precedence over indexer eligibility. When a subgraph is denied, POI presentation defers regardless of eligibility status — ensuring pre-denial rewards are preserved even for ineligible indexers.

**Prerequisites**: REO validation enabled, one indexer ineligible, subgraph denied.

**Steps**:

```bash
# Confirm indexer is ineligible
cast call <REO_PROXY> "isEligible(address)(bool)" <INELIGIBLE_INDEXER> --rpc-url <RPC>
# Expected: false

# Confirm subgraph is denied
cast call <REWARDS_MANAGER> "isDenied(bytes32)(bool)" <SUBGRAPH_DEPLOYMENT_ID> --rpc-url <RPC>
# Expected: true

# Present POI for ineligible indexer on denied subgraph
# (via indexer agent or manual)
```

**Pass Criteria**:

- POI presentation defers (not reclaimed as INDEXER_INELIGIBLE)
- `POIPresented` event shows `condition = SUBGRAPH_DENIED` (denial takes precedence)
- Pre-denial rewards preserved (not reclaimed due to ineligibility)
- After undeny + re-renewal: rewards become claimable

---

## Post-Testing Checklist

- [ ] All denied subgraphs undenied (or left in intended state)
- [ ] Reclaim addresses verified
- [ ] No allocations stuck in unexpected state
- [ ] Reclaim address balance increase accounted for
- [ ] Results documented in test tracker

---

## Related Documentation

- [← Back to REO Testing](README.md)
- [RewardsConditionsTestPlan.md](RewardsConditionsTestPlan.md) — Signal, POI, and allocation lifecycle conditions
- [BaselineTestPlan.md](BaselineTestPlan.md) — Baseline operational tests (run first)
- [ReoTestPlan.md](ReoTestPlan.md) — REO eligibility tests

---

_Derived from issuance upgrade behavior changes. Source: [RewardsBehaviourChanges.md](/docs/RewardsBehaviourChanges.md), [RewardConditions.md](/docs/RewardConditions.md). Contract: `packages/contracts/contracts/rewards/RewardsManager.sol`, `packages/subgraph-service/contracts/utilities/AllocationManager.sol`._
