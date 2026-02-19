# Indexer Test Guide

> **Navigation**: [← Back to REO Testing](README.md) | [Baseline Details](BaselineTestPlan.md) | [REO Details](ReoTestPlan.md)

Self-contained guide for indexers to verify correct eligibility handling on Arbitrum Sepolia. You control your own eligibility via the ORACLE_ROLE granted to your indexer address.

## Environment

The coordinator configures the test environment before testing begins:

- **Eligibility validation**: enabled (so eligibility state matters)
- **Eligibility period**: short (e.g. 10-15 minutes) for practical testing
- **Oracle timeout**: set very high (no fail-open during testing)
- **ORACLE_ROLE**: granted to each participating indexer

Confirm the environment is ready before starting:

```bash
export RPC="https://sepolia-rollup.arbitrum.io/rpc"
export INDEXER=<YOUR_INDEXER_ADDRESS>           # lowercase
export INDEXER_KEY=<YOUR_PRIVATE_KEY>

# Contract addresses (Arbitrum Sepolia)
export REO=0x62c2305739cc75f19a3a6d52387ceb3690d99a99
export REWARDS_MANAGER=0x1f49cae7669086c8ba53cc35d1e9f80176d67e79
```

```bash
# Validation must be enabled
cast call $REO "getEligibilityValidation()(bool)" --rpc-url $RPC
# Expected: true

# Confirm you have ORACLE_ROLE
ORACLE_ROLE=$(cast keccak "ORACLE_ROLE")
cast call $REO "hasRole(bytes32,address)(bool)" $ORACLE_ROLE $INDEXER --rpc-url $RPC
# Expected: true

# Note the eligibility period (seconds) — this is how long your renewal lasts
cast call $REO "getEligibilityPeriod()(uint256)" --rpc-url $RPC
```

### Eligibility Commands Reference

You will use these throughout the tests:

```bash
# Renew your own eligibility
cast send $REO "renewIndexerEligibility(address[],bytes)" "[$INDEXER]" "0x" \
  --rpc-url $RPC --private-key $INDEXER_KEY

# Check if you are eligible
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC

# Check your last renewal timestamp
cast call $REO "getEligibilityRenewalTime(address)(uint256)" $INDEXER --rpc-url $RPC

# Current block timestamp (to compare with renewal + period)
cast block latest --field timestamp --rpc-url $RPC
```

---

## Test Sets

### Set 1: Prepare Allocations

Open multiple allocations now — they need to mature across epochs before you can close them in later sets. You need at least 3 allocations on different deployments (one per eligibility test).

#### 1.1 Open Allocations

**Steps:**

1. Find subgraph deployments with signal:

```graphql
{
  subgraphDeployments(
    where: { signalledTokens_gt: "0" }
    orderBy: signalledTokens
    orderDirection: desc
    first: 5
  ) {
    id { id }
    signalledTokens
  }
}
```

2. Open allocations on 3+ different deployments:

```bash
graph indexer actions queue allocate <DEPLOYMENT_1> <AMOUNT>
graph indexer actions queue allocate <DEPLOYMENT_2> <AMOUNT>
graph indexer actions queue allocate <DEPLOYMENT_3> <AMOUNT>
graph indexer actions approve
```

3. Record the allocation IDs and current epoch:

```graphql
{
  indexer(id: "<INDEXER_ADDRESS>") {
    allocations(where: { status: "Active" }) {
      id
      subgraphDeployment { id { id } }
      allocatedTokens
      createdAtEpoch
    }
  }
  graphNetwork(id: "1") {
    currentEpoch
  }
}
```

**Pass criteria:**
- 3+ active allocations created
- Allocation epoch recorded (need at least 1 epoch to pass before closing)

> **While waiting for epoch maturity, proceed to Set 2.**

---

### Set 2: Eligible — Close Allocation and Receive Rewards

Renew your eligibility, then close an allocation. You should receive indexing rewards.

#### 2.1 Renew Eligibility

**Steps:**

1. Renew your eligibility:

```bash
cast send $REO "renewIndexerEligibility(address[],bytes)" "[$INDEXER]" "0x" \
  --rpc-url $RPC --private-key $INDEXER_KEY
```

2. Confirm eligibility:

```bash
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: true
```

