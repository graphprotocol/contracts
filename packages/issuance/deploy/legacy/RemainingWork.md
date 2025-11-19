# Legacy Directory - Remaining Work

**Last Updated:** 2025-11-19
**Purpose:** Document what files remain in `legacy/packages/` and what specific work each represents

---

## Summary

After Phase 2.5 cleanup, **21 files** remain in `legacy/packages/`. Each file represents concrete remaining work:

1. **High-value patterns** (1 file) - Must incorporate before REO testnet deployment
2. **Testing patterns** (5 files) - Adapt tests for migrated components
3. **Configuration patterns** (7 files) - Extract deployment/verification/validation patterns
4. **Governance workflows** (2 files in lib/) - Compare with current, extract missing patterns
5. **Deployment scripts** (3 files) - Compare with current tasks, extract missing automation
6. **Source type definitions** (3 files) - Extract type patterns if useful

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

### 2. ~~Address Book with Pending Implementation~~ ✅ COMPLETE - Phase 2.5

**Status:** ✅ INCORPORATED in Phase 2.5

**Implementation:** Created `EnhancedIssuanceAddressBook` wrapper in `packages/deploy/lib/enhanced-address-book.ts`

**What was incorporated:**

- Pending implementation tracking via wrapper pattern
- Methods: `setPendingImplementation()`, `activatePendingImplementation()`, `getPendingImplementation()`
- Integrated with orchestration tasks (deploy, sync, list)
- Full documentation in [GovernanceWorkflow.md](../../deploy/docs/GovernanceWorkflow.md)

**Legacy files now obsolete:**

- ✅ `packages/issuance/deploy/src/address-book.ts` - Pattern incorporated
- ✅ `packages/issuance/deploy/lib/src/address-book.js` - Compiled version
- ✅ `packages/issuance/deploy/scripts/address-book.js` - Script incorporated
- ✅ `packages/issuance/deploy/scripts/update-address-book.js` - Script incorporated

**Can be deleted:** Yes, after Phase 2.5 commit

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

### ~~scripts/deploy-governance-upgrade.js~~ ✅ COMPLETE - Phase 2.5

**Status:** ✅ INCORPORATED in Phase 2.5

**Implementation:** Pattern incorporated in `packages/deploy/tasks/deploy-reo-implementation.ts`

**What was incorporated:**

- Automated deployment → address book → TX generation workflow
- Safe TX JSON output with clear next steps
- Resumable deployment pattern

**Can be deleted:** Yes, after Phase 2.5 commit

---

### ~~scripts/deploy-upgrade-prep.js~~ ✅ COMPLETE - Phase 2.5

**Status:** ✅ INCORPORATED in Phase 2.5

**Implementation:** Pattern incorporated in `packages/deploy/tasks/rewards-eligibility-upgrade.ts` and `deploy-reo-implementation.ts`

**What was incorporated:**

- TX preparation and batching
- Auto-detection of pending implementations
- Safe TX JSON generation

**Can be deleted:** Yes, after Phase 2.5 commit

---

### scripts/deploy.ts, deployAll.js, verify.ts

**What they do:** Legacy deployment and verification automation

**Work needed:**

1. Compare with current Ignition deployment workflows
2. Extract any missing automation patterns
3. Check verification approach vs current
4. Can delete after extracting patterns

---

### ~~scripts/address-book.js, update-address-book.js~~ ✅ COMPLETE - Phase 2.5

**Status:** ✅ INCORPORATED in Phase 2.5

**Implementation:** Pattern incorporated in `packages/deploy/lib/enhanced-address-book.ts` and `packages/deploy/tasks/sync-pending-implementation.ts`

**What was incorporated:**

- Address book update automation
- Pending implementation activation
- On-chain verification before sync

**Can be deleted:** Yes, after Phase 2.5 commit

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
| High-Value Code    | 1               | 2             | ⏳ Phase 2        |
| Address Book       | 0               | 4             | ✅ Phase 2.5      |
| Governance Scripts | 0               | 3             | ✅ Phase 2.5      |
| Reference Scripts  | 14              | 6             | ⏳ Review needed  |
| Configuration      | 4               | 0             | ⏳ Reference only |
| Type Definitions   | 2               | 1             | ⏳ Reference only |
| **Total**          | **21**          | **33**        | **61% cleaned**   |

---

## Timeline to Full Cleanup

- **After Phase 2:** ~70% complete (fork test incorporated)
- **After Phase 2.5:** ✅ ~88% complete (address book + orchestration incorporated)
- **After Phase 3:** ~95% complete (gradual migration patterns recreated)
- **After Phase 4:** 100% complete (entire legacy/packages/ deletable)

---

**Status:** Legacy directory significantly reduced. Only high-value patterns and reference code remain.
