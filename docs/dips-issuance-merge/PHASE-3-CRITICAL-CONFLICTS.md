# Phase 3: Critical Conflicts Resolution

**Purpose**: Resolve the 4 most critical contract conflicts in priority order
**Duration**: 60-90 minutes
**Outcomes**: Core contracts resolved, compiled, and verified

---

## Progress Status

**Status**: Not Started

**Last Updated**: [Update this timestamp as you work]

### Completed Steps
- [ ] 3.1 SubgraphService.sol resolved
- [ ] 3.2 AllocationManager.sol + AllocationHandler.sol resolved
- [ ] 3.3 Directory.sol resolved
- [ ] 3.4 SubgraphServiceStorage.sol resolved

### Current Step
- Waiting to start Phase 3

### Blocked/Issues
- None yet

---

## Prerequisites

### Required State
- [✅] Phase 2 complete
- [ ] Merge initiated (git status shows "in the middle of a merge")
- [ ] Conflicts documented in docs/merge-conflicts-categorized.md
- [ ] Working directory in MERGING state

### Verify Prerequisites

```bash
# Check merge state
git status
# Should show: "You are in the middle of a merge"

# Check conflict documentation exists
ls -l docs/merge-conflicts-categorized.md docs/merge-conflicts-list.txt

# Verify critical conflicts present
git diff --name-only --diff-filter=U | grep -E "(SubgraphService|AllocationManager|Directory|Storage)"
```

**If prerequisites fail**: Go back to Phase 2

---

## ⚠️ CRITICAL RULES FOR THIS PHASE

### Absolute Requirements
1. **NO CODE CHANGES** except minimum conflict resolution
2. **COMPILE AFTER EACH FILE** - verify before proceeding to next
3. **STOP IF COMPILATION FAILS** - ask questions, don't guess
4. **NO COMMENTS** - don't add explanatory comments
5. **PRESERVE LOGIC** - port issuance-audit logic exactly as-is

### Porting vs. Refactoring
- **AllocationHandler**: This is PORTING (moving audited logic to library) - ALLOWED
- **Everything else**: NO refactoring, NO optimization, NO style changes

### Compilation Checkpoints
After resolving EACH section (3.1, 3.2, 3.3, 3.4), you MUST:
```bash
# Compile the specific file(s)
forge build --contracts <file-path> 2>&1 | tee /tmp/phase3-compile-<section>.log

# Check exit code
if [ $? -ne 0 ]; then
    echo "❌ COMPILATION FAILED - STOP HERE"
    exit 1
fi
```

**If any compilation fails**: STOP, document issue, ask user

---

## 3.1 SubgraphService.sol [CRITICAL]

**Conflict File**: `packages/subgraph-service/contracts/SubgraphService.sol`

### Resolution Strategy
- Accept issuance-audit's base structure
- REMOVE `registeredAt` field (use URL check instead)
- ADD `recurringCollector` parameter to constructor
- ADD IndexingFee payment type handling
- ADD indexing agreement functions

### Step 1: Understand the Conflict

```bash
# View the conflict
git diff packages/subgraph-service/contracts/SubgraphService.sol | head -100
```

### Step 2: Accept issuance-audit Base + Add Dips Features

**Decision Matrix**:
| Feature | Source | Action |
|---------|--------|--------|
| Contract structure | issuance-audit | ✅ Accept |
| Storage variables | issuance-audit | ✅ Accept |
| Indexer.registeredAt field | dips branch | ❌ REMOVE |
| URL check for registration | issuance-audit | ✅ Keep |
| recurringCollector parameter | dips branch | ✅ ADD |
| RECURRING_COLLECTOR immutable | dips branch | ✅ ADD |
| IndexingFee handling in collect() | dips branch | ✅ ADD |
| Indexing agreement functions | dips branch | ✅ ADD |

### Step 3: Resolve Conflict Manually

Open `packages/subgraph-service/contracts/SubgraphService.sol` and:

**A. Accept issuance-audit's pragma and imports**
```solidity
pragma solidity 0.8.33;
// Use issuance-audit's import structure
```

**B. ADD RecurringCollector import**
```solidity
// Add after other imports:
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
```

**C. ADD RecurringCollector immutable**
```solidity
// Add with other immutables:
IRecurringCollector private immutable RECURRING_COLLECTOR;
```

