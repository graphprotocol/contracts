# REO Test Plan: Rewards Eligibility Oracle

> **Navigation**: [← Back to REO Testing](README.md) | [Goal](Goal.md) | [Status](Status.md) | [BaselineTestPlan](BaselineTestPlan.md)

Tests specific to the Rewards Eligibility Oracle upgrade. Run these **after** the [baseline tests](./BaselineTestPlan.md) pass to confirm standard indexer operations are unaffected.

> All contract reads use `cast call`. All addresses must be **lowercase**. Replace placeholder addresses with actual deployed addresses for your network.

## Contract Addresses

Fill in per network before testing:

| Contract                         | Arbitrum Sepolia                             | Arbitrum One |
| -------------------------------- | -------------------------------------------- | ------------ |
| RewardsEligibilityOracle (proxy) | `0x62c2305739cc75f19a3a6d52387ceb3690d99a99` | TBD          |
| IssuanceAllocator (proxy)        | TBD                                          | TBD          |
| RewardsManager (proxy)           | TBD                                          | TBD          |
| GraphToken                       | TBD                                          | TBD          |

---

## Test Sequence Overview

| Cycle | Area                                             | Tests     |
| ----- | ------------------------------------------------ | --------- |
| 1     | Deployment Verification                          | 1.1 - 1.5 |
| 2     | Eligibility: Default State (Validation Disabled) | 2.1 - 2.3 |
| 3     | Oracle Operations                                | 3.1 - 3.5 |
| 4     | Eligibility: Validation Enabled                  | 4.1 - 4.4 |
| 5     | Eligibility: Timeout Fail-Open                   | 5.1 - 5.2 |
| 6     | Integration with Rewards                         | 6.1 - 6.4 |
| 7     | IssuanceAllocator                                | 7.1 - 7.4 |
| 8     | Emergency Operations                             | 8.1 - 8.3 |

---

## Cycle 1: Deployment Verification

### 1.1 Verify proxy and implementation

**Objective**: Confirm the REO proxy points to the correct implementation and bytecode matches expectations.

**Steps**:

1. Query the proxy's implementation address
2. Compare deployed bytecode hash against expected artifact

```bash
# Get implementation address from proxy admin
cast call <PROXY_ADMIN> "getProxyImplementation(address)" <REO_PROXY> --rpc-url <RPC>

# Get deployed bytecode hash
cast keccak $(cast code <IMPLEMENTATION_ADDRESS> --rpc-url <RPC>)
```

**Pass Criteria**:

- Implementation address matches address book (`0x4eb1de98440a39339817bdeeb3b3fff410b0b924` on Sepolia)
- Bytecode hash matches expected artifact hash

---

### 1.2 Verify role assignments

**Objective**: Confirm the correct accounts hold each role and the deployer has been removed.

**Steps**:

```bash
# Role constants
GOVERNOR_ROLE=0x0000...  # DEFAULT_ADMIN_ROLE = 0x00
OPERATOR_ROLE=$(cast keccak "OPERATOR_ROLE")
ORACLE_ROLE=$(cast keccak "ORACLE_ROLE")
PAUSE_ROLE=$(cast keccak "PAUSE_ROLE")

# Check role assignments
cast call <REO_PROXY> "hasRole(bytes32,address)(bool)" $GOVERNOR_ROLE <GOVERNOR_ADDRESS> --rpc-url <RPC>
cast call <REO_PROXY> "hasRole(bytes32,address)(bool)" $OPERATOR_ROLE <OPERATOR_ADDRESS> --rpc-url <RPC>
cast call <REO_PROXY> "hasRole(bytes32,address)(bool)" $PAUSE_ROLE <PAUSE_GUARDIAN> --rpc-url <RPC>

# Verify deployer does NOT have governor role
cast call <REO_PROXY> "hasRole(bytes32,address)(bool)" $GOVERNOR_ROLE <DEPLOYER_ADDRESS> --rpc-url <RPC>
```

**Pass Criteria**:

- Governor address has GOVERNOR_ROLE: `true`
- Operator address has OPERATOR_ROLE: `true`
- Pause guardian has PAUSE_ROLE: `true`
- Deployer does NOT have GOVERNOR_ROLE: `false`

---

### 1.3 Verify default parameters

**Objective**: Confirm the REO is deployed with expected default configuration.

**Steps**:

