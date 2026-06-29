# Indexer Eligibility Test Plan

> **Navigation**: [← Back to REO Testing](README.md) | [BaselineTestPlan](BaselineTestPlan.md) | [ReoTestPlan](ReoTestPlan.md)

Tests for indexers to verify correct eligibility handling on Arbitrum Sepolia. This is a focused subset of [ReoTestPlan.md](ReoTestPlan.md), covering per-indexer eligibility flows (renew, expire, recover). The full ReoTestPlan covers additional areas: deployment verification, oracle operations, timeout fail-open, emergency operations, and UI verification.

> **Default testnet wiring**: RewardsManager on Arbitrum Sepolia is configured to use the `RewardsEligibilityOracleMock`, so indexers control their own eligibility directly via the mock's `setEligible`. **Sets 2m–4m are the expected path.** Sets 2–4 (production REO with renewals, expiry, and ORACLE_ROLE) only apply if a coordinator repoints RewardsManager at the real oracle. Confirm the active oracle before starting — see [Which oracle is active?](#which-oracle-is-active) below.

Each test includes CLI commands, verification queries against the network subgraph, and pass/fail criteria.

> All GraphQL queries run against the network subgraph. All addresses must be **lowercase**.

---

## Prerequisites

- Completed [BaselineTestPlan](BaselineTestPlan.md) Cycles 1-4 (indexer staked, provisioned, can allocate)
- `cast` (Foundry) installed for contract interaction
- Indexer private key available for signing transactions

### Environment Configuration

By default the testnet RewardsManager points at the mock — no coordinator setup is required, and you run Sets 2m–4m.

The settings below apply **only to the production REO path (Sets 2–4)** and are set by the coordinator when the real oracle is active:

- **Eligibility validation**: enabled
- **Eligibility period**: short (e.g. 10-15 minutes)
- **Oracle timeout**: very high (no fail-open during testing)
- **ORACLE_ROLE**: granted to each participating indexer

### Environment Variables

```bash
export RPC="https://sepolia-rollup.arbitrum.io/rpc"
export INDEXER=<YOUR_INDEXER_ADDRESS>           # lowercase
export INDEXER_KEY=<YOUR_PRIVATE_KEY>

# Contract addresses (Arbitrum Sepolia)
export REO=0x6ba849fbd33257162552578b2a432d30784f2f80
export MOCK_REO=0x69b0f3c6a19beaf1ba59405f7179e188c64b4e06
export REWARDS_MANAGER=0x1f49cae7669086c8ba53cc35d1e9f80176d67e79
```

### Mock REO (default path)

The `RewardsEligibilityOracleMock` is deployed at `0x69b0f3c6a19beaf1ba59405f7179e188c64b4e06` and is the oracle RewardsManager uses by default on testnet. You toggle your own eligibility directly — no ORACLE_ROLE, renewal periods, or timeout logic:

```bash
# Check your eligibility
cast call $MOCK_REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC

# Toggle ineligible (signed by your indexer key)
cast send $MOCK_REO "setEligible(bool)" false --rpc-url $RPC --private-key $INDEXER_KEY

# Toggle eligible again
cast send $MOCK_REO "setEligible(bool)" true --rpc-url $RPC --private-key $INDEXER_KEY
```

Run Sets 2m-4m for fast eligibility control with no waiting for expiry.

#### Which oracle is active?

Confirm what RewardsManager points at before starting:

```bash
cast call $REWARDS_MANAGER "getProviderEligibilityOracle()(address)" --rpc-url $RPC
# Default (mock):       0x69b0f3c6a19beaf1ba59405f7179e188c64b4e06  -> run Sets 2m-4m
# Production (Oracle A): 0x6ba849fbd33257162552578b2a432d30784f2f80  -> run Sets 2-4

# Confirm the revert behaviour these tests assume:
cast call $REWARDS_MANAGER "getRevertOnIneligible()(bool)" --rpc-url $RPC
# Expected: true  -> an ineligible close reverts (Set 3 / 3m).
# If false, the close instead succeeds with 0 rewards (reclaim path) and Set 3's
# pass criteria do not apply — coordinate before proceeding.
```

### Verify Environment (production REO path only)

Skip this if you are on the default mock path. These checks apply to Sets 2–4:

