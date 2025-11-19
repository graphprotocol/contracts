# API Correctness Reference for Issuance Integration

**Last Updated:** 2025-11-19

---

## Overview

This document provides the correct method signatures and usage patterns for integrating issuance contracts. Following these patterns prevents common implementation errors.

⚠️ **IMPORTANT:** Copy method signatures exactly. Small differences in method names or parameter order will cause integration failures.

---

## RewardsEligibilityOracle (REO)

### Configuration Methods

#### Enable/Disable Validation

**CORRECT:**
```solidity
function setEligibilityValidationEnabled(bool enabled) external onlyRole(OPERATOR_ROLE)
```

**Example:**
```typescript
// Enable validation (Phase 6)
await reo.setEligibilityValidationEnabled(true)

// Disable validation (rollback or emergency)
await reo.setEligibilityValidationEnabled(false)
```

**❌ WRONG:**
- `setCheckingActive(bool)` ← Does not exist
- `setQualityChecking(bool)` ← Wrong name
- `enableValidation(bool)` ← Wrong name

---

#### Update Eligibility Period

**CORRECT:**
```solidity
function setEligibilityPeriod(uint256 period) external onlyRole(OPERATOR_ROLE)
```

**Example:**
```typescript
// Set to 14 days
await reo.setEligibilityPeriod(1_209_600) // 14 days in seconds
```

**Parameter:**
- `period`: Duration in seconds
- Example: 1_209_600 = 14 days

---

#### Update Oracle Timeout

**CORRECT:**
```solidity
function setOracleUpdateTimeout(uint256 timeout) external onlyRole(OPERATOR_ROLE)
```

**Example:**
```typescript
// Set to 7 days
await reo.setOracleUpdateTimeout(604_800) // 7 days in seconds
```

**Parameter:**
- `timeout`: Maximum time between oracle updates, in seconds
- Example: 604_800 = 7 days

---

### Oracle Data Submission

#### Update Oracle Data

**CORRECT:**
```solidity
function updateOracleData(
    address[] calldata indexers,
    bool[] calldata eligible,
    uint256 eligibilityPeriodEnd
) external onlyRole(ORACLE_ROLE)
```

**Example:**
```typescript
// Prepare data
const indexers = [
  '0x1111111111111111111111111111111111111111',
  '0x2222222222222222222222222222222222222222',
  '0x3333333333333333333333333333333333333333'
]

const eligible = [
  true,   // Indexer 1 is eligible
  false,  // Indexer 2 is not eligible
  true    // Indexer 3 is eligible
]

const eligibilityPeriodEnd = Math.floor(Date.now() / 1000) + 1_209_600 // 14 days from now

// Submit to REO
await reo.updateOracleData(indexers, eligible, eligibilityPeriodEnd)
```

**Parameters:**
- `indexers`: Array of indexer addresses
- `eligible`: Array of boolean eligibility status (same length as indexers)
- `eligibilityPeriodEnd`: Unix timestamp when this eligibility period ends

**Requirements:**
- Arrays must be same length
- Must have ORACLE_ROLE
- `eligibilityPeriodEnd` must be in the future

**❌ WRONG:**
- Mismatched array lengths ← Will revert
- Past `eligibilityPeriodEnd` ← May revert or be ignored
- Not having ORACLE_ROLE ← Will revert

---

### Query Methods

#### Check Indexer Eligibility

**CORRECT:**
```solidity
function isIndexerEligible(address indexer) external view returns (bool)
```

**Example:**
```typescript
// Check if indexer is eligible
const eligible = await reo.isIndexerEligible('0x1111111111111111111111111111111111111111')
console.log('Eligible:', eligible)
```

**Returns:**
- `true` if indexer is eligible
- `false` if indexer is not eligible
- `true` if validation disabled (all indexers eligible)
- May revert if oracle timeout exceeded and validation enabled