```bash
cast call <REO_PROXY> "getEligibilityPeriod()(uint256)" --rpc-url <RPC>
cast call <REO_PROXY> "getOracleUpdateTimeout()(uint256)" --rpc-url <RPC>
cast call <REO_PROXY> "getEligibilityValidation()(bool)" --rpc-url <RPC>
cast call <REO_PROXY> "getLastOracleUpdateTime()(uint256)" --rpc-url <RPC>
```

**Pass Criteria**:

- `eligibilityPeriod` = `1209600` (14 days in seconds)
- `oracleUpdateTimeout` = `604800` (7 days in seconds)
- `eligibilityValidation` = `false` (disabled by default)
- `lastOracleUpdateTime` = `0` (no oracle updates yet) or reflects actual oracle activity

---

### 1.4 Verify RewardsManager integration

**Objective**: Confirm the RewardsManager is configured to use the REO for eligibility checks.

**Steps**:

```bash
cast call <REWARDS_MANAGER> "getRewardsEligibilityOracle()(address)" --rpc-url <RPC>
```

**Pass Criteria**:

- Returns the REO proxy address

---

### 1.5 Verify contract is not paused

**Objective**: Confirm the REO is operational.

**Steps**:

```bash
cast call <REO_PROXY> "paused()(bool)" --rpc-url <RPC>
```

**Pass Criteria**:

- Returns `false`

---

## Cycle 2: Eligibility -- Default State (Validation Disabled)

### 2.1 All indexers eligible when validation disabled

**Objective**: With validation disabled (default), every indexer should be eligible regardless of renewal status.

**Steps**:

1. Confirm validation is disabled
2. Check eligibility for a known indexer
3. Check eligibility for a random address that has never been renewed

```bash
# Confirm validation disabled
cast call <REO_PROXY> "getEligibilityValidation()(bool)" --rpc-url <RPC>

# Known indexer
cast call <REO_PROXY> "isEligible(address)(bool)" <KNOWN_INDEXER> --rpc-url <RPC>

# Random/never-renewed address
cast call <REO_PROXY> "isEligible(address)(bool)" 0x0000000000000000000000000000000000000001 --rpc-url <RPC>
```

**Pass Criteria**:

- `getEligibilityValidation()` = `false`
- Both addresses return `isEligible` = `true`

---

### 2.2 Indexer with no renewal history is eligible

**Objective**: Confirm that an indexer with zero renewal timestamp is still eligible when validation is disabled.

**Steps**:

```bash
cast call <REO_PROXY> "getEligibilityRenewalTime(address)(uint256)" <NEVER_RENEWED_INDEXER> --rpc-url <RPC>
cast call <REO_PROXY> "isEligible(address)(bool)" <NEVER_RENEWED_INDEXER> --rpc-url <RPC>
```

**Pass Criteria**:

- `getEligibilityRenewalTime` = `0`
- `isEligible` = `true`

---

### 2.3 Rewards still flow with validation disabled

**Objective**: Confirm the baseline rewards flow is unaffected by the REO when validation is off.