```bash
# Validation must be enabled
cast call $REO "getEligibilityValidation()(bool)" --rpc-url $RPC
# Expected: true

# Confirm you have ORACLE_ROLE
ORACLE_ROLE=$(cast keccak "ORACLE_ROLE")
cast call $REO "hasRole(bytes32,address)(bool)" $ORACLE_ROLE $INDEXER --rpc-url $RPC
# Expected: true

# Note the eligibility period (seconds)
cast call $REO "getEligibilityPeriod()(uint256)" --rpc-url $RPC
```

---

## Test Sequence Overview

| Set | Area                           | Tests     |
| --- | ------------------------------ | --------- |
| 1   | Prepare Allocations            | 1.1       |
| 2   | Eligible — Receive Rewards     | 2.1 - 2.2 |
| 3   | Ineligible — Close Reverts     | 3.1 - 3.3 |
| 4   | Optimistic Recovery            | 4.1 - 4.2 |
| 5   | Validation Disabled            | 5.1       |
| 2m  | Eligible — Mock REO            | 2m.1      |
| 3m  | Ineligible — Mock REO          | 3m.1      |
| 4m  | Optimistic Recovery — Mock REO | 4m.1      |

**Timing**: Set 1 opens allocations that need epoch maturity. **On the default mock wiring, run Set 1 then Sets 2m-4m** — instant eligibility control, no waiting for expiry. Sets 2-4 apply only when a coordinator has activated the production REO (sequential: renew → eligible close → wait for expiry → ineligible close reverts → re-renew → recovery close); Set 5 then requires the coordinator to toggle validation.

---

## Set 1: Prepare Allocations

### 1.1 Open allocations for eligibility tests

**Objective**: Open 3+ allocations on different deployments. These need to mature across epochs before they can be closed in Sets 2-4.

**Prerequisites**: Indexer is staked, provisioned, and registered (BaselineTestPlan Cycles 1-3). Subgraph deployments with signal exist.

**Steps**:

1. Find subgraph deployments with signal
2. Open allocations on 3+ different deployments
3. Record allocation IDs and current epoch

**Command**:

```bash
graph indexer actions queue allocate <DEPLOYMENT_1> <AMOUNT>
graph indexer actions queue allocate <DEPLOYMENT_2> <AMOUNT>
graph indexer actions queue allocate <DEPLOYMENT_3> <AMOUNT>
graph indexer actions approve
```

**Verification Query**:

```graphql
{
  indexer(id: "INDEXER_ADDRESS") {
    allocations(where: { status: "Active" }) {
      id
      subgraphDeployment {
        ipfsHash
      }
      allocatedTokens
      createdAtEpoch
    }
  }
  graphNetwork(id: "1") {
    currentEpoch
  }
}
```

**Pass Criteria**:

- 3+ active allocations visible in subgraph
- `createdAtEpoch` recorded (need at least 1 epoch to pass before closing)

> While waiting for epoch maturity, proceed to Set 2 to renew eligibility.

---

## Set 2: Eligible — Receive Rewards

### 2.1 Renew eligibility

**Objective**: Renew your own eligibility and confirm the REO reflects it.

**Prerequisites**: ORACLE_ROLE confirmed in environment check.

**Command**:

```bash
cast send $REO "renewIndexerEligibility(address[],bytes)" "[$INDEXER]" "0x" \
  --rpc-url $RPC --private-key $INDEXER_KEY
```

**Verification**:

```bash
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: true

cast call $REO "getEligibilityRenewalTime(address)(uint256)" $INDEXER --rpc-url $RPC
# Record this timestamp — eligibility expires at: renewal_time + eligibility_period
```

**Pass Criteria**:

- `isEligible` returns `true`
- `getEligibilityRenewalTime` returns a recent timestamp

---

### 2.2 Close allocation while eligible

**Objective**: Verify that an eligible indexer receives indexing rewards when closing an allocation.

**Prerequisites**: `isEligible` returns `true`. Allocation from Set 1 is at least 1 epoch old.

**Command**:

