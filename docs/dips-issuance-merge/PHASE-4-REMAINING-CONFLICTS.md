# Phase 4: Remaining Conflicts

**Purpose**: Resolve interfaces, Horizon contracts, package files, and test conflicts
**Duration**: ~45-60 minutes
**Outcomes**: All remaining conflicts resolved, project compiles

---

## Progress Status

**Status**: Not Started

**Last Updated**: [Update this timestamp as you work]

### Completed Steps
- [ ] 4.1 Interfaces (ISubgraphService, IRecurringCollector, IDisputeManager)
- [ ] 4.2 Horizon contracts (DataServiceFees, GraphTallyCollector)
- [ ] 4.3 Package.json files
- [ ] 4.4 Test files
- [ ] 4.5 Full compilation check

### Current Step
- Waiting to start Phase 4

### Blocked/Issues
- None yet

---

## Prerequisites

### Required State
- [✅] Phase 3 complete
- [ ] All critical contracts resolved and compiling
- [ ] Git status shows remaining conflicts

### Verify Prerequisites

```bash
# Verify Phase 3 contracts compile
forge build --contracts packages/subgraph-service/contracts/SubgraphService.sol
forge build --contracts packages/subgraph-service/contracts/utilities/AllocationManager.sol
forge build --contracts packages/subgraph-service/contracts/utilities/Directory.sol

# Check remaining conflicts
git status | grep "Unmerged paths" -A 20

# Count remaining conflicts
echo "Remaining conflicts:"
git diff --name-only --diff-filter=U | wc -l
```

**If prerequisites fail**: Go back to Phase 3

---

## 4.1 Interfaces [ACCEPT CENTRALIZATION]

**Strategy**: Accept all interface relocations from issuance-audit. Only ADD indexing agreement functions where needed.

### 4.1.1 ISubgraphService.sol

**Conflict**: Interface location + feature additions

**Resolution**:

```bash
# Check conflict
git diff packages/interfaces/contracts/subgraph-service/ISubgraphService.sol | head -100
```

**Steps**:

1. **Accept issuance-audit's centralized location**: `packages/interfaces/contracts/subgraph-service/ISubgraphService.sol`

2. **Accept issuance-audit's base interface structure**

3. **REMOVE** `registeredAt` field from Indexer struct:
   ```solidity
   struct Indexer {
       // NO registeredAt field
       string url;
       string geoHash;
   }
   ```

4. **ADD** indexing agreement functions from dips branch:
   ```solidity
   function setIndexingFeesCut(uint256 indexingFeesCut) external;
   function acceptIndexingAgreement(address indexer, bytes calldata data) external returns (bytes16);
   function updateIndexingAgreement(address indexer, bytes16 agreementId, bytes calldata data) external;
   function cancelIndexingAgreement(bytes16 agreementId) external;
   function cancelIndexingAgreementByPayer(bytes16 agreementId) external;
   function getIndexingAgreement(bytes16 agreementId) external view returns (...);
   ```

5. **ADD** indexing agreement events:
   ```solidity
   event IndexingFeesCutSet(uint256 indexingFeesCut);
   // ... other indexing agreement events
   ```

6. **ADD** indexingFeesCut getter:
   ```solidity
   function indexingFeesCut() external view returns (uint256);
   ```

**Compilation check**:
```bash
forge build --contracts packages/interfaces/contracts/subgraph-service/ISubgraphService.sol
```

**Mark resolved**:
```bash
git add packages/interfaces/contracts/subgraph-service/ISubgraphService.sol
```

---

### 4.1.2 IRecurringCollector.sol

**Conflict**: File location

**Resolution**:

```bash
# Check if file exists in dips branch
ls -l packages/horizon/contracts/interfaces/IRecurringCollector.sol 2>/dev/null || \
ls -l packages/interfaces/contracts/horizon/IRecurringCollector.sol 2>/dev/null
```

**Steps**:

1. **Move to centralized location**: `packages/interfaces/contracts/horizon/IRecurringCollector.sol`

2. **Update pragma** if needed:
   ```solidity
   pragma solidity 0.8.27 || 0.8.33;  // Multi-version support
   ```

3. **Update any internal imports** to use @graphprotocol/interfaces paths