**D. Update constructor to accept recurringCollector**
```solidity
constructor(
    address controller,
    address disputeManager,
    address recurringCollector  // ADD THIS
) DataServiceExtension(controller, disputeManager) {
    RECURRING_COLLECTOR = IRecurringCollector(recurringCollector);  // ADD THIS
}
```

**E. REMOVE registeredAt field from Indexer struct (if present)**
```solidity
// Use issuance-audit's Indexer struct WITHOUT registeredAt
struct Indexer {
    bytes url;
    bytes32 geohash;
}
// Do NOT include: uint256 registeredAt;
```

**F. Use URL check for registration (issuance-audit pattern)**
```solidity
// In register() function, use:
if (bytes(indexers[indexer].url).length > 0) {
    revert SubgraphServiceIndexerAlreadyRegistered();
}
// Do NOT use: if (indexers[indexer].registeredAt > 0)
```

**G. ADD IndexingFee handling in collect() function**

Find the `collect()` function and add IndexingFee case:

```solidity
function collect(CollectParams calldata params) external {
    // ... existing code ...

    // Add this case to the payment type handling:
    if (params.paymentType == PaymentType.IndexingFee) {
        _collectIndexingFees(params);
        return;
    }

    // ... rest of function ...
}
```

**H. ADD _collectIndexingFees() private function**
```solidity
// Add from dips branch - handles indexing fee payment via RecurringCollector
function _collectIndexingFees(CollectParams calldata params) private {
    // Full implementation from dips branch
    // This calls RECURRING_COLLECTOR.collect()
}
```

**I. ADD indexing agreement functions**
```solidity
// Add these functions from dips branch:

function acceptIndexingAgreement(
    bytes calldata indexingAgreement,
    IndexingAgreementDecoder.SignedIndexingAgreement calldata signedIndexingAgreement
) external { /* implementation from dips branch */ }

function updateIndexingAgreement(
    bytes calldata oldIndexingAgreement,
    bytes calldata newIndexingAgreement,
    IndexingAgreementDecoder.SignedIndexingAgreement calldata signedIndexingAgreement
) external { /* implementation from dips branch */ }

function cancelIndexingAgreement(
    bytes calldata indexingAgreement,
    IndexingAgreementDecoder.SignedIndexingAgreement calldata signedIndexingAgreement
) external { /* implementation from dips branch */ }

function getIndexingAgreement(
    address indexer,
    bytes32 subgraphDeploymentId
) external view returns (bytes memory) { /* implementation from dips branch */ }
```

### Step 4: Mark Conflict Resolved

```bash
# Stage the resolved file
git add packages/subgraph-service/contracts/SubgraphService.sol
```

### Step 5: Verify Compilation

```bash
echo "Compiling SubgraphService.sol..."
forge build --contracts packages/subgraph-service/contracts/SubgraphService.sol 2>&1 | tee /tmp/phase3-compile-subgraph-service.log

if [ $? -ne 0 ]; then
    echo "❌ ERROR: SubgraphService compilation failed"
    echo "Review errors in /tmp/phase3-compile-subgraph-service.log"
    echo "STOP - Do not proceed to next section"
    exit 1
fi

echo "✅ SubgraphService.sol compiles successfully"
```

**If compilation fails**: STOP, review error log, ask user

**Mark complete**: ✅ Update "Completed Steps" above

---

## 3.2 AllocationManager.sol + AllocationHandler.sol [CRITICAL - HIGHEST RISK]

**Conflict Files**:
- `packages/subgraph-service/contracts/utilities/AllocationManager.sol`
- `packages/subgraph-service/contracts/libraries/AllocationHandler.sol`

⚠️ **HIGHEST RISK INTEGRATION** - This requires porting issuance-audit's allocation logic INTO the AllocationHandler library pattern.

### Why This Is Complex

**Context**:
- **SubgraphService contract is at 24KB limit** - Cannot add more inline code
- **issuance-audit**: Uses inline implementation in AllocationManager (clean, audited)
- **dips branch**: Uses AllocationHandler library to reduce SubgraphService size
- **Resolution**: Port issuance-audit's logic INTO the library (maintain size optimization)

