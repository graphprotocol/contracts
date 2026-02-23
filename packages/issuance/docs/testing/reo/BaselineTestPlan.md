# Indexer Baseline Test Plan: Post-Upgrade Verification

> **Navigation**: [← Back to REO Testing](README.md)

This test plan validates that indexers can perform standard operational cycles on The Graph Network after a protocol upgrade. It is upgrade-agnostic and covers the core indexer workflows that must function correctly regardless of what changed.

Each test includes CLI commands, GraphQL verification queries against the network subgraph, and pass/fail criteria.

> All GraphQL queries run against the network subgraph. All addresses must be **lowercase**.

---

## Prerequisites

- ETH and GRT on the target network (testnet or mainnet)
- Indexer stack running (graph-node, indexer-agent, indexer-service, tap-agent)
- Minimum indexer stake met (100k GRT on testnet)
- Access to Explorer UI and network subgraph

### Recommended log verbosity for troubleshooting

```
tap-agent:        RUST_LOG=info,indexer_tap_agent=trace
indexer-service:  RUST_LOG=info,indexer_service_rs=trace
indexer-agent:    INDEXER_AGENT_LOG_LEVEL=trace
```

---

## Test Sequence Overview

The tests are organized into 7 cycles. Cycles 1-6 cover individual operations; Cycle 7 ties them together in an end-to-end workflow.

| Cycle | Area                           | Tests     |
| ----- | ------------------------------ | --------- |
| 1     | Indexer Setup and Registration | 1.1 - 1.3 |
| 2     | Stake Management               | 2.1 - 2.2 |
| 3     | Provision Management           | 3.1 - 3.4 |
| 4     | Allocation Management          | 4.1 - 4.5 |
| 5     | Query Serving and Revenue      | 5.1 - 5.4 |
| 6     | Network Health                 | 6.1 - 6.3 |
| 7     | End-to-End Workflow            | 7.1       |

---

## Cycle 1: Indexer Setup and Registration

### 1.1 Setup indexer via Explorer

**Objective**: Stake GRT and set delegation parameters through Explorer UI.

**Steps**:

1. Navigate to Explorer
2. Stake GRT to your indexer address
3. Set delegation parameters (query fee cut, indexing reward cut)
4. Wait for transaction confirmation

**Verification Query**:

```graphql
{
  indexers(where: { id: "INDEXER_ADDRESS" }) {
    id
    createdAt
    stakedTokens
    queryFeeCut
    indexingRewardCut
  }
}
```

**Pass Criteria**:

- Indexer entity exists with correct `stakedTokens`
- `queryFeeCut` and `indexingRewardCut` reflect configured values
- Transaction visible in Explorer history

---

### 1.2 Register indexer URL and GEO coordinates

**Objective**: Verify indexer metadata registration via the indexer agent.

**Steps**:

1. Configure `indexer-agent` with URL and GEO coordinates
2. Start or restart the agent
3. Confirm the agent logs show successful registration

**Verification Query**:

```graphql
{
  indexers(where: { id: "INDEXER_ADDRESS" }) {
    id
    url
    geoHash
  }
}
```

**Pass Criteria**:

- `url` matches configured value
- `geoHash` is populated
- Agent logs show `Successfully registered indexer`

---

### 1.3 Validate Subgraph Service provision and registration

**Objective**: Confirm the indexer agent automatically creates a provision and registers with SubgraphService.

**Steps**:

1. Ensure indexer has sufficient unallocated stake
2. Start indexer agent
3. Monitor logs for provision creation and registration