**Logic:**
1. If `eligibilityValidationEnabled == false`: Return `true` (all eligible)
2. If no oracle data: Return `true` (grace period)
3. If oracle timeout exceeded: Revert (safety mechanism)
4. Otherwise: Return stored eligibility from latest oracle data

---

### View Functions

#### Get Configuration

**CORRECT:**
```typescript
// Get eligibility period
const period = await reo.eligibilityPeriod()
console.log('Eligibility Period:', period.toString(), 'seconds')

// Get oracle timeout
const timeout = await reo.oracleUpdateTimeout()
console.log('Oracle Timeout:', timeout.toString(), 'seconds')

// Check if validation enabled
const enabled = await reo.eligibilityValidationEnabled()
console.log('Validation Enabled:', enabled)

// Get RewardsManager address
const rm = await reo.rewardsManager()
console.log('RewardsManager:', rm)

// Get latest oracle update timestamp
const lastUpdate = await reo.lastOracleUpdate()
console.log('Last Update:', new Date(lastUpdate.toNumber() * 1000))

// Get latest eligibility period end
const periodEnd = await reo.latestEligibilityPeriodEnd()
console.log('Period Ends:', new Date(periodEnd.toNumber() * 1000))
```

---

### Role Management

#### Grant Roles

**CORRECT:**
```typescript
import { keccak256, toUtf8Bytes } from 'ethers'

// Calculate role identifiers
const OPERATOR_ROLE = keccak256(toUtf8Bytes('OPERATOR_ROLE'))
const ORACLE_ROLE = keccak256(toUtf8Bytes('ORACLE_ROLE'))

// Grant OPERATOR_ROLE
await reo.grantRole(OPERATOR_ROLE, operatorAddress)

// Grant ORACLE_ROLE
await reo.grantRole(ORACLE_ROLE, oracleAddress)
```

**Check Roles:**
```typescript
// Check if address has role
const hasOperatorRole = await reo.hasRole(OPERATOR_ROLE, operatorAddress)
const hasOracleRole = await reo.hasRole(ORACLE_ROLE, oracleAddress)

console.log('Has Operator Role:', hasOperatorRole)
console.log('Has Oracle Role:', hasOracleRole)
```

**Revoke Roles:**
```typescript
// Revoke role
await reo.revokeRole(OPERATOR_ROLE, operatorAddress)
```

---

## RewardsManager Integration

### Set REO on RewardsManager

**CORRECT:**
```solidity
function setRewardsEligibilityOracle(address oracle) external onlyGovernor
```

**Example:**
```typescript
// Set REO on RewardsManager (governance only)
await rewardsManager.setRewardsEligibilityOracle(reoAddress)

// Verify
const reo = await rewardsManager.rewardsEligibilityOracle()
console.log('REO Address:', reo)
```

**Parameter:**
- `oracle`: Address of REO proxy
- Use `address(0)` to disable REO integration

**Usage:**
- Initial integration (Phase 4)
- Rollback: `setRewardsEligibilityOracle(ethers.ZeroAddress)`

---

### Query REO from RM

**CORRECT:**
```typescript
// RewardsManager internally calls REO
// When distributing rewards, RM will call:
const eligible = await reo.isIndexerEligible(indexerAddress)

// If eligible: Distribute rewards
// If not eligible: Skip rewards
```

**This is internal to RewardsManager** - you don't need to call this manually unless testing.

---

## IssuanceAllocator (IA) - Future Use

### Configuration Methods

#### Set Target Allocation

**CORRECT:**
```solidity
function setTargetAllocation(
    address target,
    uint256 allocatorMintingPPM,
    uint256 selfMintingPPM,
    bool evenIfDistributionPending
) external onlyOwner
```

**Example - Stage 2: 100% to RewardsManager (Replication)**
```typescript
// Set 100% allocation to RewardsManager
await ia.setTargetAllocation(
  rewardsManagerAddress,
  1_000_000,  // 100% in PPM (parts per million)
  0,          // 0% self-minting
  false       // Don't set if distribution pending
)
```