**Steps**: Run [Baseline Test Plan Cycle 5.2](./BaselineTestPlan.md#52-close-allocation-and-collect-indexing-rewards) (close allocation and collect rewards).

**Pass Criteria**:

- Indexing rewards are non-zero on allocation closure
- No change in behavior from baseline

---

## Cycle 3: Oracle Operations

### 3.1 Grant oracle role

**Objective**: Verify an operator can grant ORACLE_ROLE to an oracle address.

**Prerequisites**: Transaction signed by OPERATOR_ROLE holder.

**Steps**:

```bash
# Grant oracle role (as operator)
cast send <REO_PROXY> "grantRole(bytes32,address)" $ORACLE_ROLE <ORACLE_ADDRESS> --rpc-url <RPC> --private-key <OPERATOR_KEY>

# Verify
cast call <REO_PROXY> "hasRole(bytes32,address)(bool)" $ORACLE_ROLE <ORACLE_ADDRESS> --rpc-url <RPC>
```

**Pass Criteria**:

- Transaction succeeds
- `hasRole` returns `true` for the oracle address

---

### 3.2 Renew single indexer eligibility

**Objective**: Verify an oracle can renew eligibility for a single indexer.

**Prerequisites**: Caller has ORACLE_ROLE.

**Steps**:

```bash
# Renew eligibility for one indexer
cast send <REO_PROXY> "renewIndexerEligibility(address[],bytes)" "[<INDEXER_ADDRESS>]" "0x" --rpc-url <RPC> --private-key <ORACLE_KEY>

# Check renewal timestamp
cast call <REO_PROXY> "getEligibilityRenewalTime(address)(uint256)" <INDEXER_ADDRESS> --rpc-url <RPC>

# Check last oracle update time
cast call <REO_PROXY> "getLastOracleUpdateTime()(uint256)" --rpc-url <RPC>
```

**Verification**: Check for emitted events:

- `IndexerEligibilityRenewed(indexer, oracle)`
- `IndexerEligibilityData(oracle, data)`

**Pass Criteria**:

- Transaction succeeds, returns count `1`
- `getEligibilityRenewalTime` is approximately `block.timestamp` of the renewal tx
- `lastOracleUpdateTime` updated to the same timestamp
- Events emitted correctly

---

### 3.3 Renew multiple indexers in batch

**Objective**: Verify batch renewal works correctly.

**Steps**:

```bash
cast send <REO_PROXY> "renewIndexerEligibility(address[],bytes)" "[<INDEXER_1>,<INDEXER_2>,<INDEXER_3>]" "0x" --rpc-url <RPC> --private-key <ORACLE_KEY>
```

**Verification**: Check renewal timestamps for all three indexers.

**Pass Criteria**:

- Transaction succeeds, returns count `3`
- All three indexers have updated renewal timestamps
- One `IndexerEligibilityRenewed` event per indexer

---

### 3.4 Zero addresses skipped in renewal

**Objective**: Verify zero addresses in the renewal array are silently skipped.

**Steps**:

```bash
cast send <REO_PROXY> "renewIndexerEligibility(address[],bytes)" "[0x0000000000000000000000000000000000000000,<INDEXER_ADDRESS>]" "0x" --rpc-url <RPC> --private-key <ORACLE_KEY>
```

**Pass Criteria**:

- Transaction succeeds, returns count `1` (not 2)
- Only the non-zero indexer has a `IndexerEligibilityRenewed` event

---

### 3.5 Unauthorized renewal reverts

**Objective**: Verify that accounts without ORACLE_ROLE cannot renew eligibility.

**Steps**:

```bash
# Attempt renewal from a non-oracle account
cast send <REO_PROXY> "renewIndexerEligibility(address[],bytes)" "[<INDEXER_ADDRESS>]" "0x" --rpc-url <RPC> --private-key <NON_ORACLE_KEY>
```

**Pass Criteria**:

- Transaction reverts with AccessControl error

---

## Cycle 4: Eligibility -- Validation Enabled

### 4.1 Enable eligibility validation

**Objective**: Verify an operator can enable validation, switching from "all eligible" to oracle-based eligibility.

**Prerequisites**: OPERATOR_ROLE holder. Some indexers should have been renewed (Cycle 3), others not.

**Steps**:

```bash
# Enable validation
cast send <REO_PROXY> "setEligibilityValidation(bool)" true --rpc-url <RPC> --private-key <OPERATOR_KEY>

# Verify
cast call <REO_PROXY> "getEligibilityValidation()(bool)" --rpc-url <RPC>
```

**Verification**: Check for `EligibilityValidationUpdated(true)` event.

**Pass Criteria**:

- Transaction succeeds
- `getEligibilityValidation()` = `true`

---

### 4.2 Renewed indexer is eligible

**Objective**: After enabling validation, a recently renewed indexer should still be eligible.

**Prerequisites**: Indexer was renewed in Cycle 3. Validation is enabled (4.1).

**Steps**:

```bash
cast call <REO_PROXY> "isEligible(address)(bool)" <RENEWED_INDEXER> --rpc-url <RPC>
cast call <REO_PROXY> "getEligibilityRenewalTime(address)(uint256)" <RENEWED_INDEXER> --rpc-url <RPC>
```

**Pass Criteria**:

- `isEligible` = `true`
- `getEligibilityRenewalTime` is within the last `eligibilityPeriod` (14 days)

---

### 4.3 Non-renewed indexer is NOT eligible

**Objective**: An indexer that was never renewed should be ineligible when validation is enabled.

**Steps**:

```bash
cast call <REO_PROXY> "isEligible(address)(bool)" <NEVER_RENEWED_INDEXER> --rpc-url <RPC>
cast call <REO_PROXY> "getEligibilityRenewalTime(address)(uint256)" <NEVER_RENEWED_INDEXER> --rpc-url <RPC>
```

**Pass Criteria**:

- `isEligible` = `false`
- `getEligibilityRenewalTime` = `0`

---

### 4.4 Eligibility expires after period

**Objective**: Verify that an indexer's eligibility expires when the eligibility period has passed since their last renewal.

**Approach**: This is easiest to test by temporarily reducing the eligibility period to a short duration.

**Steps**:

1. Renew an indexer's eligibility
2. Reduce eligibility period to a short value (e.g., 60 seconds)
3. Wait for the period to elapse
4. Check eligibility

```bash
# Renew indexer
cast send <REO_PROXY> "renewIndexerEligibility(address[],bytes)" "[<INDEXER_ADDRESS>]" "0x" --rpc-url <RPC> --private-key <ORACLE_KEY>

# Reduce period to 60 seconds (as operator)
cast send <REO_PROXY> "setEligibilityPeriod(uint256)" 60 --rpc-url <RPC> --private-key <OPERATOR_KEY>

# Immediately check -- should still be eligible
cast call <REO_PROXY> "isEligible(address)(bool)" <INDEXER_ADDRESS> --rpc-url <RPC>

# Wait 60+ seconds, then check again
sleep 65
cast call <REO_PROXY> "isEligible(address)(bool)" <INDEXER_ADDRESS> --rpc-url <RPC>

# IMPORTANT: Restore eligibility period to default
cast send <REO_PROXY> "setEligibilityPeriod(uint256)" 1209600 --rpc-url <RPC> --private-key <OPERATOR_KEY>
```

**Pass Criteria**:

- First check (immediately after renewal): `isEligible` = `true`
- Second check (after period elapsed): `isEligible` = `false`
- Eligibility period restored to default

---

## Cycle 5: Eligibility -- Timeout Fail-Open

### 5.1 Oracle timeout makes all indexers eligible

**Objective**: Verify the fail-open mechanism: if no oracle updates occur for longer than `oracleUpdateTimeout`, all indexers become eligible.

**Approach**: Reduce the oracle timeout to a short duration and wait.

**Prerequisites**: Validation enabled (4.1). At least one indexer is NOT renewed (should be ineligible).

**Steps**:

```bash
# Confirm non-renewed indexer is currently ineligible
cast call <REO_PROXY> "isEligible(address)(bool)" <NEVER_RENEWED_INDEXER> --rpc-url <RPC>
# Expected: false

# Reduce oracle timeout to 60 seconds (as operator)
cast send <REO_PROXY> "setOracleUpdateTimeout(uint256)" 60 --rpc-url <RPC> --private-key <OPERATOR_KEY>

# Wait for timeout to elapse
sleep 65

# Check -- should now be eligible due to fail-open
cast call <REO_PROXY> "isEligible(address)(bool)" <NEVER_RENEWED_INDEXER> --rpc-url <RPC>

# IMPORTANT: Restore oracle timeout to default
cast send <REO_PROXY> "setOracleUpdateTimeout(uint256)" 604800 --rpc-url <RPC> --private-key <OPERATOR_KEY>
```

**Pass Criteria**:

- Before timeout: `isEligible` = `false`
- After timeout: `isEligible` = `true`
- Timeout restored to default

---

### 5.2 Oracle renewal resets timeout

**Objective**: Verify that an oracle renewal resets the `lastOracleUpdateTime`, closing the fail-open window.

**Steps**:

```bash
# Record current lastOracleUpdateTime
cast call <REO_PROXY> "getLastOracleUpdateTime()(uint256)" --rpc-url <RPC>

# Renew any indexer
cast send <REO_PROXY> "renewIndexerEligibility(address[],bytes)" "[<INDEXER_ADDRESS>]" "0x" --rpc-url <RPC> --private-key <ORACLE_KEY>

# Check lastOracleUpdateTime again
cast call <REO_PROXY> "getLastOracleUpdateTime()(uint256)" --rpc-url <RPC>
```

**Pass Criteria**:

- `lastOracleUpdateTime` updated to the block timestamp of the renewal transaction

---

## Cycle 6: Integration with Rewards

These tests verify the end-to-end interaction between the REO and the rewards system.

### 6.1 Eligible indexer receives indexing rewards

**Objective**: Confirm that a renewed (eligible) indexer receives rewards when closing an allocation.

**Prerequisites**: Validation enabled. Indexer renewed by oracle. Indexer has an active allocation open for several epochs on a rewarded deployment.

**Steps**:

1. Confirm eligibility: `isEligible(indexer)` = `true`
2. Close allocation per [Baseline 5.2](./BaselineTestPlan.md#52-close-allocation-and-collect-indexing-rewards)
3. Check rewards

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
- Rewards amount is consistent with allocation size and epoch duration

---

### 6.2 Ineligible indexer denied rewards

**Objective**: Confirm that a non-renewed (ineligible) indexer receives zero rewards when closing an allocation.

**Prerequisites**: Validation enabled. Indexer has NOT been renewed (or renewal expired). Indexer has an active allocation on a rewarded deployment.

**Steps**:

1. Confirm ineligibility: `isEligible(indexer)` = `false`
2. Close allocation
3. Check rewards

**Pass Criteria**:

- `indexingRewards` = `0`
- Allocation still transitions to `Closed` status (closure succeeds, just no rewards)

---

### 6.3 Reclaimed rewards flow to reclaim contract

**Objective**: When an ineligible indexer is denied rewards, verify the denied rewards are routed to the `ReclaimedRewardsForIndexerIneligible` contract.

**Prerequisites**: Same as 6.2.

**Steps**:

1. Close allocation for ineligible indexer
2. Check the reclaim contract balance or events

```bash
# Check for RewardsDeniedDueToEligibility event on RewardsManager
# (implementation detail -- exact event name may vary)
cast logs --from-block <CLOSE_TX_BLOCK> --to-block <CLOSE_TX_BLOCK> --address <REWARDS_MANAGER> --rpc-url <RPC>
```

**Pass Criteria**:

- Denied rewards event emitted
- Reclaim contract receives the tokens that would have been the indexer's rewards

---

### 6.4 Re-renewal restores reward eligibility

**Objective**: After an indexer's eligibility expires and they are denied rewards, verify that a new oracle renewal restores their ability to earn rewards.

**Steps**:

1. Confirm indexer is currently ineligible
2. Renew the indexer via oracle
3. Confirm eligibility restored: `isEligible` = `true`
4. Open new allocation, wait, close, check rewards

**Pass Criteria**:

- After renewal: `isEligible` = `true`
- New allocation closure yields non-zero `indexingRewards`

---

## Cycle 7: IssuanceAllocator

### 7.1 Verify IssuanceAllocator configuration

**Objective**: Confirm the IssuanceAllocator is correctly configured with RewardsManager as a self-minting target.

**Steps**:

```bash
# Check issuance rate
cast call <ISSUANCE_ALLOCATOR> "getIssuancePerBlock()(uint256)" --rpc-url <RPC>

# Check RewardsManager target allocation
cast call <ISSUANCE_ALLOCATOR> "getTargetIssuancePerBlock(address)(uint256,uint256)" <REWARDS_MANAGER> --rpc-url <RPC>

# Check if IssuanceAllocator is minter
cast call <GRAPH_TOKEN> "isMinter(address)(bool)" <ISSUANCE_ALLOCATOR> --rpc-url <RPC>

# Check RewardsManager knows about IssuanceAllocator
cast call <REWARDS_MANAGER> "getIssuanceAllocator()(address)" --rpc-url <RPC>
```

**Pass Criteria**:

- `getIssuancePerBlock` returns the expected issuance rate
- RewardsManager has self-minting allocation = 100% of issuance
- IssuanceAllocator is a minter on GraphToken
- RewardsManager points to IssuanceAllocator

---

### 7.2 Distribute issuance

**Objective**: Verify `distributeIssuance()` executes correctly.

**Steps**:

```bash
# Anyone can call this
cast send <ISSUANCE_ALLOCATOR> "distributeIssuance()" --rpc-url <RPC> --private-key <ANY_KEY>
```

**Pass Criteria**:

- Transaction succeeds
- No unexpected reverts

---

### 7.3 Verify issuance rate matches RewardsManager

**Objective**: Confirm the issuance rate in IssuanceAllocator matches what RewardsManager expects.

**Steps**:

```bash
# IssuanceAllocator rate
cast call <ISSUANCE_ALLOCATOR> "getIssuancePerBlock()(uint256)" --rpc-url <RPC>

# RewardsManager effective rate
cast call <REWARDS_MANAGER> "issuancePerBlock()(uint256)" --rpc-url <RPC>
```

**Pass Criteria**:

- Both values are identical

---

### 7.4 IssuanceAllocator not paused

**Objective**: Confirm the IssuanceAllocator is operational.

**Steps**:

```bash
cast call <ISSUANCE_ALLOCATOR> "paused()(bool)" --rpc-url <RPC>
```

**Pass Criteria**:

- Returns `false`

---

## Cycle 8: Emergency Operations

### 8.1 Pause REO

**Objective**: Verify the pause guardian can pause the REO.

**Prerequisites**: Caller has PAUSE_ROLE.

**Steps**:

```bash
# Pause
cast send <REO_PROXY> "pause()" --rpc-url <RPC> --private-key <PAUSE_KEY>

# Verify paused
cast call <REO_PROXY> "paused()(bool)" --rpc-url <RPC>

# View functions should still work
cast call <REO_PROXY> "isEligible(address)(bool)" <INDEXER_ADDRESS> --rpc-url <RPC>

# IMPORTANT: Unpause when done
cast send <REO_PROXY> "unpause()" --rpc-url <RPC> --private-key <PAUSE_KEY>
```

**Pass Criteria**:

- Pause succeeds, `paused()` = `true`
- View functions (`isEligible`) still return results
- Oracle write operations (`renewIndexerEligibility`) revert while paused
- Unpause succeeds, `paused()` = `false`

---

### 8.2 Disable eligibility validation (emergency override)

**Objective**: Verify an operator can disable validation to immediately make all indexers eligible.

**Steps**:

```bash
# Disable validation
cast send <REO_PROXY> "setEligibilityValidation(bool)" false --rpc-url <RPC> --private-key <OPERATOR_KEY>

# Previously ineligible indexer should now be eligible
cast call <REO_PROXY> "isEligible(address)(bool)" <PREVIOUSLY_INELIGIBLE_INDEXER> --rpc-url <RPC>
```

**Pass Criteria**:

- Transaction succeeds
- All indexers return `isEligible` = `true`

---

### 8.3 Access control prevents unauthorized configuration

**Objective**: Verify that only authorized roles can perform privileged operations.

**Steps** (all should revert):

```bash
# Non-operator tries to set eligibility period
cast send <REO_PROXY> "setEligibilityPeriod(uint256)" 100 --rpc-url <RPC> --private-key <RANDOM_KEY>

# Non-operator tries to enable validation
cast send <REO_PROXY> "setEligibilityValidation(bool)" true --rpc-url <RPC> --private-key <RANDOM_KEY>

# Non-pause-role tries to pause
cast send <REO_PROXY> "pause()" --rpc-url <RPC> --private-key <RANDOM_KEY>
```

**Pass Criteria**:

- All three transactions revert with AccessControl errors

---

## Post-Testing Cleanup Checklist

After completing all tests, ensure the REO is left in the expected state:

- [ ] `eligibilityValidation` set to intended value (disabled or enabled per rollout plan)
- [ ] `eligibilityPeriod` = `1209600` (14 days)
- [ ] `oracleUpdateTimeout` = `604800` (7 days)
- [ ] Contract is NOT paused
- [ ] Oracle roles assigned to intended oracle addresses only
- [ ] No test accounts retain elevated roles

---

## Monitoring Checklist

After the upgrade is live, continuously monitor:

- [ ] `IndexerEligibilityRenewed` events flowing regularly from oracles
- [ ] `lastOracleUpdateTime` advancing (oracles are active)
- [ ] No `RewardsDeniedDueToEligibility` events for indexers that should be eligible
- [ ] Epoch progression and total rewards issuance unchanged from pre-upgrade baseline
- [ ] IssuanceAllocator `distributeIssuance()` executing without errors

---

## Related Documentation

- [← Back to REO Testing](README.md)
- [Goal.md](Goal.md) - Testing objectives and deliverables
- [Status.md](Status.md) - Current progress and next steps
- [BaselineTestPlan.md](BaselineTestPlan.md) - Baseline operational tests (run first)

---

_Derived from REO contract specification and audit reports. Source contracts: `/packages/issuance/contracts/eligibility/`_