**What Needs to Be Ported**:
1. `presentPOI()` - Three-path rewards logic (CLAIMED/RECLAIMED/DEFERRED)
2. `_distributeIndexingRewards()` - Reward distribution logic
3. `_verifyAllocationProof()` - ECDSA signature verification
4. `closeAllocation()` - Reward reclaim on close
5. `resizeAllocation()` - Snapshot logic

### Step 1: Examine issuance-audit's Implementation

```bash
# Extract issuance-audit's AllocationManager for reference
git show origin/issuance-audit:packages/subgraph-service/contracts/utilities/AllocationManager.sol > /tmp/issuance-alloc-manager.sol

# Review the functions we need to port:
echo "Review these functions in /tmp/issuance-alloc-manager.sol:"
echo "  - _presentPOI() - around line 100-200"
echo "  - _distributeIndexingRewards() - around line 200-250"
echo "  - _verifyAllocationProof() - around line 250-280"
echo "  - closeAllocation() - around line 300-350"
echo "  - resizeAllocation() - around line 350-400"
```

### Step 2: Update AllocationHandler Library First

**File**: `packages/subgraph-service/contracts/libraries/AllocationHandler.sol`

**A. Update pragma to 0.8.33**
```solidity
pragma solidity 0.8.33;
```

**B. ADD new imports from issuance-audit**
```solidity
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { RewardsCondition } from "@graphprotocol/interfaces/contracts/rewards/RewardsCondition.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/staking/IHorizonStakingTypes.sol";
```

**C. Update ALL imports to use @graphprotocol/interfaces paths**
```solidity
// Change:
import { ISubgraphService } from "../interfaces/ISubgraphService.sol";
// To:
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

// Apply same pattern to all imports
```

**D. Port presentPOI() with three-path rewards logic**

Find the existing `presentPOI()` function in AllocationHandler and replace with logic from issuance-audit's `_presentPOI()`:

```solidity
function presentPOI(PresentParams memory params)
    internal
    returns (uint256 tokensRewards, bool allocationForceClosed)
{
    // PORT COMPLETE LOGIC from issuance-audit's _presentPoi()

    // Key steps to port:
    // 1. Record POI presentation timestamp
    // 2. Determine RewardsCondition via rewardsManager.determineRewardsCondition()
    // 3. Three-path reward distribution:
    //    a. DEFERRED (TOO_YOUNG or DENIED):
    //       - Return 0 without snapshot
    //       - Do NOT clear pending rewards
    //    b. RECLAIMED (invalid POI):
    //       - Call rewardsManager.reclaimRewards()
    //       - Take snapshot and clear pending
    //    c. CLAIMED (valid):
    //       - Call rewardsManager.takeRewards()
    //       - Take snapshot and clear pending
    // 4. Emit POIPresented event with condition
    // 5. If rewards > 0, distribute via _distributeIndexingRewards()
    // 6. Check for over-allocation, force close if needed
    // 7. Return (rewards, forceClosed) tuple

    // IMPORTANT: Preserve EXACT logic from issuance-audit
    // NO optimizations, NO style changes
}
```

**E. ADD _distributeIndexingRewards() internal function**

```solidity
function _distributeIndexingRewards(
    address allocationId,
    uint256 tokens,
    address indexer,
    address delegationPool,
    uint256 indexingRewardCut
) internal returns (uint256) {
    // PORT COMPLETE LOGIC from issuance-audit

    // Key steps:
    // 1. Calculate indexer rewards: (tokens * indexingRewardCut) / MAX_PPM
    // 2. Calculate delegator rewards: tokens - indexerRewards
    // 3. Transfer indexer rewards to indexer
    // 4. Transfer delegator rewards to delegation pool
    // 5. Emit IndexingRewardDistributed event
    // 6. Return total distributed
}
```

**F. ADD _verifyAllocationProof() internal pure function**

```solidity
function _verifyAllocationProof(
    address indexer,
    bytes32 allocationId,
    bytes32 metadata,
    bytes memory signature
) internal pure {
    // PORT COMPLETE LOGIC from issuance-audit

    // Key steps:
    // 1. Construct message hash: keccak256(abi.encodePacked(allocationId, metadata))
    // 2. Get EIP-191 signed message hash
    // 3. Recover signer from signature
    // 4. Verify signer == indexer, revert if not
}
```

**G. Update closeAllocation() with reward reclaim logic**

Find existing `closeAllocation()` and update with issuance-audit's logic:

```solidity
function closeAllocation(/* existing params */) internal {
    // PORT COMPLETE LOGIC from issuance-audit

    // Key steps:
    // 1. If uncollected rewards exist:
    //    - Call rewardsManager.reclaimRewards() with CLOSE_ALLOCATION condition
    //    - Take snapshot and clear pending if rewards reclaimed
    // 2. Unlock tokens via stakingManager
    // 3. Delete allocation
    // 4. Emit AllocationClosed event
}
```

**H. Update resizeAllocation() with snapshot logic**

Find existing `resizeAllocation()` and update with issuance-audit's logic:

```solidity
function resizeAllocation(/* existing params */) internal {
    // PORT COMPLETE LOGIC from issuance-audit

    // Key steps:
    // 1. Validate new tokens amount
    // 2. Take rewards snapshot before resize
    // 3. Update allocation tokens
    // 4. Adjust stake via stakingManager (increase or decrease)
    // 5. Emit AllocationResized event
}
```

### Step 3: Incremental Compilation Checks

⚠️ **Do NOT port everything at once** - Use incremental approach:

```bash
echo "=== INCREMENTAL COMPILATION ==="

# Step 1: Update pragma and imports only
echo "Step 1: Checking base structure (pragma + imports)..."
forge build --contracts packages/subgraph-service/contracts/libraries/AllocationHandler.sol 2>&1 | tee /tmp/alloc-handler-step1.log
if [ $? -ne 0 ]; then
    echo "❌ Base structure failed - fix imports before proceeding"
    exit 1
fi
echo "✅ Step 1 passed"

# Step 2: Port presentPOI logic
echo "Step 2: Checking presentPOI()..."
forge build --contracts packages/subgraph-service/contracts/libraries/AllocationHandler.sol 2>&1 | tee /tmp/alloc-handler-step2.log
if [ $? -ne 0 ]; then
    echo "❌ presentPOI failed - review logic before proceeding"
    exit 1
fi
echo "✅ Step 2 passed"

# Step 3: Add _distributeIndexingRewards
echo "Step 3: Checking _distributeIndexingRewards()..."
forge build --contracts packages/subgraph-service/contracts/libraries/AllocationHandler.sol 2>&1 | tee /tmp/alloc-handler-step3.log
if [ $? -ne 0 ]; then
    echo "❌ _distributeIndexingRewards failed"
    exit 1
fi
echo "✅ Step 3 passed"

# Step 4: Add _verifyAllocationProof
echo "Step 4: Checking _verifyAllocationProof()..."
forge build --contracts packages/subgraph-service/contracts/libraries/AllocationHandler.sol 2>&1 | tee /tmp/alloc-handler-step4.log
if [ $? -ne 0 ]; then
    echo "❌ _verifyAllocationProof failed"
    exit 1
fi
echo "✅ Step 4 passed"

# Step 5: Update closeAllocation
echo "Step 5: Checking closeAllocation()..."
forge build --contracts packages/subgraph-service/contracts/libraries/AllocationHandler.sol 2>&1 | tee /tmp/alloc-handler-step5.log
if [ $? -ne 0 ]; then
    echo "❌ closeAllocation failed"
    exit 1
fi
echo "✅ Step 5 passed"

# Step 6: Update resizeAllocation
echo "Step 6: Checking resizeAllocation()..."
forge build --contracts packages/subgraph-service/contracts/libraries/AllocationHandler.sol 2>&1 | tee /tmp/alloc-handler-step6.log
if [ $? -ne 0 ]; then
    echo "❌ resizeAllocation failed"
    exit 1
fi
echo "✅ Step 6 passed"

echo "✅ All incremental steps passed for AllocationHandler"
```

**If any step fails**: STOP, review the specific error log, fix before proceeding

### Step 4: Resolve AllocationManager.sol Conflict

**File**: `packages/subgraph-service/contracts/utilities/AllocationManager.sol`

**Strategy**: Accept issuance-audit's base structure, maintain library delegation

**A. Accept issuance-audit's pragma and imports**
```solidity
pragma solidity 0.8.33;
// Use issuance-audit's import structure
```

**B. Update imports to centralized interfaces**
```solidity
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
// etc.
```