```bash
graph indexer actions queue close <ALLOCATION_ID>
graph indexer actions approve
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

- Status changes to `Closed`
- `indexingRewards` is non-zero
- `closedAtEpoch` is current epoch

---

## Set 3: Ineligible — Close Reverts

> RewardsManager runs with `revertOnIneligible = true`. An ineligible indexer **cannot** close/present a POI: the transaction reverts with `Indexer not eligible for rewards`, the allocation stays `Active`, and the accrued rewards are preserved (not zeroed, not reclaimed) until the indexer becomes eligible again. This blocks reward collection rather than denying it — the optimistic model.

### 3.1 Wait for eligibility expiry

**Objective**: Confirm that eligibility expires after the configured period.

**Prerequisites**: Renewal timestamp and eligibility period recorded from Set 2.1.

**Steps**:

1. Calculate expiry time: `renewal_timestamp + eligibility_period`
2. Wait until current block time exceeds expiry
3. Verify eligibility has expired

**Verification**:

```bash
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: false

# Confirm by comparing timestamps:
cast call $REO "getEligibilityRenewalTime(address)(uint256)" $INDEXER --rpc-url $RPC
cast call $REO "getEligibilityPeriod()(uint256)" --rpc-url $RPC
cast block latest --field timestamp --rpc-url $RPC
# block_timestamp > renewal_time + period
```

**Pass Criteria**:

- `isEligible` returns `false`
- Block timestamp exceeds renewal time + eligibility period

---

### 3.2 Attempt to close while ineligible (reverts)

**Objective**: Verify that an ineligible indexer cannot close an allocation with a POI — the on-chain `closeAllocation`/`takeRewards` call reverts and the allocation remains open.

**Prerequisites**: `isEligible` returns `false`. Allocation from Set 1 is at least 1 epoch old.

**Steps**:

1. Confirm ineligibility
2. Attempt to close an allocation
3. Confirm the close reverts and the allocation stays `Active`

**Command**:

```bash
# Confirm ineligible
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: false

# Attempt to close — this should fail on-chain
graph indexer actions queue close <ALLOCATION_ID>
graph indexer actions approve
```

The indexer-agent close action fails when the transaction reverts. To observe the revert directly, dry-run the close against the SubgraphService with `cast call` (it returns the revert reason `Indexer not eligible for rewards`).

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

- Close transaction reverts with `Indexer not eligible for rewards`
- Allocation remains `Active` (no `closedAtEpoch`)
- Accrued rewards are preserved — not zeroed, not reclaimed
- Contrast with Set 2.2 where the eligible close succeeded with non-zero `indexingRewards`

---

### 3.3 Prolonged ineligibility → STALE_POI reclaim (the limit of "no rewards lost")

**Objective**: Verify the one case where the optimistic guarantee breaks: because you cannot present a POI while ineligible (3.2 reverts), the staleness clock keeps running. If an allocation goes past `maxPOIStaleness`, its accrued rewards become reclaimable as STALE_POI — so eligibility must be renewed before that window elapses.

**Prerequisites**: `isEligible` returns `false`. An active allocation whose last POI was presented long enough ago that it can cross `maxPOIStaleness` while you stay ineligible. Note `maxPOIStaleness` first:

```bash
cast call <SUBGRAPH_SERVICE> "maxPOIStaleness()(uint256)" --rpc-url $RPC
```

**Steps**:

1. Confirm ineligible (`isEligible` = `false`); note the allocation's last POI time
2. Stay ineligible until `lastPOIPresentedAt + maxPOIStaleness` has elapsed (POI presentation reverts in the meantime, so the clock cannot be reset)
3. Observe the outcome: once stale, the allocation's rewards are reclaimed as STALE_POI — either when a third party force-closes the stale allocation, or on the next POI/close after renewal

**Verification**: Look for a `RewardsReclaimed` event with reason `STALE_POI` on the RewardsManager for the allocation, and confirm the indexer's `indexingRewards` for it is `0`.

**Pass Criteria**:

- While ineligible and before `maxPOIStaleness`: rewards still preserved (3.2 behaviour)
- After crossing `maxPOIStaleness`: accrued rewards are reclaimed as STALE_POI, **not** paid to the indexer even after re-renewal
- Confirms the operational rule: renew (or restore eligibility) before `maxPOIStaleness` elapses

---

## Set 4: Optimistic Recovery

Eligibility denial is **optimistic**: rewards accrue to allocations during ineligible periods, and because closing while ineligible reverts (Set 3.2), no rewards are ever lost. Once the indexer renews eligibility, the close succeeds and pays out in full for the entire duration — including the epochs spent ineligible. This is the key behavioral difference from subgraph denial, where denial-period rewards are permanently reclaimed.

### 4.1 Re-renew eligibility

**Objective**: Restore eligibility after expiry and confirm the REO reflects it.

**Prerequisites**: Eligibility expired (Set 3.1). Do this promptly after Set 3.

**Command**:

```bash
cast send $REO "renewIndexerEligibility(address[],bytes)" "[$INDEXER]" "0x" \
  --rpc-url $RPC --private-key $INDEXER_KEY
