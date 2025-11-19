# Legacy Directory - Remaining Work

**Last Updated:** 2025-11-19
**Purpose:** Document what files remain in `legacy/packages/` and what specific work each represents

---

## Summary

After cleanup, **27 files** remain in `legacy/packages/`. Each file represents concrete remaining work:

1. **High-value patterns** (3 files) - Must incorporate in Phase 2-3
2. **Testing patterns** (5 files) - Adapt tests for migrated components
3. **Configuration patterns** (7 files) - Extract deployment/verification/validation patterns
4. **Governance workflows** (6 files in lib/) - Compare with current, extract missing patterns
5. **Deployment scripts** (6 files) - Compare with current tasks, extract missing automation

---

## High-Value Files (Must Incorporate)

### 1. Fork-Based Governance Testing ⭐ CRITICAL - Phase 2

**File:** `packages/issuance/deploy/test-governance-workflow.ts`

**What it does:**

- Forks Arbitrum network at specific block
- Impersonates governance Safe multi-sig
- Deploys issuance components
- Executes governance transactions via Safe
- Validates integration with checkpoint modules

**Why it's valuable:**

- Provides complete E2E testing of governance workflow
- Tests Safe transaction execution
- Validates checkpoint modules work correctly
- Critical for confidence before mainnet deployment

**Remaining work:**

- Adapt for REO deployment workflow
- Update contract names (ServiceQualityOracle → RewardsEligibilityOracle)
- Create test file at `packages/deploy/test/reo-governance-workflow.test.ts`
- Integrate with current checkpoint modules

**Priority:** HIGH - Needed before REO testnet deployment

---

### 2. Address Book with Pending Implementation ⭐ IMPORTANT - Phase 2

**File:** `packages/issuance/deploy/src/address-book.ts`
**Compiled:** `packages/issuance/deploy/lib/src/address-book.js`

**What it provides:**

```typescript
interface IssuanceContractEntry {
  address: string
  implementation?: {
    address: string
    deployedAt?: string
  }
  pendingImplementation?: {
    // ← This feature doesn't exist in Toolshed
    address: string
    deployedAt?: string
    readyForUpgrade?: boolean // Tracks upgrade readiness
  }
}
```

**Why it's valuable:**

- Tracks pending implementation deployments
- Marks when implementations are ready for governance upgrade
- Useful for multi-step upgrade workflows
- Not available in Toolshed AddressBook

**Remaining work:**

- Review implementation details
- Decide: Extend Toolshed AddressBook OR create custom wrapper
- Integrate pending implementation tracking into current workflows

**Priority:** MEDIUM - Useful for upgrade coordination

---

### 3. Governance Transaction Builders (Reference Pattern)

**Files:**

- `lib/ignition/modules/governanceTransactions.js`
- `lib/ignition/modules/upgradePrep.js`
- `lib/ignition/modules/upgradeComplete.js`
- `lib/ignition/modules/verifyUpgradeState.js`

**What they do:**

- Build Safe transaction batches
- Encode function calls for governance
- Coordinate multi-step upgrades

**Why keeping:**

- May contain patterns not yet in current TX builder
- Reference for complex governance workflows

**Remaining work:**

- Review for patterns missing in current `packages/deploy/governance/`
- Extract any valuable patterns
- Can delete after thorough review

**Priority:** LOW - Current TX builder is likely sufficient

---

## Testing Patterns (5 files) - Create Tests for Migrated Components

### packages/deploy/test/issuance-active.test.ts

**What it tests:** Legacy checkpoint modules (IssuanceAllocatorActive, ServiceQualityOracleActive, IssuanceAllocatorMinter)

**Problem:** Tests OBSOLETE legacy versions, not current migrated modules

**Work needed:**

1. Create equivalent tests in `packages/deploy/test/` for CURRENT checkpoint modules
2. Test RewardsEligibilityOracleActive deploys and calls assertion correctly
3. Test IssuanceAllocatorActive, IssuanceAllocatorMinter work correctly
4. Test assertion failures when governance hasn't executed integration

**Priority:** MEDIUM - Important for deployment confidence

---

### packages/issuance/deploy/test/service-quality-oracle-deploy.test.ts

**What it tests:** ServiceQualityOracle deployment (obsolete contract name)

**Work needed:**

1. Check if `packages/issuance/test/` has equivalent test for RewardsEligibilityOracle
2. If not, create deployment test for REO
3. Can delete after creating modern equivalent

---

### packages/issuance/deploy/test/issuance-state-verifier.test.ts

**What it tests:** IssuanceStateVerifier assertions work correctly

**Work needed:**