**Verification Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS" } }) {
    id
    indexer {
      id
      url
      geoHash
    }
    tokensProvisioned
    tokensAllocated
    tokensThawing
    thawingPeriod
    maxVerifierCut
    dataService {
      id
    }
  }
}
```

**Pass Criteria**:

- Provision exists for SubgraphService
- `url` and `geoHash` populated in indexer registration
- `tokensProvisioned` is non-zero
- Agent logs show `Successfully provisioned to the Subgraph Service` and `Successfully registered indexer`

---

## Cycle 2: Stake Management

### 2.1 Add stake via Explorer

**Objective**: Verify indexers can increase their stake.

**Steps**:

1. Navigate to Explorer
2. Add stake to your indexer
3. Wait for transaction confirmation

**Verification Query**:

```graphql
{
  indexers(where: { id: "INDEXER_ADDRESS" }) {
    id
    stakedTokens
    allocatedTokens
    availableStake
  }
}
```

**Pass Criteria**:

- `stakedTokens` increases by the added amount
- Transaction visible in Explorer history

---

### 2.2 Unstake tokens and withdraw after thawing

**Objective**: Verify the unstake and thawing period workflow.

**Steps**:

1. Unstake tokens via Explorer
2. Note the thawing period end time
3. Wait for thawing period to complete
4. Withdraw thawed tokens

**Verification Query**:

```graphql
{
  indexers(where: { id: "INDEXER_ADDRESS" }) {
    id
    stakedTokens
    availableStake
  }
  thawRequests(where: { indexer_: { id: "INDEXER_ADDRESS" } }) {
    id
    tokens
    thawingUntil
    type
  }
}
```

**Pass Criteria**:

- Thaw request appears with correct token amount
- After thawing period, tokens withdraw successfully
- `stakedTokens` decreases by withdrawn amount

---

## Cycle 3: Provision Management

### 3.1 View current provision

**Objective**: Check current Subgraph Service provision status.

**Command**:

```bash
graph indexer provisions get
```

**Verification Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS" } }) {
    id
    tokensProvisioned
    tokensThawing
    tokensAllocated
    thawingPeriod
    maxVerifierCut
  }
}
```

**Pass Criteria**:

- CLI output matches subgraph data
- `tokensProvisioned` shows provisioned stake

---

### 3.2 Add stake to provision

**Objective**: Increase provision without creating a new one.

**Command**:

```bash
graph indexer provisions add <AMOUNT>
```

**Verification Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS" } }) {
    id
    tokensProvisioned
    tokensAllocated
    indexer {
      stakedTokens
      availableStake
    }
  }
}
```

**Pass Criteria**:

- `tokensProvisioned` increases by the added amount
- `availableStake` decreases correspondingly

---

### 3.3 Thaw stake from provision

**Objective**: Initiate thawing process to remove stake from provision.

**Command**:

```bash
graph indexer provisions thaw <AMOUNT>
```

**Verification Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS" } }) {
    id
    tokensProvisioned
    tokensThawing
  }
  thawRequests(where: { indexer_: { id: "INDEXER_ADDRESS" }, type: Provision }) {
    id
    tokens
    thawingUntil
  }
}
```

**Pass Criteria**:

- `tokensThawing` increases by the thawed amount
- Thaw request created with future `thawingUntil` timestamp

---

### 3.4 Remove thawed stake from provision

**Objective**: Complete the provision reduction after thawing period.

**Command**:

```bash
graph indexer provisions remove
```

**Verification Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS" } }) {
    id
    tokensProvisioned
    tokensThawing
  }
  indexers(where: { id: "INDEXER_ADDRESS" }) {
    availableStake
  }
}
```

**Pass Criteria**:

- `tokensThawing` decreases to 0
- `tokensProvisioned` decreases by the removed amount
- `availableStake` increases correspondingly

---

## Cycle 4: Allocation Management

### 4.1 Find subgraph deployments with rewards

**Objective**: Identify eligible deployments for allocation.

**Query**:

```graphql
{
  subgraphDeployments(where: { deniedAt: 0, signalledTokens_not: 0, indexingRewardAmount_not: 0 }) {
    ipfsHash
    stakedTokens
    signalledTokens
    indexingRewardAmount
    manifest {
      network
    }
  }
}
```

**Action**: Filter results by chains your graph-node can index.

---

### 4.2 Create allocation manually

**Objective**: Open an allocation for a specific deployment.

**Command**:

```bash
graph indexer allocations create <DEPLOYMENT_IPFS_HASH> <AMOUNT>
```

**Verification Query**:

```graphql
{
  allocations(where: { indexer_: { id: "INDEXER_ADDRESS" }, status: "Active" }) {
    id
    allocatedTokens
    createdAtEpoch
    subgraphDeployment {
      ipfsHash
    }
  }
}
```

**Pass Criteria**:

- Allocation appears with status `Active`
- `allocatedTokens` matches specified amount
- `createdAtEpoch` is current epoch

---

### 4.3 Create allocation via actions queue

**Objective**: Test the actions queue workflow for allocation management.

**Commands**:

```bash
graph indexer actions queue allocate <DEPLOYMENT_IPFS_HASH> <AMOUNT>
graph indexer actions execute approve <ACTION_ID>
```

**Verification**: Same as 4.2.

**Pass Criteria**:

- Action queued successfully
- After approval, allocation appears with status `Active`

---

### 4.4 Create allocation via deployment rules

**Objective**: Test automated allocation management through rules.

**Command**:

```bash
graph indexer rules set <DEPLOYMENT_IPFS_HASH> allocationAmount <AMOUNT> allocationLifetime <EPOCHS>
```

**Verification**: Same as 4.2.

**Pass Criteria**:

- Indexer agent picks up the rule and creates the allocation automatically
- Set `allocationLifetime` to a small value for quicker testing

---

### 4.5 Reallocate a deployment

**Objective**: Close and recreate allocation in one operation.

**Command**:

```bash
graph indexer allocations reallocate <ALLOCATION_ID> <NEW_AMOUNT>
```

**Verification Query**:

```graphql
{
  allocations(
    where: { indexer_: { id: "INDEXER_ADDRESS" }, subgraphDeployment_: { ipfsHash: "DEPLOYMENT_IPFS_HASH" } }
  ) {
    id
    status
    allocatedTokens
    createdAtEpoch
    closedAtEpoch
  }
}
```

**Pass Criteria**:

- Old allocation shows status `Closed`
- New allocation created with status `Active`
- New `allocatedTokens` matches specified amount

---

## Cycle 5: Query Serving and Revenue Collection

> **Cross-reference**: Allocations opened in Cycles 4-5 may also serve as setup for [ReoTestPlan Cycle 6](./ReoTestPlan.md#cycle-6-integration-with-rewards), which tests reward denial/recovery with mature allocations. If running both plans, keep extra allocations open for the REO reward integration tests.

### 5.1 Send test queries

**Objective**: Verify the indexer serves queries through the gateway.

**Script** (save as `query_test.sh`):

```bash
#!/bin/bash
subgraph_id=${1}
count=${2:-25}
api_key=${3:-"YOUR_API_KEY"}
gateway=${4:-"https://gateway.thegraph.com"}