**Example - Stage 3: 95% RM / 5% DirectAllocation**
```typescript
// Set 95% to RewardsManager
await ia.setTargetAllocation(
  rewardsManagerAddress,
  950_000,    // 95% in PPM
  0,
  false
)

// Set 5% to DirectAllocation
await ia.setTargetAllocation(
  directAllocationAddress,
  50_000,     // 5% in PPM
  0,
  false
)
```

**Parameters:**
- `target`: Address of target contract
- `allocatorMintingPPM`: Percentage in PPM (1,000,000 = 100%)
- `selfMintingPPM`: Percentage for self-minting (usually 0)
- `evenIfDistributionPending`: Override pending distribution check

**PPM (Parts Per Million):**
- 1,000,000 = 100%
- 500,000 = 50%
- 100,000 = 10%
- 10,000 = 1%
- 1,000 = 0.1%

**❌ WRONG:**
- Using 100 for 100% ← Should be 1,000,000
- Using decimals ← Should be integers only
- Total allocations > 100% ← Will revert

---

#### Set Issuance Per Block

**CORRECT:**
```solidity
function setIssuancePerBlock(uint256 issuancePerBlock) external onlyOwner
```

**Example:**
```typescript
// Set issuance rate (tokens per block)
await ia.setIssuancePerBlock(ethers.parseEther('10')) // 10 tokens per block
```

**Parameter:**
- `issuancePerBlock`: Amount of tokens to mint per block (in wei)
- Example: `parseEther('10')` = 10 tokens per block

---

### Query Methods

#### Get Target Allocation

**CORRECT:**
```solidity
function getTargetAllocation(address target) external view returns (uint256 allocatorPPM, uint256 selfPPM)
```

**Example:**
```typescript
// Get allocation for RewardsManager
const [allocatorPPM, selfPPM] = await ia.getTargetAllocation(rewardsManagerAddress)

console.log('Allocator PPM:', allocatorPPM.toString()) // e.g., 1000000 (100%)
console.log('Self PPM:', selfPPM.toString())           // e.g., 0 (0%)

// Calculate percentage
const percentage = (allocatorPPM.toNumber() / 10000).toFixed(2)
console.log('Percentage:', percentage + '%')           // e.g., "100.00%"
```

**Returns:**
- `allocatorPPM`: Percentage allocated by allocator (in PPM)
- `selfPPM`: Percentage for self-minting (in PPM)

**❌ WRONG:**
- Using `getTargetIssuancePerBlock().issuancePerBlock` ← Wrong field name
- Expecting single return value ← Returns tuple

---

#### Get Target Issuance Per Block

**CORRECT:**
```solidity
struct TargetIssuance {
    uint256 selfIssuancePerBlock;
    uint256 allocatorIssuancePerBlock;
}

function getTargetIssuancePerBlock(address target) external view returns (TargetIssuance memory)
```

**Example:**
```typescript
// Get issuance for RewardsManager
const ti = await ia.getTargetIssuancePerBlock(rewardsManagerAddress)

// ⚠️ IMPORTANT: Use correct field name!
const rmIssuance = ti.selfIssuancePerBlock  // ← CORRECT
// NOT: ti.issuancePerBlock ← WRONG

console.log('RM Issuance Per Block:', ethers.formatEther(rmIssuance))
```

**Returns:**
- `TargetIssuance` struct with two fields:
  - `selfIssuancePerBlock`: Amount target receives per block
  - `allocatorIssuancePerBlock`: Amount allocated by allocator

**For RewardsManager integration, use `selfIssuancePerBlock`**

**❌ WRONG:**
- Using `ti.issuancePerBlock` ← Field does not exist
- Using wrong field name ← Will cause errors

---

### RewardsManager Integration

#### Set IA on RewardsManager

**CORRECT:**
```solidity
function setIssuanceAllocator(address allocator) external onlyGovernor
```