1. Check if `packages/issuance/test/` tests IssuanceStateVerifier
2. Ensure all assertion functions are tested (assertRewardsEligibilityOracleSet, etc.)
3. Can delete after confirming coverage

---

### packages/issuance/deploy/test/deployment.test.js & packages/deploy/test/issuance-active-smoke.test.ts

**What they test:** General deployment workflows and smoke tests

**Work needed:**

1. Extract deployment testing patterns
2. Create modern equivalents in current test structure
3. Can delete after patterns extracted

---

## Configuration Patterns (7 files) - Extract Deployment Settings

### ignition/configs/issuance.arbitrumSepolia.json5 (LEGACY)

**Current file exists:** `packages/issuance/deploy/ignition/configs/issuance.arbitrumSepolia.json5`

**Legacy has that current doesn't:**

- Network metadata (chainId, blockTime, rpcUrl, explorerUrl)
- Deployment configuration (confirmations, gasPrice, gasLimit, timeout)
- Verification settings (apiKey, apiUrl structure)
- Testing flags (enableTestingFeatures, skipInitialValidation)
- Environment requirements validation
- Test accounts structure

**Work needed:**

1. Evaluate if network metadata belongs in configs vs hardhat.config.ts
2. Check if deployment settings should be in hardhat config instead
3. Extract verification patterns if useful for automation
4. Decide if testing flags approach is valuable
5. Extract environment variable validation patterns
6. Can delete after extracting patterns

**Priority:** MEDIUM - May improve deployment automation

---

### ignition/configs/issuance.arbitrumOne.json5 (LEGACY)

**Work needed:** Same analysis as arbitrumSepolia.json5 above

---

### package.json, tsconfig.json, hardhat.config.ts files (LEGACY)

**Work needed:**

1. Compare with current package.json/configs
2. Extract any missing scripts or configuration
3. Can delete after comparison

---

## Governance Workflows (6 files in lib/) - Extract Missing Patterns

### lib/ignition/modules/governanceTransactions.js

**What it does:** Generates governance transaction data WITHOUT executing

- Creates contract references at specific addresses via Ignition
- Returns transaction details for external signing
- Enables flexible governance workflows (Governor, Safe, etc.)

**Current equivalent:** `packages/deploy/governance/tx-builder.ts`

**Legacy approach:**

```javascript
// Uses Ignition modules to generate TX data
const GovernanceTransactionsModule = buildModule('...', (m) => {
  const proxyAdmin = m.contractAt('ProxyAdmin', address)
  const proxy = m.contractAt('TransparentUpgradeableProxy', proxyAddress)
  return { proxyAdmin, proxy, newImplementation }
})
```

**Current approach:**

```typescript
// Manual TX building
txBuilder.addTx({
  to: address,
  data: encodedCalldata,
  value: 0,
})
```

**Work needed:**

1. Compare capabilities: Can current tx-builder generate all needed TXs?
2. Check if Ignition-based TX generation offers advantages
3. Extract pattern if missing capabilities found
4. Can delete after comparison

**Priority:** MEDIUM - Current tx-builder may be sufficient

---

### lib/ignition/modules/upgradePrep.js, upgradeComplete.js, verifyUpgradeState.js

**What they do:** Multi-step upgrade workflow orchestration

**Work needed:**

1. Compare with `packages/deploy/tasks/` to see if equivalent exists
2. Extract workflow patterns if missing
3. Check for overlap with current governance/ directory
4. Can delete after extracting unique patterns

---

### lib/ignition/modules/IssuanceAllocator.js

**What it does:** Legacy IssuanceAllocator deployment module (compiled)

**Work needed:**

1. Already superseded by current IssuanceAllocator.ts module
2. Can delete - no unique patterns

---

### lib/src/address-book.js, contracts.js, index.js

**What they do:** Compiled JavaScript from src/ TypeScript sources

**Work needed:**

1. Focus on src/ TypeScript sources instead
2. Can delete lib/ compiled files after reviewing src/

---

## Deployment Scripts (6 files) - Compare with Current Tasks

### scripts/deploy-governance-upgrade.js

**What it does:** Automated governance upgrade workflow script

**Current equivalent:** `packages/deploy/tasks/*.ts`

**Work needed:**

1. Compare with current task implementations
2. Check if all upgrade steps are automated in current tasks
3. Extract missing automation patterns
4. Can delete after comparison

---

### scripts/deploy-upgrade-prep.js

**What it does:** Prepares upgrade transactions

**Work needed:**

1. Compare with current governance TX builder
2. Extract preparation patterns if missing
3. Can delete after comparison

---

### scripts/deploy.ts, deployAll.js, verify.ts

**What they do:** Legacy deployment and verification automation

**Work needed:**