**Mark resolved**:
```bash
# If file was moved
git add packages/interfaces/contracts/horizon/IRecurringCollector.sol
# Remove old location if it existed
git rm packages/horizon/contracts/interfaces/IRecurringCollector.sol 2>/dev/null || true
```

---

### 4.1.3 IDisputeManager.sol

**Conflict**: File relocation

**Resolution**:

**Steps**:

1. **Accept issuance-audit's centralized version**: `packages/interfaces/contracts/subgraph-service/IDisputeManager.sol`

2. **No modifications needed** - accept as-is (dips branch doesn't add dispute features)

**Mark resolved**:
```bash
git add packages/interfaces/contracts/subgraph-service/IDisputeManager.sol
```

---

### 4.1.4 Update Import Paths

After moving interfaces, update all imports:

```bash
# Find files that import old interface locations
echo "Checking for outdated import paths..."

# Will need to update these manually during conflict resolution
# The contracts in Phase 3 should already have updated paths
```

**Compilation check after all interfaces**:
```bash
forge build --contracts packages/interfaces/
```

---

## 4.2 Horizon Contracts

**Strategy**: Accept issuance-audit implementations, keep dips library patterns where they exist for size reasons.

### 4.2.1 DataServiceFees.sol

**Conflict**: Library vs inline implementation

**Resolution**:

```bash
# Check conflict
git diff packages/horizon/contracts/data-service/extensions/DataServiceFees.sol | head -50
```

**Steps**:

1. **Accept issuance-audit's base structure and pragma**:
   ```solidity
   pragma solidity 0.8.27 || 0.8.33;
   ```

2. **KEEP StakeClaims library delegation** from dips branch (if it exists for size reasons):
   ```solidity
   import { StakeClaims } from "../libraries/StakeClaims.sol";

   function _lockStake(...) internal {
       StakeClaims.lockStake(...);
   }
   ```

3. **Accept issuance-audit's linting directives**

4. **Update imports** to centralized paths

**Compilation check**:
```bash
forge build --contracts packages/horizon/contracts/data-service/extensions/DataServiceFees.sol
```

**Mark resolved**:
```bash
git add packages/horizon/contracts/data-service/extensions/DataServiceFees.sol
# If library exists, add it too
git add packages/horizon/contracts/data-service/libraries/StakeClaims.sol 2>/dev/null || true
```

---

### 4.2.2 DataServiceFeesStorage.sol

**Conflict**: Storage types

**Resolution**:

**Steps**:

1. **Accept issuance-audit's interface types**:
   ```solidity
   pragma solidity 0.8.27 || 0.8.33;

   import { ILinkedList } from "@graphprotocol/interfaces/contracts/libraries/ILinkedList.sol";

   abstract contract DataServiceFeesV1Storage {
       mapping(address => ILinkedList.List) internal _stakeClaims;
       uint256[50] private __gap;
   }
   ```

**Mark resolved**:
```bash
git add packages/horizon/contracts/data-service/extensions/DataServiceFeesStorage.sol
```

---

### 4.2.3 GraphTallyCollector.sol

**Conflict**: Payment type restriction

**Resolution**:

```bash
# Check conflict
git diff packages/horizon/contracts/payments/collectors/GraphTallyCollector.sol | head -50
```

**Steps**:

1. **Accept issuance-audit version** (no payment type restriction)

2. **REMOVE** any payment type validation from dips branch:
   ```solidity
   // DO NOT include payment type checks like:
   // require(paymentType == IGraphPayments.PaymentTypes.QueryFee, ...);

   // Collectors are payment-type agnostic by design
   ```

3. **Accept issuance-audit's linting directives**

**Compilation check**:
```bash
forge build --contracts packages/horizon/contracts/payments/collectors/GraphTallyCollector.sol
```

**Mark resolved**:
```bash
git add packages/horizon/contracts/payments/collectors/GraphTallyCollector.sol
```

---

## 4.3 Package.json Files

**Strategy**: Manual merge - prefer newer versions, include dependencies from both sides.

### 4.3.1 packages/horizon/package.json

```bash
# View conflict
cat packages/horizon/package.json | grep -A 10 -B 10 "<<<<<<<"
```

**Steps**:

1. **Open conflict markers** and manually merge:
   - For version conflicts: prefer higher version
   - For new dependencies: include from both sides
   - For removed dependencies: keep removal (from issuance-audit)

2. **Merge scripts**: Keep all scripts from both sides

3. **Merge devDependencies**: Same strategy as dependencies

**Validate JSON**:
```bash
cat packages/horizon/package.json | jq . > /dev/null && echo "✅ Valid JSON"
```

**Mark resolved**:
```bash
git add packages/horizon/package.json
```

---

### 4.3.2 packages/subgraph-service/package.json

```bash
# View conflict
cat packages/subgraph-service/package.json | grep -A 10 -B 10 "<<<<<<<"
```

**Steps**: Same as horizon/package.json above

**Validate JSON**:
```bash
cat packages/subgraph-service/package.json | jq . > /dev/null && echo "✅ Valid JSON"
```

**Mark resolved**:
```bash
git add packages/subgraph-service/package.json
```

---

## 4.4 Test Files

**Strategy**: Accept issuance-audit tests + ADD ONLY tests for NEW dips features.

**⚠️ TIME LIMIT**: Maximum 15 minutes per test file. Don't spend excessive time on tests.

### General Test Resolution Strategy

For each conflicted test file:

1. **Accept issuance-audit's base test structure**

2. **Update imports** to centralized paths:
   ```solidity
   pragma solidity 0.8.33;
   import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
   ```

3. **Update constant references**:
   - `minimumProvisionTokens` → `MINIMUM_PROVISION_TOKENS`
   - Similar for other renamed constants

4. **Update struct field counts** if Indexer struct changed (registeredAt removed):
   ```solidity
   // If test checks field count, update:
   // 3 fields → 2 fields (if registeredAt removed)
   ```

5. **DO NOT fix failing tests** - only update for syntax/compilation

6. **ADD tests for dips features** only if they're NEW test files

### Common Test File Conflicts

```bash
# List conflicted test files
git diff --name-only --diff-filter=U | grep "test.*\.sol"
```

For each test file:

```bash
# Example: SubgraphService.t.sol
# 1. Accept issuance-audit structure
# 2. Update imports
# 3. Update constant references
# 4. Mark resolved
git add packages/subgraph-service/test/unit/subgraphService/SubgraphService.t.sol
```

### Deleted Test Files

```bash
# If a test file was deleted in dips branch but modified in issuance-audit:
# Accept the deletion
git rm packages/subgraph-service/test/path/to/test.t.sol
```

### New Dips Test Files

**Keep these** (they test dips-specific features):
- `test/unit/libraries/IndexingAgreement.t.sol`
- `test/unit/subgraphService/indexing-agreement/*.t.sol`
- `test/unit/libraries/StakeClaims.t.sol`
- `test/unit/payments/recurring-collector/*.t.sol`

These should already have `pragma solidity 0.8.33` from Phase 0.

---

## 4.5 Full Compilation Check

After resolving all conflicts:

```bash
echo "Running full compilation check..."

# Full build
pnpm build 2>&1 | tee /tmp/phase4-compile-check.log

# Check exit code
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Compilation failed"
    echo "Review errors in /tmp/phase4-compile-check.log"
    # STOP and ask user
    exit 1
fi

echo "✅ Full compilation successful"
```

**If compilation fails**:
1. **STOP** immediately
2. Review error log
3. Identify which file has issues
4. Ask user for guidance
5. **DO NOT** add arbitrary code changes to "fix" it

---

## Phase 4 Complete! ✅

### Verification Checklist

Before proceeding to Phase 5, verify:

- [✅] All interfaces resolved and centralized
- [✅] Horizon contracts resolved
- [✅] Package.json files merged and valid
- [✅] Test files resolved (or timed out after 15 min each)
- [✅] Full compilation successful
- [✅] No unresolved conflicts remain

### Check No Remaining Conflicts

```bash
git status | grep "Unmerged paths"
# Should be empty

git diff --name-only --diff-filter=U | wc -l
# Should be 0
```

### Update Progress Section

1. Change Status to: **✅ Complete**
2. Update "Last Updated" timestamp
3. Mark all steps complete with ✅

### Next Steps

**Proceed to**: `PHASE-5-VERIFICATION.md`

**What's Next**: Post-merge verification - storage layouts, contract sizes, tests
