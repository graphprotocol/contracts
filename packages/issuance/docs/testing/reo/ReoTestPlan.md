# REO Test Plan: Rewards Eligibility Oracle

> **Navigation**: [← Back to REO Testing](README.md) | [BaselineTestPlan](BaselineTestPlan.md)

Tests specific to the Rewards Eligibility Oracle upgrade. Run these **after** the [baseline tests](./BaselineTestPlan.md) pass to confirm standard indexer operations are unaffected.

> All contract reads use `cast call`. All addresses must be **lowercase**. Replace placeholder addresses with actual deployed addresses for your network.

## Contract Addresses

| Contract                         | Arbitrum Sepolia                             | Arbitrum One |
| -------------------------------- | -------------------------------------------- | ------------ |
| RewardsEligibilityOracle (proxy) | `0x62c2305739cc75f19a3a6d52387ceb3690d99a99` | TBD          |
| RewardsManager (proxy)           | `0x1f49cae7669086c8ba53cc35d1e9f80176d67e79` | TBD          |
| GraphToken (L2)                  | `0xf8c05dcf59e8b28bfd5eed176c562bebcfc7ac04` | TBD          |

**Address sources**: `packages/issuance/addresses.json` (REO), `packages/horizon/addresses.json` (RewardsManager, GraphToken) in the `post-audit` worktree.

### RPC

| Network          | RPC URL                                  |
| ---------------- | ---------------------------------------- |
| Arbitrum Sepolia | `https://sepolia-rollup.arbitrum.io/rpc` |

### Hardhat Tasks

The deployment package provides Hardhat tasks that read from the address books and handle governance workflow automatically. Run from `packages/deployment` in the `post-audit` worktree:

```bash
npx hardhat reo:status  --network arbitrumSepolia   # Full status: config, oracle activity, role holders
npx hardhat reo:enable  --network arbitrumSepolia   # Enable eligibility validation (requires OPERATOR_ROLE)
npx hardhat reo:disable --network arbitrumSepolia   # Disable eligibility validation (requires OPERATOR_ROLE)
```

These are alternatives to the raw `cast` commands used below. `reo:status` in particular is useful as a quick check at any point during testing.

---

## Testing Approach

**Multi-indexer cycling**: Three indexers cycle through eligibility states individually (not simultaneously). Each indexer transitions through eligible/ineligible states in sequence, allowing controlled observation of each transition.

| Phase | Indexer A            | Indexer B            | Indexer C            |
| ----- | -------------------- | -------------------- | -------------------- |
| 1     | Eligible             | --                   | --                   |
| 2     | Ineligible (expired) | Eligible             | --                   |
| 3     | Re-renewed           | Ineligible (expired) | Eligible             |
| 4     | Eligible             | Re-renewed           | Ineligible (expired) |

**Oracle control**: Use a dedicated test oracle account (fake oracle) to manually control eligibility state transitions rather than relying on the actual reporting software. Grant ORACLE_ROLE to this account in Cycle 3.

**Testnet parameter acceleration**: Reduce time-dependent parameters for practical testing:

| Parameter             | Default              | Test Value              | Purpose                                    |
| --------------------- | -------------------- | ----------------------- | ------------------------------------------ |
| Eligibility period    | 14 days (1,209,600s) | 5-10 minutes (300-600s) | Allow expiration within a test session     |
| Oracle update timeout | 7 days (604,800s)    | 5-10 minutes (300-600s) | Allow fail-open testing without long waits |

> Testnet epochs are ~554 blocks (~110 minutes) vs ~6,646 blocks (~24h) on mainnet. Issuance rates are adjusted proportionally.

**Stakeholder coordination**: Discord channel for testing. UI/Explorer team and network subgraph team monitor throughout for display accuracy during denial scenarios.

---

## Execution Phases

| Phase       | Cycles | Activity                                                                            |
| ----------- | ------ | ----------------------------------------------------------------------------------- |
| Setup       | —      | Run [BaselineTestPlan](BaselineTestPlan.md) Cycles 1-7, confirm testnet environment |
| REO Phase 1 | 1-3    | Deployment verification, default state, oracle setup                                |
| REO Phase 2 | 4-5    | Validation enabled, timeout fail-open, begin indexer cycling                        |
| REO Phase 3 | 6      | Integration with rewards, multi-indexer denial/renewal cycling                      |
| REO Phase 4 | 7-8    | Emergency ops, UI/subgraph verification                                             |
| Wrap-up     | —      | Results review, cleanup checklist, mainnet readiness assessment                     |