for ((i=0; i<count; i++))
do
    curl "${gateway}/api/subgraphs/id/${subgraph_id}" \
        -H 'content-type: application/json' \
        -H "Authorization: Bearer ${api_key}" \
        -d '{"query": "{ _meta { block { number } } }"}'
    echo
done
```

**Run**:

```bash
chmod +x query_test.sh
./query_test.sh <SUBGRAPH_ID> 50
```

**Verification**:

1. Queries return valid JSON with block data
2. Check indexer-service logs for query processing
3. Check database for TAP receipts:

```sql
SELECT COUNT(*) FROM tap_horizon_receipts
WHERE allocation_id = '<ALLOCATION_ID>';
```

**Pass Criteria**:

- Queries succeed with 200 responses
- TAP receipts generated in database

---

### 5.2 Close allocation and collect indexing rewards

**Objective**: Verify rewards collection on allocation closure.

**Prerequisites**: Allocation must be several epochs old. Check first:

```graphql
{
  graphNetworks {
    currentEpoch
  }
  allocations(where: { indexer_: { id: "INDEXER_ADDRESS" }, status: "Active" }) {
    id
    allocatedTokens
    createdAtEpoch
  }
}
```

**Command**:

```bash
graph indexer allocations close <ALLOCATION_ID>
```

**Verification Query**:

```graphql
{
  allocations(where: { id: "ALLOCATION_ID" }) {
    id
    status
    allocatedTokens
    indexingRewards
    closedAtEpoch
  }
}
```

**Pass Criteria**:

- Status changes to `Closed`
- `indexingRewards` is non-zero (for deployments with rewards)
- `closedAtEpoch` is current epoch

---

### 5.3 Verify query fee collection

**Objective**: Confirm query fees collected after allocation closure.

> Query fee collection happens asynchronously after closure and may take minutes to hours.

**Verification Query**:

```graphql
{
  allocations(where: { indexer_: { id: "INDEXER_ADDRESS" }, status: "Closed" }) {
    id
    queryFeesCollected
    closedAtEpoch
  }
}
```

**Pass Criteria**:

- `queryFeesCollected` is non-zero for allocations that served queries

---

### 5.4 Close allocation with explicit POI

**Objective**: Test POI override and reward eligibility.

**Prerequisites**: Allocation is several epochs old.

**Command**:

```bash
graph indexer allocations close <ALLOCATION_ID> --poi <NON_ZERO_POI>
```

**Verification Query**:

```graphql
{
  allocations(where: { id: "ALLOCATION_ID" }) {
    id
    status
    indexingRewards
    poi
  }
}
```

**Pass Criteria**:

- `indexingRewards` is non-zero
- `poi` matches the submitted value

---

## Cycle 6: Network Health

### 6.1 Monitor indexer health

**Objective**: Verify indexer appears healthy in the network.

**Query**:

```graphql
{
  indexers(where: { id: "INDEXER_ADDRESS" }) {
    id
    url
    geoHash
    stakedTokens
    allocatedTokens
    availableStake
    delegatedTokens
    queryFeesCollected
    rewardsEarned
    allocations(where: { status: "Active" }) {
      id
      subgraphDeployment {
        ipfsHash
      }
    }
  }
}
```

**Pass Criteria**:

- All expected fields populated
- Active allocations visible
- Accumulated rewards and fees present

---

### 6.2 Check epoch progression

**Objective**: Verify the network is progressing normally.

**Query**:

```graphql
{
  graphNetworks {
    id
    currentEpoch
    totalTokensStaked
    totalTokensAllocated
    totalQueryFees
    totalIndexingRewards
  }
}
```

**Pass Criteria**:

- `currentEpoch` increments at the expected rate
- Network totals accumulate over time

---

### 6.3 Verify no unexpected errors in logs

**Objective**: Confirm clean operation across all indexer components.

**Steps**:

1. Review indexer-agent logs for unexpected errors or reverts
2. Review indexer-service logs for query handling issues
3. Review tap-agent logs for receipt/RAV issues
4. Review graph-node logs for indexing errors

**Pass Criteria**:

- No unexpected `ERROR` level log entries
- No transaction reverts
- No stuck or looping operations

---

## Cycle 7: End-to-End Workflow

### 7.1 Full operational cycle

Run these operations in sequence to validate a complete indexer lifecycle:

| Step | Operation                          | Reference |
| ---- | ---------------------------------- | --------- |
| 1    | Check provision status             | 3.1       |
| 2    | Find a rewarded deployment         | 4.1       |
| 3    | Create allocation                  | 4.2       |
| 4    | Send test queries (50-100)         | 5.1       |
| 5    | Wait 2-3 epochs                    | -         |
| 6    | Close allocation                   | 5.2       |
| 7    | Verify indexing rewards (non-zero) | 5.2       |
| 8    | Verify query fees collected        | 5.3       |
| 9    | Repeat with a different deployment | 4.2       |

**Pass Criteria**: All individual pass criteria met across the full sequence.

---

## Post-Upgrade Validation Checklist

### Core functionality

- [ ] Indexer stack components compatible with upgraded contracts
- [ ] Existing allocations continue to function
- [ ] New allocations can be created
- [ ] Query serving works through gateway
- [ ] Indexing rewards collected correctly
- [ ] Query fees collected correctly
- [ ] Provision management operations succeed

### Network health

- [ ] Network subgraph indexes the upgrade correctly
- [ ] Epoch progression continues normally
- [ ] Explorer displays correct data
- [ ] No unexpected reverts or errors in logs

### Upgrade-specific (fill in per upgrade)

- [ ] Contract address changes updated in indexer configuration
- [ ] New protocol parameters match expected values
- [ ] Schema changes (if any) reflected correctly
- [ ] _[Add upgrade-specific items here]_

---

## Troubleshooting

**Allocation creation fails**:

- Check `availableStake` is sufficient
- Verify graph-node is syncing the target deployment
- Ensure provision has enough tokens

**Query fees not collected**:

- Wait longer (can take several hours)
- Check TAP receipts in database
- Verify queries actually hit your indexer (check service logs)

**Zero indexing rewards**:

- Confirm allocation was open for the required number of epochs
- Verify POI was submitted correctly
- Confirm deployment has rewards enabled (`indexingRewardAmount_not: 0`)

---

## Network Configuration Reference

### Arbitrum Sepolia (testnet)

| Parameter         | Value                                   |
| ----------------- | --------------------------------------- |
| Explorer          | <https://testnet.thegraph.com/explorer> |
| Gateway           | <https://gateway.testnet.thegraph.com>  |
| Epoch length      | ~554 blocks (~110 minutes)              |
| Min indexer stake | 100k GRT                                |
| Thawing period    | Shortened for faster testing            |

### Arbitrum One (mainnet)

| Parameter         | Value                           |
| ----------------- | ------------------------------- |
| Explorer          | <https://thegraph.com/explorer> |
| Gateway           | <https://gateway.thegraph.com>  |
| Epoch length      | ~6,646 blocks (~24 hours)       |
| Min indexer stake | 100k GRT                        |

---

## Related Documentation

- [← Back to REO Testing](README.md)

---

_Extracted from Horizon upgrade test plans._