```

**Verification**:

```bash
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: true
```

**Pass Criteria**:

- `isEligible` returns `true` after re-renewal

---

### 4.2 Close allocation — full rewards after re-renewal

**Objective**: Verify that an allocation closed after re-renewal receives full rewards for its entire duration, including the ineligible period.

**Prerequisites**: `isEligible` returns `true`. Active allocation from Set 1 has been open across multiple epochs including the ineligible period.

**Command**:

```bash
graph indexer actions queue close <ALLOCATION_ID>
graph indexer actions approve
```

**Verification Query**:

```graphql
{
  allocations(where: { id: "ALLOCATION_ID" }) {
    id
    status
    indexingRewards
    createdAtEpoch
    closedAtEpoch
  }
}
```

**Pass Criteria**:

- Status changes to `Closed`
- `indexingRewards` is non-zero
- Rewards reflect the full allocation duration (`closedAtEpoch - createdAtEpoch`), not reduced by the ineligible period
- Compare with Set 2.2: this allocation was open longer and should have proportionally more rewards

---

## Set 5: Validation Disabled

### 5.1 Verify eligibility when validation is off

**Objective**: Confirm that all indexers are eligible when validation is disabled, regardless of renewal status. This is the default state and the emergency fallback.

**Prerequisites**: Coordinator has disabled validation (`setEligibilityValidation(false)`).

**Verification**:

```bash
cast call $REO "getEligibilityValidation()(bool)" --rpc-url $RPC
# Expected: false

cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: true
```

**Pass Criteria**:

- `getEligibilityValidation` returns `false`
- `isEligible` returns `true` even without a recent renewal

---

## Mock REO Test Sets (2m - 4m)

These sets use the `RewardsEligibilityOracleMock` for direct eligibility control. On Arbitrum Sepolia the RewardsManager the mock. These replace Sets 2-4 when the mock is active.

### 2m.1 Close allocation while eligible (mock)

**Objective**: Verify rewards when eligible (the default mock state).

**Prerequisites**: Allocation from Set 1 is at least 1 epoch old.

```bash
# Confirm eligible (default)
cast call $MOCK_REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: true

# Close allocation
graph indexer actions queue close <ALLOCATION_ID>
graph indexer actions approve
```

**Pass Criteria**: `indexingRewards` is non-zero.

---

### 3m.1 Toggle ineligible and attempt close (mock)

**Objective**: Verify the close reverts after toggling ineligible.

```bash
# Toggle ineligible
cast send $MOCK_REO "setEligible(bool)" false --rpc-url $RPC --private-key $INDEXER_KEY

# Confirm
cast call $MOCK_REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: false

# Attempt to close — this should fail on-chain
graph indexer actions queue close <ALLOCATION_ID>
graph indexer actions approve
```

**Pass Criteria**: Close reverts with `Indexer not eligible for rewards`. Allocation stays `Active`; accrued rewards preserved for later collection.

---

### 4m.1 Re-enable and close allocation -- full rewards (mock)

**Objective**: Verify optimistic recovery: toggle eligible again and receive full rewards.

**Prerequisites**: Active allocation open across multiple epochs, including time while ineligible.

```bash
# Toggle eligible
cast send $MOCK_REO "setEligible(bool)" true --rpc-url $RPC --private-key $INDEXER_KEY

# Confirm
cast call $MOCK_REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: true