**C. Ensure AllocationManager delegates to library**
```solidity
// The pattern should be:
function _presentPOI(...) internal returns (uint256, bool) {
    // Construct params struct
    AllocationHandler.PresentParams memory params = AllocationHandler.PresentParams({
        // populate fields
    });

    // Delegate to library
    return AllocationHandler.presentPOI(params);
}

// Similar delegation for other functions
```

**D. Verify function signatures match issuance-audit's expectations**
- Return types
- Parameter types
- Visibility modifiers
- Event emissions

### Step 5: Final Compilation Check

```bash
echo "=== FINAL COMPILATION CHECK ==="

echo "Compiling AllocationHandler library..."
forge build --contracts packages/subgraph-service/contracts/libraries/AllocationHandler.sol 2>&1 | tee /tmp/compile-check-AllocationHandler.log

if [ $? -ne 0 ]; then
    echo "❌ ERROR: AllocationHandler compilation failed"
    echo "This is the highest-risk integration point - DO NOT PROCEED"
    exit 1
fi
echo "✅ AllocationHandler compiles"

echo "Compiling AllocationManager contract..."
forge build --contracts packages/subgraph-service/contracts/utilities/AllocationManager.sol 2>&1 | tee /tmp/compile-check-AllocationManager.log

if [ $? -ne 0 ]; then
    echo "❌ ERROR: AllocationManager compilation failed"
    exit 1
fi
echo "✅ AllocationManager compiles"

echo "✅ Both files compile successfully"
```

### Step 6: Mark Conflicts Resolved

```bash
# Stage both files
git add packages/subgraph-service/contracts/libraries/AllocationHandler.sol
git add packages/subgraph-service/contracts/utilities/AllocationManager.sol
```

**Mark complete**: ✅ Update "Completed Steps" above

---

## 3.3 Directory.sol [CRITICAL]

**Conflict File**: `packages/subgraph-service/contracts/utilities/Directory.sol`

### Resolution Strategy
- Accept issuance-audit's base structure
- ADD `recurringCollector` parameter to constructor
- ADD `RECURRING_COLLECTOR` immutable

### Step 1: Understand the Conflict

```bash
# View the conflict
git diff packages/subgraph-service/contracts/utilities/Directory.sol
```

### Step 2: Resolve Conflict

Open `packages/subgraph-service/contracts/utilities/Directory.sol` and:

**A. Accept issuance-audit's pragma and imports**
```solidity
pragma solidity 0.8.33;
// Use issuance-audit's import structure
```

**B. ADD RecurringCollector import**
```solidity
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
```

**C. ADD RecurringCollector immutable**
```solidity
// Add with other immutables:
IRecurringCollector private immutable RECURRING_COLLECTOR;
```

**D. Update constructor to accept recurringCollector**
```solidity
constructor(
    address controller,
    address recurringCollector  // ADD THIS
) Managed(controller) {
    RECURRING_COLLECTOR = IRecurringCollector(recurringCollector);  // ADD THIS
}
```

**E. Keep all other logic from issuance-audit**
- Don't modify any other functions
- Accept issuance-audit's implementation as-is

### Step 3: Mark Conflict Resolved

```bash
# Stage the resolved file
git add packages/subgraph-service/contracts/utilities/Directory.sol
```

### Step 4: Verify Compilation

```bash
echo "Compiling Directory.sol..."
forge build --contracts packages/subgraph-service/contracts/utilities/Directory.sol 2>&1 | tee /tmp/phase3-compile-directory.log

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Directory compilation failed"
    echo "Review errors in /tmp/phase3-compile-directory.log"
    echo "STOP - Do not proceed to next section"
    exit 1
fi

echo "✅ Directory.sol compiles successfully"
```

**If compilation fails**: STOP, review error log, ask user

**Mark complete**: ✅ Update "Completed Steps" above

---

## 3.4 SubgraphServiceStorage.sol [CRITICAL - STORAGE LAYOUT]

**Conflict File**: `packages/subgraph-service/contracts/SubgraphServiceStorage.sol`

⚠️ **STORAGE SAFETY CRITICAL** - Must preserve storage layout for upgradeability

### Resolution Strategy
- Use issuance-audit's storage pattern (likely V1Storage)
- ADD `indexingFeesCut` variable for dips feature
- Verify storage layout safe

### Step 1: Understand the Conflict

```bash
# View the conflict
git diff packages/subgraph-service/contracts/SubgraphServiceStorage.sol
```