---

## Execution Notes

### Roles needed

Testing requires access to three roles on the REO contract. On Arbitrum Sepolia:

| Role          | Needed for                                                | Current holder                                                |
| ------------- | --------------------------------------------------------- | ------------------------------------------------------------- |
| OPERATOR_ROLE | Enable/disable validation, set periods, grant ORACLE_ROLE | NetworkOperator: `0xade6b8eb69a49b56929c1d4f4b428d791861db6f` |
| ORACLE_ROLE   | Renew indexer eligibility                                 | Not yet assigned -- must be granted in Cycle 3                |
| PAUSE_ROLE    | Pause/unpause (Cycle 8)                                   | Check with `reo:status`                                       |

The tester needs the NetworkOperator key (or governance access) to execute Cycles 3-5 and 8. If the tester doesn't hold OPERATOR_ROLE directly, the Hardhat tasks generate governance TX files for Safe multisig execution.

### Advance planning for Cycle 6

Cycle 6 tests reward integration with live indexers. These tests take multiple epochs (~110 minutes each on Sepolia) and require allocations that were opened **before** validation was enabled. Plan ahead:

1. During **Cycle 2** (validation still disabled): open allocations for at least two indexers on rewarded deployments -- one that will be renewed (for test 6.1) and one that will NOT be renewed (for test 6.2)
2. These allocations need to mature for 2-3 epochs before they can be closed in Cycle 6
3. When you enable validation in **Cycle 4**, the non-renewed indexer becomes ineligible while their allocation is still open -- this is the setup for test 6.2

### Parameter changes during testing

Tests 4.4, 5.1, and 8.1 temporarily modify live parameters (eligibility period, oracle timeout, pause state). Each test includes a restore step. If a session is interrupted:

```bash
# Verify and restore defaults
npx hardhat reo:status --network arbitrumSepolia

# If needed, restore manually (as operator):
cast send <REO_PROXY> "setEligibilityPeriod(uint256)" 1209600 --rpc-url <RPC> --private-key <OPERATOR_KEY>
cast send <REO_PROXY> "setOracleUpdateTimeout(uint256)" 604800 --rpc-url <RPC> --private-key <OPERATOR_KEY>
cast send <REO_PROXY> "unpause()" --rpc-url <RPC> --private-key <PAUSE_KEY>
```

---

## Test Sequence Overview

| Cycle | Area                                             | Tests     | Notes                                       |
| ----- | ------------------------------------------------ | --------- | ------------------------------------------- |
| 1     | Deployment Verification                          | 1.1 - 1.5 | Read-only, no role access needed            |
| 2     | Eligibility: Default State (Validation Disabled) | 2.1 - 2.3 | Open allocations here for Cycle 6           |
| 3     | Oracle Operations                                | 3.1 - 3.5 | Requires OPERATOR_ROLE + ORACLE_ROLE        |
| 4     | Eligibility: Validation Enabled                  | 4.1 - 4.4 | Requires OPERATOR_ROLE; 4.4 changes params  |
| 5     | Eligibility: Timeout Fail-Open                   | 5.1 - 5.2 | Requires OPERATOR_ROLE; 5.1 changes params  |
| 6     | Integration with Rewards                         | 6.1 - 6.6 | Requires mature allocations from Cycle 2    |
| 7     | Emergency Operations                             | 7.1 - 7.3 | Requires PAUSE_ROLE; changes live state     |
| 8     | UI and Subgraph Verification                     | 8.1 - 8.3 | Coordinate with Explorer and subgraph teams |

---

## Cycle 1: Deployment Verification

> Tests 1.2, 1.3, and 1.5 can be checked in one step with `npx hardhat reo:status --network arbitrumSepolia`, which displays role holders, configuration, and contract state. The individual `cast` commands below are useful for scripted or more granular verification.

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

