# Indexer Eligibility Test Plan

> **Navigation**: [← Back to REO Testing](README.md) | [BaselineTestPlan](BaselineTestPlan.md) | [ReoTestPlan](ReoTestPlan.md)

Tests for indexers to verify correct eligibility handling on Arbitrum Sepolia. This is a focused subset of [ReoTestPlan.md](ReoTestPlan.md), covering per-indexer eligibility flows (renew, expire, recover). The full ReoTestPlan covers additional areas: deployment verification, oracle operations, timeout fail-open, emergency operations, and UI verification.

Each indexer controls their own eligibility via the ORACLE_ROLE granted to their address.

Each test includes CLI commands, verification queries against the network subgraph, and pass/fail criteria.

> All GraphQL queries run against the network subgraph. All addresses must be **lowercase**.

---

## Prerequisites

- Completed [BaselineTestPlan](BaselineTestPlan.md) Cycles 1-4 (indexer staked, provisioned, can allocate)
- `cast` (Foundry) installed for contract interaction
- Indexer private key available for signing transactions

### Environment Configuration (set by coordinator)

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
export REO=0x62c2305739cc75f19a3a6d52387ceb3690d99a99
export REWARDS_MANAGER=0x1f49cae7669086c8ba53cc35d1e9f80176d67e79
```

### Verify Environment

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

| Set | Area                       | Tests     |
| --- | -------------------------- | --------- |
| 1   | Prepare Allocations        | 1.1       |
| 2   | Eligible — Receive Rewards | 2.1 - 2.2 |
| 3   | Ineligible — Verify Denial | 3.1 - 3.2 |
| 4   | Optimistic Recovery        | 4.1 - 4.2 |
| 5   | Validation Disabled        | 5.1       |

**Timing**: Set 1 opens allocations that need epoch maturity. Sets 2-4 are sequential (renew → eligible close → wait for expiry → ineligible close → re-renew → recovery close). Set 5 requires coordinator to toggle validation.

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

## Set 3: Ineligible — Verify Denial

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

### 3.2 Close allocation while ineligible

**Objective**: Verify that an ineligible indexer receives zero indexing rewards when closing an allocation. Denied rewards are routed to the reclaim contract.

**Prerequisites**: `isEligible` returns `false`. Allocation from Set 1 is at least 1 epoch old.

**Steps**:

1. Confirm ineligibility
2. Close an allocation
3. Verify zero rewards

**Command**:

```bash
# Confirm ineligible
cast call $REO "isEligible(address)(bool)" $INDEXER --rpc-url $RPC
# Expected: false

# Close allocation
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
- `indexingRewards` is `0`
- Contrast with Set 2.2 where `indexingRewards` was non-zero

---

## Set 4: Optimistic Recovery

Eligibility denial is **optimistic**: rewards accrue to allocations during ineligible periods and are paid in full when the indexer closes while eligible. This is the key behavioral difference from subgraph denial.

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