# Close allocation
graph indexer actions queue close <ALLOCATION_ID>
graph indexer actions approve
```

**Pass Criteria**:

- `indexingRewards` is non-zero
- Rewards reflect the full allocation duration (not reduced by the ineligible period)
- Compare with 2m.1: longer-open allocation should have proportionally more rewards

---

## Indexer Awareness: Denial and Reward Conditions

These situations are managed by the coordinator, not the indexer. No indexer action is needed — but indexers should understand the expected behaviour.

### During subgraph denial

If a coordinator denies a subgraph you have allocations on:

- **Continue presenting POIs** — deferred presentations reset the staleness clock, preventing STALE_POI reclaim when the subgraph is later undenied
- `getRewards()` returns a frozen value (pre-denial uncollected rewards are preserved)
- Closing an allocation on a denied subgraph returns 0 rewards but preserves the pre-denial amount

**Verification during denial:**

```bash
cast call $REWARDS_MANAGER "isDenied(bytes32)(bool)" <DEPLOYMENT_ID> --rpc-url $RPC
# Expected: true (if coordinator denied it)

cast call $REWARDS_MANAGER "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID> --rpc-url $RPC
# Returns frozen pre-denial rewards (non-zero if you had uncollected rewards)
```

### After subgraph undeny

After a coordinator undenies a subgraph:

- Accumulators resume growing
- Close allocation normally — rewards include pre-denial + post-undeny amounts
- Denial-period rewards were reclaimed to the configured reclaim address (or, if none is configured, simply not minted) — either way not included in your claim

**Verification after undeny:**

```bash
cast call $REWARDS_MANAGER "isDenied(bytes32)(bool)" <DEPLOYMENT_ID> --rpc-url $RPC
# Expected: false

cast call $REWARDS_MANAGER "getRewards(address,address)(uint256)" <SUBGRAPH_SERVICE> <ALLOCATION_ID> --rpc-url $RPC
# Should be growing again (pre-denial + post-undeny rewards)
```

### While you are ineligible

With `revertOnIneligible = true`, presenting a POI / closing an allocation reverts (`Indexer not eligible for rewards`) for as long as you are ineligible. Rewards keep accruing and are not lost — but be aware of the interaction with POI staleness below: you cannot present POIs while ineligible, so a prolonged ineligible period can push an allocation past `maxPOIStaleness`, after which rewards are reclaimed as STALE_POI. Renew eligibility before that window elapses.

### POI staleness

If an allocation goes without POI presentation for longer than `maxPOIStaleness`, rewards are reclaimed as STALE_POI instead of being paid to the indexer.

```bash
cast call <SUBGRAPH_SERVICE> "maxPOIStaleness()(uint256)" --rpc-url $RPC
# Note this value — present POIs more frequently than this
```

**Action**: Ensure your indexer agent is healthy and presenting POIs regularly.

### Signal-related conditions

Rewards require curation signal above the minimum threshold. If signal drops below `minimumSubgraphSignal`, rewards freeze and are reclaimed. This is not actionable by indexers — it depends on curators.

```bash
cast call $REWARDS_MANAGER "minimumSubgraphSignal()(uint256)" --rpc-url $RPC
```

**Related**: [RewardsConditionsTestPlan.md](RewardsConditionsTestPlan.md) | [SubgraphDenialTestPlan.md](SubgraphDenialTestPlan.md)

---

## Troubleshooting

**`isEligible` returns `false` unexpectedly:**

- Check if validation is enabled: `getEligibilityValidation()`
- Check your renewal time: `getEligibilityRenewalTime(address)`
- Check the eligibility period: `getEligibilityPeriod()`
- Your renewal may have expired: compare `renewal_time + period` with current block time

**Renewal transaction reverts:**

- Confirm you have ORACLE_ROLE: `hasRole(ORACLE_ROLE, address)`
- Confirm the REO is not paused: `paused()`

**Close/POI reverts with `Indexer not eligible for rewards`:**

- You are ineligible and `revertOnIneligible = true` — this is expected. Renew eligibility (Set 2.1) or toggle the mock eligible (Set 2m), then retry the close.
- Confirm: `isEligible(address)` returns `false`.

**Zero rewards on close despite being eligible:**

- Check allocation maturity: must have been open for at least 1 full epoch
- Check if subgraph deployment has signal (no signal = no rewards)
- Verify RewardsManager points to the REO: `getProviderEligibilityOracle()`

---

**Related**: [BaselineTestPlan.md](BaselineTestPlan.md) | [ReoTestPlan.md](ReoTestPlan.md)
