# Indexer Operational Test Plan: Post-Upgrade Network Verification

# Overview

This test plan validates that indexers can perform standard operational cycles on The Graph Network after a protocol upgrade. Each test includes specific commands, verification queries, and expected results.

**Primary Environment**: Arbitrum Sepolia testnet

**Secondary Environment**: Arbitrum One mainnet (after testnet validation)

**Target**: Network indexers validating upgrade functionality

**Verification**: All tests include GraphQL queries against the network subgraph

## Testing Approach

1. **Testnet First**: All operational cycles should be validated on Arbitrum Sepolia testnet
2. **Identify Issues**: Document any unexpected behavior or failures
3. **Mainnet Validation**: After testnet confidence is established, repeat critical paths on mainnet
4. **Continuous Monitoring**: Track network health metrics throughout

---

# Operational Test Cycles

## Cycle 1: Stake Management

### 1.1 Add Stake via Explorer

**Objective**: Verify indexers can increase their stake through the Explorer UI

**Steps**:

1. Navigate to Explorer
2. Add stake to your indexer
3. Wait for transaction confirmation

**Verification Query**:

```graphql
{
  indexers(where: { id: "INDEXER_ADDRESS_LOWERCASE" }) {
    id
    stakedTokens
    allocatedTokens
    unallocatedStake
  }
}
```

**Pass Criteria**:

- `stakedTokens` increases by the added amount
- Transaction shows in Explorer history

---

### 1.2 Unstake Tokens and Withdraw

**Objective**: Verify the unstake and thawing period workflow

**Steps**:

1. Unstake tokens via Explorer
2. Note the thawing period end time
3. Wait for thawing period to complete
4. Withdraw thawed tokens

**Verification Query**:

```graphql
{
  indexers(where: { id: "INDEXER_ADDRESS_LOWERCASE" }) {
    id
    stakedTokens
    unallocatedStake
  }
  thawRequests(where: { 
    indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" }
  }) {
    id
    tokens
    thawingUntil
    type
  }
}
```

**Pass Criteria**:

- Thaw request appears with correct token amount
- After thawing period, tokens are withdrawn successfully
- `stakedTokens` decreases by withdrawn amount

---

## Cycle 2: Provision Management

### 2.1 View Current Provision

**Objective**: Check Subgraph Service provision status

**Command**:

```bash
graph indexer provisions get
```

**Verification Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" } }) {
    id
    indexer {
      id
      url
      geoHash
    }
    tokensProvisioned
    tokensThawing
    tokensAllocated
    thawingPeriod
    maxVerifierCut
  }
}
```

**Pass Criteria**:

- Provision exists for SubgraphService
- `tokensProvisioned` shows provisioned stake
- Registration data (url, geoHash) is populated

---

### 2.2 Add Stake to Provision

**Objective**: Increase provision without creating a new one

**Command**:

```bash
graph indexer provisions add <AMOUNT>
```

**Verification Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" } }) {
    id
    tokensProvisioned
    tokensAllocated
    indexer {
      stakedTokens
      unallocatedStake
    }
  }
}
```

**Pass Criteria**:

- `tokensProvisioned` increases by the added amount
- `unallocatedStake` decreases correspondingly

---

### 2.3 Thaw Stake from Provision

**Objective**: Initiate thawing process to remove stake from provision

**Command**:

```bash
graph indexer provisions thaw <AMOUNT>
```