### Step 2: Understand Storage Patterns

**issuance-audit likely uses**:
```solidity
contract SubgraphServiceV1Storage {
    // Storage variables
    mapping(address => Indexer) internal indexers;
    // ... other variables
}

contract SubgraphServiceStorage is SubgraphServiceV1Storage {
    // Can be empty or have new variables
}
```

**What we need to ADD**:
```solidity
uint256 internal indexingFeesCut;
```

### Step 3: Resolve Conflict

Open `packages/subgraph-service/contracts/SubgraphServiceStorage.sol` and:

**A. Accept issuance-audit's base structure**
```solidity
pragma solidity 0.8.33;

// Accept issuance-audit's storage contract structure
contract SubgraphServiceV1Storage {
    // ALL variables from issuance-audit
}
```

**B. ADD indexingFeesCut to the extension contract**

If issuance-audit uses inheritance pattern:
```solidity
contract SubgraphServiceStorage is SubgraphServiceV1Storage {
    // ADD this for dips feature:
    uint256 internal indexingFeesCut;
}
```

Or if issuance-audit has everything in one contract:
```solidity
contract SubgraphServiceStorage {
    // ALL existing variables from issuance-audit
    // ...

    // ADD at the END (preserve order):
    uint256 internal indexingFeesCut;
}
```

**C. Ensure NO variables removed or reordered**
- Storage slots must be stable
- Can only ADD new variables at the end
- Cannot remove or change existing variables

### Step 4: Mark Conflict Resolved

```bash
# Stage the resolved file
git add packages/subgraph-service/contracts/SubgraphServiceStorage.sol
```

### Step 5: Verify Compilation

```bash
echo "Compiling SubgraphServiceStorage.sol..."
forge build --contracts packages/subgraph-service/contracts/SubgraphServiceStorage.sol 2>&1 | tee /tmp/phase3-compile-storage.log

if [ $? -ne 0 ]; then
    echo "❌ ERROR: SubgraphServiceStorage compilation failed"
    echo "Review errors in /tmp/phase3-compile-storage.log"
    echo "STOP - Do not proceed to next phase"
    exit 1
fi

echo "✅ SubgraphServiceStorage.sol compiles successfully"
```

### Step 6: Generate Storage Layout for Verification

```bash
echo "Generating storage layout for verification..."
forge inspect packages/subgraph-service/contracts/SubgraphService.sol:SubgraphService storage-layout --pretty > docs/storage-layout-phase3-subgraph-service.txt

echo "Storage layout saved to docs/storage-layout-phase3-subgraph-service.txt"
echo "This will be compared in Phase 5 verification"
```

**Mark complete**: ✅ Update "Completed Steps" above

---

## Phase 3 Complete! ✅

### Verification Checklist

Before proceeding to Phase 4, verify:

- [✅] SubgraphService.sol resolved and compiles
- [✅] AllocationHandler.sol resolved and compiles
- [✅] AllocationManager.sol resolved and compiles
- [✅] Directory.sol resolved and compiles
- [✅] SubgraphServiceStorage.sol resolved and compiles
- [✅] All files staged with `git add`
- [✅] Storage layout generated for verification

### Critical Files Status

```bash
# Verify all critical files staged
git diff --cached --name-only | grep -E "(SubgraphService|AllocationManager|AllocationHandler|Directory|Storage)"
# Should show all 5 files staged
```

### Compilation Logs Created

All compilation logs saved for reference:
```
/tmp/phase3-compile-subgraph-service.log
/tmp/alloc-handler-step1.log through step6.log
/tmp/compile-check-AllocationHandler.log
/tmp/compile-check-AllocationManager.log
/tmp/phase3-compile-directory.log
/tmp/phase3-compile-storage.log
```

### Update Progress Section

1. Change Status to: **✅ Complete**
2. Update "Last Updated" timestamp
3. Mark all steps complete with ✅

### Next Steps

**Proceed to**: `PHASE-4-REMAINING-CONFLICTS.md`

**What's Next**: Resolve remaining conflicts (interfaces, Horizon contracts, package files, tests)

**Important Notes**:
- The hardest part is done (critical contracts resolved)
- Phase 4 conflicts are less risky but still require care
- Continue to verify compilation after each section
- Do not commit yet - verification happens in Phase 5