**Prerequisites**: Indexer has an active allocation on a rewarded deployment, open for at least 2 epochs. This should already exist from running [Baseline Cycle 4](./BaselineTestPlan.md#cycle-4-allocation-management).

> **Cross-reference**: The allocations opened here (and in [Baseline Cycles 4-5](./BaselineTestPlan.md#cycle-4-allocation-management)) serve as setup for [Cycle 6](#cycle-6-integration-with-rewards) reward integration tests. Open extra allocations now for the indexers you plan to cycle through eligibility states.

**Steps**: Close the allocation per [Baseline 5.2](./BaselineTestPlan.md#52-close-allocation-and-collect-indexing-rewards) and verify rewards.

> **Advance setup for Cycle 6**: Before moving to Cycle 3, open allocations for the indexers you plan to use in Cycle 6. You need at least:
>
> - One allocation for a **renewed** indexer (test 6.1 -- will receive rewards)
> - One allocation for a **non-renewed** indexer (test 6.2 -- will be denied rewards)
>
> These allocations must mature for 2-3 epochs before Cycle 6. Since validation is still disabled, both will accrue potential rewards. Use [Baseline 4.2](./BaselineTestPlan.md#42-create-allocation-manually) to create them.

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

> **Before enabling**: Confirm the allocations you opened during Cycle 2 for Cycle 6 testing are still active. Once validation is enabled, any non-renewed indexer with an open allocation becomes ineligible for rewards -- this is the intended setup for test 6.2.

**Steps**:

```bash
# Enable validation (alternative: npx hardhat reo:enable --network arbitrumSepolia)
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

These tests verify the end-to-end interaction between the REO and the rewards system using live indexers.

> **Timing**: These tests require allocations that have been open for 2-3 epochs (~3.5-5.5 hours on Sepolia). The allocations should have been opened during Cycle 2, before validation was enabled. If they weren't, you'll need to open them now and wait before proceeding. Cycles 7 and 8 can be run while waiting.

### 6.1 Eligible indexer receives indexing rewards

**Objective**: Confirm that a renewed (eligible) indexer receives rewards when closing an allocation.

**Prerequisites**: Validation enabled (Cycle 4). Indexer renewed by oracle (Cycle 3). Indexer has an active allocation open for several epochs on a rewarded deployment (opened during Cycle 2).

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

**Prerequisites**: Validation enabled (Cycle 4). Indexer has NOT been renewed by the oracle. Indexer has an active allocation on a rewarded deployment that was opened during Cycle 2 (before validation was enabled).

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

> **Timing**: This test requires opening a new allocation and waiting 2-3 epochs (~3.5-5.5 hours). It can be run as the final validation step, or skipped on testnet if time is constrained and covered by the combination of 6.2 + Cycle 3 (which together demonstrate the renewal mechanism works).

**Steps**:

1. Confirm indexer is currently ineligible (the indexer from test 6.2)
2. Renew the indexer via oracle (as in test 3.2)
3. Confirm eligibility restored: `isEligible` = `true`
4. Open new allocation, wait 2-3 epochs, close, check rewards

**Pass Criteria**:

- After renewal: `isEligible` = `true`
- New allocation closure yields non-zero `indexingRewards`

---

### 6.5 View functions reflect zero for ineligible indexer

**Objective**: Verify that RewardsManager view functions do not over-report claimable rewards for an ineligible indexer. Previously, view functions could show unclaimable balances, misleading indexers into thinking they had earned rewards.

**Prerequisites**: Validation enabled. Indexer is ineligible. Indexer has an active allocation that has been open several epochs.

**Steps**:

1. Confirm ineligibility: `isEligible(indexer)` = `false`
2. Query the view function for pending rewards on the allocation

```bash
# Check pending rewards for an active allocation
cast call <REWARDS_MANAGER> "getRewards(bytes32)(uint256)" <ALLOCATION_ID> --rpc-url <RPC>
```

**Pass Criteria**:

- Returns `0` (or near-zero), not the full accumulated amount
- This prevents the UI from displaying rewards the indexer cannot actually claim

---

### 6.6 Eligibility denial is optimistic -- full rewards after re-renewal

**Objective**: Verify that rewards continue accumulating during an ineligible period (optimistic model). After re-renewal, closing the allocation yields the full accumulated amount including epochs where the indexer was ineligible. This differs from subgraph denial, which permanently stops accumulation.

**Prerequisites**: Indexer has an active allocation open for several epochs. Indexer was eligible when allocation was opened.

**Steps**:

1. Confirm indexer is currently eligible with an active allocation
2. Let eligibility expire (or reduce eligibility period as in test 4.4)
3. Confirm `isEligible(indexer)` = `false`
4. Wait 1-2 additional epochs while ineligible
5. Re-renew the indexer via oracle
6. Confirm `isEligible(indexer)` = `true`
7. Close allocation and check rewards

**Pass Criteria**:

- `indexingRewards` reflects the full allocation lifetime (eligible + ineligible epochs)
- Amount is comparable to what a continuously-eligible indexer would earn for the same period
- Temporary ineligibility does not cause permanent reward loss

---

## Cycle 7: Emergency Operations

### 7.1 Pause REO

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

### 7.2 Disable eligibility validation (emergency override)

**Objective**: Verify an operator can disable validation to immediately make all indexers eligible.

**Steps**:

```bash
# Disable validation (alternative: npx hardhat reo:disable --network arbitrumSepolia)
cast send <REO_PROXY> "setEligibilityValidation(bool)" false --rpc-url <RPC> --private-key <OPERATOR_KEY>

# Previously ineligible indexer should now be eligible
cast call <REO_PROXY> "isEligible(address)(bool)" <PREVIOUSLY_INELIGIBLE_INDEXER> --rpc-url <RPC>
```

**Pass Criteria**:

- Transaction succeeds
- All indexers return `isEligible` = `true`

---

### 7.3 Access control prevents unauthorized configuration

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

## Cycle 8: UI and Subgraph Verification

These tests verify that the Graph Explorer and network subgraph correctly reflect eligibility states and denial scenarios. Run these in coordination with the Explorer and subgraph teams.

### 8.1 Explorer displays correct rewards during denial

**Objective**: Verify that the Graph Explorer does not show incorrect indexing reward amounts when an indexer is ineligible and claims are denied.

**Prerequisites**: At least one indexer is ineligible with an active allocation. Explorer team monitoring.

**Steps**:

1. Open Explorer to the ineligible indexer's profile
2. Check displayed pending rewards for active allocations
3. Close allocation (will be denied rewards)
4. Verify Explorer updates to reflect the actual outcome (zero rewards)

**Pass Criteria**:

- Explorer does not display inflated or false pending rewards for ineligible indexers
- After allocation closure with denial, Explorer shows `0` indexing rewards for that allocation
- No discrepancy between on-chain state and Explorer display

---

### 8.2 Network subgraph reflects eligibility transitions

**Objective**: Verify the network subgraph correctly indexes eligibility renewal events and displays accurate stake/delegation amounts through state transitions.

**Steps**:

1. Renew indexer eligibility via oracle
2. Query network subgraph for the indexer
3. Let eligibility expire
4. Query again and compare

```graphql
{
  indexers(where: { id: "INDEXER_ADDRESS" }) {
    id
    stakedTokens
    delegatedTokens
    allocatedTokens
    rewardsEarned
  }
}
```

**Pass Criteria**:

- `stakedTokens` and `delegatedTokens` remain accurate regardless of eligibility state
- Subgraph does not show incorrect amounts during eligibility transitions
- No indexing errors in the subgraph during REO-related transactions

---

### 8.3 Denied transaction appears correct in Explorer history

**Objective**: When an ineligible indexer closes an allocation and rewards are denied, the transaction should not appear "successful" in a way that misleads the indexer.

**Steps**:

1. Close allocation for an ineligible indexer
2. Check the transaction in Explorer's history view
3. Verify the displayed outcome matches reality (0 rewards)

**Pass Criteria**:

- Transaction status is clear (not misleadingly shown as a successful reward claim)
- Reward amount displayed is `0` or clearly indicates denial
- Explorer team confirms no confusing UX for the indexer

---

## Post-Testing Cleanup Checklist

Run `npx hardhat reo:status --network arbitrumSepolia` to verify. Ensure the REO is left in the expected state:

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

---

## Related Documentation

- [← Back to REO Testing](README.md)
- [BaselineTestPlan.md](BaselineTestPlan.md) - Baseline operational tests (run first)

---

_Derived from REO contract specification and audit reports. Source contracts: `/packages/issuance/contracts/eligibility/`_