1. Compare with current Ignition deployment workflows
2. Extract any missing automation patterns
3. Check verification approach vs current
4. Can delete after extracting patterns

---

### scripts/address-book.js, update-address-book.js

**What they do:** Address book management utilities

**Work needed:**

1. Part of src/address-book.ts incorporation work (see High-Value section)
2. Review for address tracking automation
3. Can delete after address book feature incorporated

---

## Source Files (3 files) - TypeScript Sources

### src/address-book.ts

**Status:** See High-Value section above - pending implementation tracking

---

### src/contracts.ts, src/index.ts

**What they do:** Contract type definitions and exports

**Work needed:**

1. Check if current structure has equivalent
2. Extract any useful type definitions
3. Can delete after extracting types

---

## What Has Been Successfully Removed ✅

### Checkpoint Modules (9 files) - Fully Migrated

- ✅ IssuanceAllocatorActive.ts → packages/deploy/ignition/modules/issuance/
- ✅ IssuanceAllocatorMinter.ts → packages/deploy/ignition/modules/issuance/
- ✅ ServiceQualityOracleActive.ts → RewardsEligibilityOracleActive.ts
- ✅ IssuanceAllocatorTargetAllocated.ts (Phase 3, recreate when needed)
- ✅ PilotAllocationActive.ts (Phase 3, recreate when needed)
- ✅ \_refs/RewardsManager.ts → packages/deploy/ignition/modules/horizon/
- ✅ \_refs/GraphToken.ts → packages/deploy/ignition/modules/horizon/
- ✅ \_refs/IssuanceAllocator.ts → packages/deploy/ignition/modules/issuance/\_refs/
- ✅ \_refs/PilotAllocation.ts (Phase 3, recreate when needed)

### Component Modules (5 files) - Superseded

- ✅ ServiceQualityOracle.ts → RewardsEligibilityOracle.ts (improved)
- ✅ IssuanceAllocator.ts → Current version (better proxy handling)
- ✅ DirectAllocationImplementation.ts → DirectAllocation.ts
- ✅ GovernanceCheckpoint.ts → Stateless pattern used instead
- ✅ GraphProxyAdmin2.ts → Not needed

### Target Modules (3 files) - Phase 3 Patterns

- ✅ BasicIssuanceInfrastructure.ts (simple composition, documented)
- ✅ PilotAllocation.ts (gradual migration, recreate in Phase 3)
- ✅ ReplicatedAllocation.ts (gradual migration, recreate in Phase 3)

**Total removed:** 17 obsolete files

---

## Actionable Next Steps

### Phase 2 (Before REO Testing)

1. **Priority 1:** Incorporate fork-based governance test pattern
   - Create `packages/deploy/test/reo-governance-workflow.test.ts`
   - Adapt legacy test-governance-workflow.ts
   - Test complete governance flow on fork

2. **Priority 2:** Review address book pending implementation feature
   - Evaluate if Toolshed AddressBook can be extended
   - Or create custom wrapper for pending implementation tracking

3. **Priority 3:** Review lib/ governance transaction scripts
   - Compare with current `packages/deploy/governance/` implementation
   - Extract any missing patterns
   - Delete if no unique value found

### Phase 3 (IA Structure)

1. Recreate gradual migration patterns when needed:
   - ReplicatedAllocation pattern (IA at 100% to RewardsManager)
   - PilotAllocation pattern (test allocation target)
   - Checkpoint modules for target allocation verification

### Phase 4 (Final Cleanup)

1. Delete all reference scripts after patterns extracted
2. Delete test files after patterns documented
3. Delete config files after addresses captured
4. Delete lib/ directory after thorough review
5. Delete entire legacy/packages/ directory

---

## Metrics

| Category           | Files Remaining | Files Removed | Status            |
| ------------------ | --------------- | ------------- | ----------------- |
| Checkpoint Modules | 0               | 9             | ✅ Complete       |
| Component Modules  | 0               | 5             | ✅ Complete       |
| Target Modules     | 0               | 3             | ✅ Complete       |
| High-Value Code    | 3               | 0             | ⏳ Phase 2-3      |
| Reference Scripts  | 20              | 0             | ⏳ Review needed  |
| Configuration      | 4               | 0             | ⏳ Reference only |
| **Total**          | **27**          | **17**        | **63% cleaned**   |

---

## Timeline to Full Cleanup

- **After Phase 2:** ~85% complete (high-value code incorporated)
- **After Phase 3:** ~95% complete (gradual migration patterns recreated)
- **After Phase 4:** 100% complete (entire legacy/packages/ deletable)

---

**Status:** Legacy directory significantly reduced. Only high-value patterns and reference code remain.