**Verification Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" } }) {
    id
    tokensProvisioned
    tokensThawing
  }
  thawRequests(where: { 
    indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" },
    type: "ProvisionThaw"
  }) {
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

### 2.4 Remove Thawed Stake from Provision

**Objective**: Complete the provision reduction after thawing period

**Command**:

```bash
graph indexer provisions remove
```

**Verification Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" } }) {
    id
    tokensProvisioned
    tokensThawing
  }
  indexers(where: { id: "INDEXER_ADDRESS_LOWERCASE" }) {
    unallocatedStake
  }
}
```

**Pass Criteria**:

- `tokensThawing` decreases to 0
- `tokensProvisioned` decreases by the removed amount
- `unallocatedStake` increases correspondingly

---

## Cycle 3: Allocation Management

### 3.1 Query Available Subgraph Deployments

**Objective**: Find subgraph deployments with rewards for allocation

**Query to get deployments with rewards**:

```graphql
{
  subgraphDeployments(where: { 
    deniedAt: 0, 
    signalledTokens_not: 0, 
    indexingRewardAmount_not: 0 
  }) {
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

**Action**: Filter by chains your graph-node can index

---

### 3.2 Create Allocation Manually

**Objective**: Open allocation for a specific deployment

**Command**:

```bash
graph indexer allocations create <DEPLOYMENT_IPFS_HASH> <AMOUNT>
```

**Verification Query**:

```graphql
{
  allocations(where: { 
    indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" },
    status: "Active"
  }) {
    id
    allocatedTokens
    createdAtEpoch
    subgraphDeployment {
      ipfsHash
    }
    indexer {
      id
    }
  }
}
```

**Pass Criteria**:

- Allocation appears with status `Active`
- `allocatedTokens` matches the specified amount
- `createdAtEpoch` is current epoch

---

### 3.3 Create Allocation via Actions Queue

**Objective**: Test the actions queue workflow

**Command**:

```bash
graph indexer actions queue allocate <DEPLOYMENT_IPFS_HASH> <AMOUNT>
graph indexer actions execute approve <ACTION_ID>
```

**Verification**: Same as 3.2

---

### 3.4 Create Allocation via Deployment Rules

**Objective**: Test automated allocation management

**Command**:

```bash
graph indexer rules set <DEPLOYMENT_IPFS_HASH> allocationAmount <AMOUNT> allocationLifetime <EPOCHS>
```

**Verification**: Same as 3.2

**Note**: Set `allocationLifetime` to a few epochs for quicker testing

---

### 3.5 Reallocate a Deployment

**Objective**: Close and recreate allocation in one operation

**Command**:

```bash
graph indexer allocations reallocate <ALLOCATION_ID> <NEW_AMOUNT>
```

**Verification Query**:

```graphql
{
  allocations(where: { 
    indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" },
    subgraphDeployment_: { ipfsHash: "DEPLOYMENT_IPFS_HASH" }
  }) {
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

## Cycle 4: Query Serving and Revenue Collection

### 4.1 Send Test Queries to Your Indexer

**Objective**: Verify indexer can serve queries through the gateway

**Script** (save as [`query.sh`](http://query.sh)):

```bash
#!/bin/bash

subgraph_id=${1}
count=${2:-25}
api_key=${3:-"YOUR_API_KEY"}

for ((i=0; i<count; i++))
do
    curl "https://gateway.thegraph.com/api/subgraphs/id/${subgraph_id}" \
        -H 'content-type: application/json' \
        -H "Authorization: Bearer ${api_key}" \
        -d '{"query": "{ _meta { block { number } } }"}'
    echo
done
```

**Run**:

```bash
chmod +x query.sh
./query.sh <SUBGRAPH_ID> 50
```

**Verification**:

1. Queries return valid results
2. Check indexer-service logs for query processing
3. Inspect database for TAP receipts:

```sql
SELECT COUNT(*) FROM tap_horizon_receipts 
WHERE allocation_id = '<ALLOCATION_ID>';
```

**Pass Criteria**:

- Queries succeed with 200 responses
- TAP receipts generated in database
- Multiple receipts accumulated for RAV aggregation

---

### 4.2 Close Allocation and Collect Rewards

**Objective**: Verify rewards collection on allocation closure

**Prerequisites**:

- Allocation must be several epochs old
- Check current epoch and allocation age:

```graphql
{
  graphNetworks {
    currentEpoch
  }
  allocations(where: { 
    indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" },
    status: "Active"
  }) {
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
- `indexingRewards` is non-zero (if deployment has rewards)
- `closedAtEpoch` is current epoch

---

### 4.3 Verify Query Fee Collection

**Objective**: Confirm query fees collected after allocation closure

**Note**: Query fee collection happens asynchronously after closure

**Verification Query**:

```graphql
{
  allocations(where: { 
    indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" },
    status: "Closed"
  }) {
    id
    queryFeesCollected
    closedAtEpoch
  }
}
```

**Alternative Verification**:

```bash
graph indexer allocations get <ALLOCATION_ID>
```

**Pass Criteria**:

- `queryFeesCollected` is non-zero for allocations that served queries
- Collection typically completes within minutes to hours of closure

---

### 4.4 Close Allocation with Non-Zero POI

**Objective**: Test POI submission and reward eligibility

**Prerequisites**: Allocation is several epochs old

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
- `poi` matches submitted value

---

## Cycle 5: Zero-Token (Altruistic) Allocations

### 5.1 Create Zero-Token Allocation

**Objective**: Test altruistic indexing without stake

**Command**:

```bash
graph indexer allocations create <DEPLOYMENT_IPFS_HASH> 0
```

**Verification Query**:

```graphql
{
  allocations(where: { 
    indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" },
    allocatedTokens: "0"
  }) {
    id
    allocatedTokens
    status
  }
}
```

**Pass Criteria**:

- Allocation created with `allocatedTokens` = 0
- Status is `Active`

---

### 5.2 Close Zero-Token Allocation

**Objective**: Verify altruistic allocations can be closed normally

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
  }
}
```

**Pass Criteria**:

- Status changes to `Closed`
- `indexingRewards` is 0 (no rewards for zero-stake allocations)

---

## Cycle 6: Network Monitoring and Validation

### 6.1 Monitor Indexer Health

**Objective**: Verify indexer appears healthy in the network

**Query**:

```graphql
{
  indexers(where: { id: "INDEXER_ADDRESS_LOWERCASE" }) {
    id
    url
    geoHash
    stakedTokens
    allocatedTokens
    unallocatedStake
    delegatedTokens
    queryFeesCollected
    indexingRewardAmount
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
- Accumulated rewards and fees visible

---

### 6.2 Check Epoch Progression

**Objective**: Verify network is progressing normally

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

- `currentEpoch` increments regularly
- Network totals accumulate over time

---

### 6.3 Validate Subgraph Service Registration

**Objective**: Confirm indexer is properly registered

**Query**:

```graphql
{
  provisions(where: { indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" } }) {
    id
    indexer {
      id
      url
      geoHash
    }
    tokensProvisioned
    dataService {
      id
    }
  }
}
```

**Pass Criteria**:

- Provision exists for SubgraphService
- Registration metadata (url, geoHash) populated
- `tokensProvisioned` sufficient for operations

---

# Complete Operational Workflow

## End-to-End Test Sequence

Run these operations in order to validate a full operational cycle:

1. **Setup** (Cycle 2.1): Check provision status
2. **Allocate** (Cycle 3.2): Create allocation for rewarded deployment
3. **Serve** (Cycle 4.1): Send test queries (50-100 queries)
4. **Wait**: Let allocation age 2-3 epochs
5. **Close** (Cycle 4.2): Close allocation
6. **Verify Indexing Rewards** (Cycle 4.2): Check non-zero rewards
7. **Verify Query Fees** (Cycle 4.3): Check query fee collection
8. **Repeat**: Allocate to different deployment

---

# Network Configuration

## Arbitrum Sepolia Testnet (Primary Testing Environment)

**Network Subgraph**: Check latest deployment in testnet explorer

**Explorer**: [`https://testnet.thegraph.com/explorer`](https://testnet.thegraph.com/explorer)

**Gateway**: [`https://gateway.testnet.thegraph.com`](https://gateway.testnet.thegraph.com)

**Testnet Parameters**:

- Epochs: ~554 blocks (~110 minutes vs 24 hours on mainnet)
- Minimum indexer stake: 100k GRT
- Thawing period: Shorter for faster testing
- GRT available via testnet faucet

**Test Query Script** (for testnet):

```bash
subgraph_id=${1}
count=${2:-25}
api_key=${3:-"c6ee2f3c1bcf1e0364b83e6470264dce"}  # Testnet default

for ((i=0; i<count; i++))
do
    curl "{{https://gateway.testnet.thegraph.com/api/subgraphs/id/${subgraph_id}}}" \
        -H 'content-type: application/json' \
        -H "Authorization: Bearer ${api_key}" \
        -d '{"query": "{ _meta { block { number } } }"}'
    echo
done
```

## Arbitrum One Mainnet (Post-Testnet Validation)

**Network Subgraph**: Query via [`https://gateway.thegraph.com`](https://gateway.thegraph.com)

**Explorer**: [`https://thegraph.com/explorer`](https://thegraph.com/explorer)

**Gateway**: [`https://gateway.thegraph.com`](https://gateway.thegraph.com)

**Important Notes**:

- All addresses in queries must be lowercase
- Testnet epochs are much faster - adjust waiting times accordingly
- Use testnet faucet for GRT: Contact protocol team in Discord

---

# Troubleshooting

## Common Issues

**Allocation creation fails**:

- Check `unallocatedStake` is sufficient
- Verify graph-node is syncing the deployment
- Ensure provision has enough tokens

**Query fees not collected**:

- Wait longer (can take several hours)
- Check TAP receipts in database
- Verify queries actually hit your indexer

**Zero indexing rewards**:

- Check allocation was open for minimum epochs
- Verify POI was submitted correctly
- Confirm deployment has rewards enabled

---

# Post-Upgrade Validation Checklist

## Testnet Validation (Arbitrum Sepolia)

- [ ]  Indexer stack components compatible with upgraded contracts
- [ ]  Existing allocations continue to function
- [ ]  New allocations can be created
- [ ]  Query serving works through gateway
- [ ]  Rewards collection functions correctly
- [ ]  Query fee collection works
- [ ]  Provision management operations succeed
- [ ]  Network subgraph indexes upgrade correctly
- [ ]  No unexpected reverts or errors in logs

## Upgrade-Specific Validation

- [ ]  Contract addresses updated in indexer configuration
- [ ]  Network subgraph reflects upgraded contract state
- [ ]  GraphQL schema changes (if any) documented
- [ ]  Epoch progression continues normally
- [ ]  Protocol parameters match expected values
- [ ]  Explorer displays upgraded contract data correctly

## Mainnet Validation (After Testnet Success)

- [ ]  Critical path operations verified (allocate, serve, collect)
- [ ]  No regressions from testnet findings
- [ ]  Performance metrics within acceptable ranges
- [ ]  Monitoring dashboards updated for new contract events