**Example:**
```typescript
// Set IA on RewardsManager (governance only)
await rewardsManager.setIssuanceAllocator(iaAddress)

// Verify
const ia = await rewardsManager.issuanceAllocator()
console.log('IA Address:', ia)
```

**Parameter:**
- `allocator`: Address of IssuanceAllocator proxy
- Use `address(0)` to disable IA integration (rollback)

---

#### RM Queries IA for Issuance

**CORRECT:**
```typescript
// RewardsManager internally calls:
const ti = await ia.getTargetIssuancePerBlock(rewardsManagerAddress)
const issuance = ti.selfIssuancePerBlock  // ⚠️ Use correct field!

// Then RM uses this issuance amount for rewards distribution
```

**This is internal to RewardsManager** - shown for reference only.

---

## GraphToken

### Grant Minting Authority

**CORRECT:**
```solidity
function addMinter(address minter) external onlyGovernor
```

**Example:**
```typescript
// Grant IA minting authority (governance only)
await graphToken.addMinter(iaAddress)

// Verify
const isMinter = await graphToken.isMinter(iaAddress)
console.log('Is Minter:', isMinter) // true
```

**Parameter:**
- `minter`: Address to grant minting authority

---

### Revoke Minting Authority

**CORRECT:**
```solidity
function removeMinter(address minter) external onlyGovernor
```

**Example:**
```typescript
// Revoke minting authority (governance only, for rollback)
await graphToken.removeMinter(iaAddress)

// Verify
const isMinter = await graphToken.isMinter(iaAddress)
console.log('Is Minter:', isMinter) // false
```

---

## Proxy Administration

### Upgrade Proxy

**CORRECT:**
```solidity
// GraphProxyAdmin (from Horizon)
function upgrade(address proxy, address implementation) external onlyOwner
```

**Example:**
```typescript
// Upgrade RewardsManager proxy (governance via ProxyAdmin)
await graphProxyAdmin.upgrade(
  rewardsManagerProxyAddress,
  newRewardsManagerImplementation
)

// Accept proxy
await graphProxyAdmin.acceptProxy(
  newRewardsManagerImplementation,
  rewardsManagerProxyAddress
)
```

**Parameters:**
- `proxy`: Address of proxy contract
- `implementation`: Address of new implementation

---

## Common Mistakes & How to Avoid

### 1. Wrong Method Name

**❌ WRONG:**
```typescript
await reo.setCheckingActive(true)  // Method does not exist
```

**✅ CORRECT:**
```typescript
await reo.setEligibilityValidationEnabled(true)
```

---

### 2. Wrong Percentage Units

**❌ WRONG:**
```typescript
await ia.setTargetAllocation(target, 100, 0, false)  // 100 = 0.01%, not 100%!
```

**✅ CORRECT:**
```typescript
await ia.setTargetAllocation(target, 1_000_000, 0, false)  // 1,000,000 = 100%
```

---

### 3. Wrong Struct Field Name

**❌ WRONG:**
```typescript
const ti = await ia.getTargetIssuancePerBlock(target)
const issuance = ti.issuancePerBlock  // Field does not exist!
```

**✅ CORRECT:**
```typescript
const ti = await ia.getTargetIssuancePerBlock(target)
const issuance = ti.selfIssuancePerBlock  // Correct field name
```

---

### 4. Forgetting Role Requirements

**❌ WRONG:**
```typescript
// Called by address without ORACLE_ROLE
await reo.updateOracleData(indexers, eligible, periodEnd)  // Will revert!
```

**✅ CORRECT:**
```typescript
// 1. Grant role first (governance)
await reo.grantRole(ORACLE_ROLE, oracleAddress)

// 2. Then call from oracle address
await reo.connect(oracleSigner).updateOracleData(indexers, eligible, periodEnd)
```

---

### 5. Array Length Mismatch

**❌ WRONG:**
```typescript
const indexers = ['0x1111...', '0x2222...']
const eligible = [true]  // Wrong length!
await reo.updateOracleData(indexers, eligible, periodEnd)  // Will revert
```