3. Note your renewal timestamp (you'll need this to know when it expires):

```bash
cast call $REO "getEligibilityRenewalTime(address)(uint256)" $INDEXER --rpc-url $RPC
```

**Pass criteria:**
- `isEligible` returns `true`

#### 2.2 Close Allocation While Eligible

**Prerequisites:** At least 1 epoch has passed since allocation was opened.

**Steps:**

1. Close an allocation:

```bash
graph indexer actions queue close <ALLOCATION_ID>
graph indexer actions approve
```

2. Verify rewards were received:

```graphql
{
  allocation(id: "<ALLOCATION_ID>") {
    status
    indexingRewards
    closedAtEpoch
  }
}
```

**Pass criteria:**
- Allocation status is `Closed`
- `indexingRewards` > 0

---

### Set 3: Ineligible — Close Allocation and Verify Denial

Wait for your eligibility to expire, then close an allocation. You should receive zero rewards.

#### 3.1 Wait for Eligibility Expiry

**Steps:**

1. Calculate when your eligibility expires: `renewal_timestamp + eligibility_period`

2. Monitor until expired:

```bash
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Wait until this returns: false
```

> **While waiting, you can review test results from Set 2.**

**Pass criteria:**
- `isEligible` returns `false`

#### 3.2 Close Allocation While Ineligible

**Prerequisites:** `isEligible` returns `false`. At least 1 epoch has passed since allocation was opened.

**Steps:**

1. Confirm you are ineligible:

```bash
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: false
```

2. Close an allocation:

```bash
graph indexer actions queue close <ALLOCATION_ID>
graph indexer actions approve
```

3. Check rewards:

```graphql
{
  allocation(id: "<ALLOCATION_ID>") {
    status
    indexingRewards
    closedAtEpoch
  }
}
```

**Pass criteria:**
- Allocation status is `Closed`
- `indexingRewards` is `0`

> Denied rewards are routed to the reclaim contract, not to the indexer.

---

### Set 4: Optimistic Recovery — Full Rewards After Re-Renewal

Re-renew eligibility after expiry and close an allocation. You should receive full rewards including accrual during the ineligible period.

This is the key behavioral difference from subgraph denial: eligibility denial is **optimistic** — rewards accrue during ineligible periods and are paid in full upon re-renewal.

#### 4.1 Re-Renew Eligibility

**Steps:**

1. Re-renew your eligibility:

```bash
cast send $REO "renewIndexerEligibility(address[],bytes)" "[$INDEXER]" "0x" \
  --rpc-url $RPC --private-key $INDEXER_KEY
```

2. Confirm eligibility restored:

```bash
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: true
```

**Pass criteria:**
- `isEligible` returns `true` after re-renewal

#### 4.2 Close Allocation — Full Rewards

**Prerequisites:** You have an active allocation that has been open across multiple epochs (including the ineligible period from Set 3).

**Steps:**

1. Close the allocation:

```bash
graph indexer actions queue close <ALLOCATION_ID>
graph indexer actions approve
```

2. Check rewards:

```graphql
{
  allocation(id: "<ALLOCATION_ID>") {
    status
    indexingRewards
    closedAtEpoch
    createdAtEpoch
  }
}
```

3. Compare: this allocation was open for more epochs than the one closed in Set 2, including the ineligible period. Rewards should reflect the **full** duration.

**Pass criteria:**
- `indexingRewards` > 0
- Rewards reflect the full allocation duration (not reduced by the ineligible period)
- This confirms the optimistic model: accrual continues during ineligibility

---

### Set 5: Validation Disabled — All Eligible

When validation is disabled, all indexers are eligible regardless of renewal status. This is the default state and the emergency fallback.

#### 5.1 Verify Eligibility When Validation Is Off

**Prerequisites:** Coordinator has disabled validation (`setEligibilityValidation(false)`).

**Steps:**

1. Confirm validation is disabled:

```bash
cast call $REO "getEligibilityValidation()(bool)" --rpc-url $RPC
# Expected: false
```

2. Check eligibility (should be true regardless of renewal status):

```bash
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: true
```

**Pass criteria:**
- `isEligible` returns `true` even without a recent renewal

---

## Test Sequence Summary

| Set | What You Do | Expected Outcome | Time |
|-----|-------------|------------------|------|
| 1 | Open 3+ allocations | Allocations created, wait for epoch maturity | 5 min + wait |
| 2 | Renew eligibility → close allocation | Rewards received | 5 min |
| 3 | Wait for expiry → close allocation | Zero rewards (denied) | Wait + 5 min |
| 4 | Re-renew → close allocation | Full rewards (optimistic recovery) | 5 min |
| 5 | Validation disabled → check eligibility | All eligible | 2 min |

**Timing notes:**
- Set 1 should be done first; allocations need epoch maturity before closing
- Set 2 requires epoch maturity from Set 1
- Set 3 requires eligibility expiry after Set 2 renewal
- Set 4 uses remaining allocation from Set 1, close promptly after Set 3
- Set 5 requires coordinator to disable validation

## Troubleshooting

**`isEligible` returns `false` unexpectedly:**
- Check if validation is enabled: `getEligibilityValidation()`
- Check your renewal time: `getEligibilityRenewalTime(address)`
- Check the eligibility period: `getEligibilityPeriod()`
- Your renewal may have expired: compare `renewal_time + period` with current block time

**Renewal transaction reverts:**
- Confirm you have ORACLE_ROLE: `hasRole(ORACLE_ROLE, address)`
- Confirm the REO is not paused: `paused()`

**Zero rewards on close despite being eligible:**
- Check allocation maturity: must have been open for at least 1 full epoch
- Check if subgraph deployment has signal (no signal = no rewards)
- Verify RewardsManager points to the REO: `getRewardsEligibilityOracle()`

---

**Related**: [BaselineTestPlan.md](BaselineTestPlan.md) | [ReoTestPlan.md](ReoTestPlan.md)
