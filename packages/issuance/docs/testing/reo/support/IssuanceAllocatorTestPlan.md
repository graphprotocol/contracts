# IssuanceAllocator Test Plan

> **Navigation**: [← Back to REO Testing](../README.md)

## Contract Addresses

| Contract                  | Arbitrum Sepolia                             | Arbitrum One                                 |
| ------------------------- | -------------------------------------------- | -------------------------------------------- |
| IssuanceAllocator (proxy) | `0x76a0d75651d4db83f74ac502b86a0ae4e19ac38b` | Not yet deployed                             |
| RewardsManager (proxy)    | `0x1f49cae7669086c8ba53cc35d1e9f80176d67e79` | `0x971b9d3d0ae3eca029cab5ea1fb0f72c85e6a525` |
| GraphToken (L2)           | `0xf8c05dcf59e8b28bfd5eed176c562bebcfc7ac04` | `0x9623063377ad1b27544c965ccd7342f7ea7e88c7` |

---

## Tests

### 1. Verify IssuanceAllocator configuration

**Objective**: Confirm the IssuanceAllocator is correctly configured with RewardsManager as a self-minting target.

**Steps**:

```bash
# Check issuance rate
cast call <ISSUANCE_ALLOCATOR> "getIssuancePerBlock()(uint256)" --rpc-url <RPC>

# Check RewardsManager target allocation
# Returns a TargetIssuancePerBlock struct:
# (allocatorIssuanceRate, allocatorIssuanceBlockAppliedTo, selfIssuanceRate, selfIssuanceBlockAppliedTo)
cast call <ISSUANCE_ALLOCATOR> "getTargetIssuancePerBlock(address)((uint256,uint256,uint256,uint256))" <REWARDS_MANAGER> --rpc-url <RPC>

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

### 2. Distribute issuance

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

### 3. Verify issuance rate matches RewardsManager

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

### 4. IssuanceAllocator not paused

**Objective**: Confirm the IssuanceAllocator is operational.

**Steps**:

```bash
cast call <ISSUANCE_ALLOCATOR> "paused()(bool)" --rpc-url <RPC>
```

**Pass Criteria**:

- Returns `false`