**✅ CORRECT:**
```typescript
const indexers = ['0x1111...', '0x2222...']
const eligible = [true, false]  // Same length as indexers
await reo.updateOracleData(indexers, eligible, periodEnd)
```

---

### 6. Using Zero Address Incorrectly

**❌ WRONG:**
```typescript
await ia.setTargetAllocation('0x0000000000000000000000000000000000000000', 1_000_000, 0, false)
// Zero address as target is invalid
```

**✅ CORRECT:**
```typescript
// Use zero address only to disable integration
await rewardsManager.setRewardsEligibilityOracle(ethers.ZeroAddress)  // Disable REO
```

---

## Quick Reference Table

### REO Methods

| Method | Who Can Call | Parameters | Returns |
|--------|--------------|------------|---------|
| `setEligibilityValidationEnabled` | OPERATOR | `bool` | - |
| `setEligibilityPeriod` | OPERATOR | `uint256 (seconds)` | - |
| `setOracleUpdateTimeout` | OPERATOR | `uint256 (seconds)` | - |
| `updateOracleData` | ORACLE | `address[], bool[], uint256` | - |
| `isIndexerEligible` | Anyone | `address` | `bool` |
| `eligibilityPeriod` | Anyone | - | `uint256` |
| `oracleUpdateTimeout` | Anyone | - | `uint256` |
| `eligibilityValidationEnabled` | Anyone | - | `bool` |
| `grantRole` | ADMIN (Governance) | `bytes32, address` | - |

### IA Methods (Future)

| Method | Who Can Call | Parameters | Returns |
|--------|--------------|------------|---------|
| `setTargetAllocation` | Owner (Governance) | `address, uint256, uint256, bool` | - |
| `setIssuancePerBlock` | Owner (Governance) | `uint256` | - |
| `getTargetAllocation` | Anyone | `address` | `(uint256, uint256)` |
| `getTargetIssuancePerBlock` | Anyone | `address` | `TargetIssuance` |

### RM Integration Methods

| Method | Who Can Call | Parameters | Returns |
|--------|--------------|------------|---------|
| `setRewardsEligibilityOracle` | Governor | `address` | - |
| `setIssuanceAllocator` | Governor | `address` | - |
| `rewardsEligibilityOracle` | Anyone | - | `address` |
| `issuanceAllocator` | Anyone | - | `address` |

---

## Testing API Calls

### Using Hardhat Console

```typescript
// Start Hardhat console
npx hardhat console --network arbitrumSepolia

// Get contracts
const reo = await ethers.getContractAt('RewardsEligibilityOracle', REO_ADDRESS)

// Test view functions (safe, doesn't modify state)
await reo.eligibilityPeriod()
await reo.oracleUpdateTimeout()
await reo.eligibilityValidationEnabled()

// Test with static call (simulates but doesn't execute)
await reo.isIndexerEligible.staticCall('0x1111...')
```

### Using Hardhat Script

```typescript
// scripts/test-reo.ts
import { ethers } from 'hardhat'

async function main() {
  const reo = await ethers.getContractAt('RewardsEligibilityOracle', REO_ADDRESS)

  console.log('Eligibility Period:', await reo.eligibilityPeriod())
  console.log('Oracle Timeout:', await reo.oracleUpdateTimeout())
  console.log('Validation Enabled:', await reo.eligibilityValidationEnabled())
}

main().catch(console.error)
```

---

## References

- REO Contract: `packages/issuance/contracts/RewardsEligibilityOracle.sol`
- IA Contract: `packages/issuance/contracts/IssuanceAllocator.sol`
- Interface Definitions: `@graphprotocol/interfaces`
- Integration Tests: `packages/issuance/test/`
- Deployment Sequence: `REODeploymentSequence.md`
- Governance Workflow: `GovernanceWorkflow.md`

---

**Remember:** When in doubt, check the actual contract code or interface definitions. These are the source of truth for method signatures and behavior.
