# Convergence Plan: Merging Current Spike with Legacy Implementation

> **ARCHIVED:** Historical analysis document. See [../../RemainingWork.md](../../RemainingWork.md) for current status.


**Created:** 2025-11-19
**Purpose:** Actionable plan to converge two partial implementations into one production-ready codebase
**Priority:** REO deployment first, then complete structure for IA

---

## Executive Summary

We have **two partial implementations** that need to converge:

- **Current spike** - Modern Toolshed integration, clean architecture
- **Legacy implementation** - Production-grade patterns, governance workflow, pending implementation tracking

**This is NOT about extracting examples.** This is about **merging two codebases** where each has strengths the other lacks.

---

## Comparative Analysis

### What Current Has That Legacy Doesn't

| Feature                          | Current                                                                | Legacy                        | Action           |
| -------------------------------- | ---------------------------------------------------------------------- | ----------------------------- | ---------------- |
| Toolshed integration             | ✅ Full integration                                                    | ❌ None                       | **KEEP current** |
| Modern proxy helpers             | ✅ `deployImplementation()`, `deployWithTransparentUpgradeableProxy()` | ❌ Manual                     | **KEEP current** |
| Safe TX builder                  | ✅ Generic `TxBuilder` class                                           | ❌ None                       | **KEEP current** |
| Hardhat task integration         | ✅ `issuance:build-rewards-eligibility-upgrade`                        | ❌ Scripts only               | **KEEP current** |
| Contract artifacts from monorepo | ✅ Imports from actual contracts                                       | ⚠️ May be outdated            | **KEEP current** |
| RewardsEligibilityOracle name    | ✅ Current name                                                        | ❌ Old `ServiceQualityOracle` | **KEEP current** |

### What Legacy Has That Current Doesn't

| Feature                         | Legacy                                | Current             | Action                  |
| ------------------------------- | ------------------------------------- | ------------------- | ----------------------- |
| Pending implementation tracking | ✅ In address book                    | ❌ None             | **ADD to current**      |
| IssuanceStateVerifier contract  | ✅ GovernanceAssertions helper        | ❌ None             | **ADD to current**      |
| Shared GraphProxyAdmin2         | ✅ Shared admin pattern               | ❌ Per-module admin | **EVALUATE**            |
| Mock contracts for testing      | ✅ MockGraphToken, MockRewardsManager | ❌ None             | **ADD to current**      |
| Governance checkpoint detection | ✅ `GovernanceCheckpoint.ts` module   | ❌ Manual           | **ADD to current**      |
| Fork-based governance testing   | ✅ Full test suite                    | ❌ None             | **ADD to current**      |
| Three-phase workflow docs       | ✅ Prepare/Execute/Verify             | ⚠️ Implicit         | **DOCUMENT in current** |
| Gradual migration pattern       | ✅ ReplicatedAllocation               | ❌ None             | **ADD for IA**          |
| Target separation               | ✅ contracts/ vs targets/             | ❌ All in modules/  | **REFACTOR current**    |
| Address book scripts            | ✅ CLI utilities                      | ❌ None             | **ADD to current**      |

### Design Conflicts to Resolve

| Decision            | Current Approach      | Legacy Approach            | Recommendation                              |
| ------------------- | --------------------- | -------------------------- | ------------------------------------------- |
| ProxyAdmin          | Per-module ProxyAdmin | Shared GraphProxyAdmin2    | **Current** for now, shared later if needed |
| Module structure    | Single modules/ dir   | contracts/ vs targets/     | **Legacy** - better separation              |
| Governance workflow | Task-based            | Script-based with checks   | **Merge** - tasks that use checks           |
| Contract naming     | REO (new)             | SQO (old)                  | **Current** - use new names                 |
| Address book        | Toolshed standard     | Extended with pending impl | **Merge** - extend Toolshed                 |

---

## Convergence Strategy: REO Focus

### Phase 1: Foundation Merge (REO Priority)

**Goal:** Merge the patterns needed for production-grade REO deployment

**Duration:** 1-2 days

**Tasks:**

1. **Add IssuanceStateVerifier contract** ✅ HIGH VALUE

   ```
   Source: legacy/packages/issuance/deploy/contracts/IssuanceStateVerifier.sol
   Target: packages/issuance/deploy/contracts/IssuanceStateVerifier.sol
   ```

   - Rename `ServiceQualityOracle` → `RewardsEligibilityOracle` in contract
   - Update interface to match current RewardsManager
   - Add tests

2. **Add mock contracts for testing** ✅ HIGH VALUE

   ```
   Source: legacy/packages/issuance/deploy/contracts/mocks/
   Target: packages/issuance/deploy/contracts/mocks/
   ```

   - Copy MockGraphToken.sol, MockRewardsManager.sol
   - Update to match current contract interfaces

3. **Extend address book with pending implementation** ✅ CRITICAL

   ```
   Source: legacy/packages/issuance/deploy/src/address-book.ts (IssuanceContractEntry interface)
   Target: Extend current Toolshed AddressBook usage
   ```

   - Add `pendingImplementation` field to address book entries
   - Add helper functions for upgrade workflow
   - Document usage pattern

4. **Add governance checkpoint module** ✅ HIGH VALUE

   ```
   Source: legacy/packages/issuance/deploy/ignition/modules/contracts/GovernanceCheckpoint.ts
   Target: packages/issuance/deploy/ignition/modules/governance/GovernanceCheckpoint.ts
   ```

   - Adapt to use IssuanceStateVerifier
   - Integrate with current Ignition modules
   - Add examples for REO integration checks

5. **Restructure module organization** ✅ IMPORTANT

   ```
   Current: ignition/modules/*.ts (flat)
   Target:  ignition/modules/
            ├── contracts/       # Component deployments (REO, IA, DirectAllocation)
            ├── governance/      # Governance integration modules
            ├── proxy/          # Proxy utilities (keep existing)
            └── examples/       # Example usage (keep existing)
   ```

### Phase 2: REO Deployment Testing

**Goal:** Validate REO deployment with governance workflow

**Duration:** 1 day

**Tasks:**

1. **Create REO fork-based test** ✅ CRITICAL

   ```
   Source: Pattern from legacy/packages/issuance/deploy/test-governance-workflow.ts
   Target: packages/issuance/deploy/test/reo-governance-workflow.test.ts
   ```

   - Fork Arbitrum testnet
   - Deploy REO component
   - Simulate governance: upgrade RM, set REO
   - Use IssuanceStateVerifier to validate
   - Verify with assertions

2. **Document REO deployment procedure** ✅ CRITICAL

   ```
   Target: packages/issuance/deploy/docs/REODeployment.md
   ```

   - Component deployment (permissionless)
   - Governance proposal generation
   - Safe batch execution
   - Post-deployment verification
   - Rollback procedures

3. **Create REO governance checklist** ✅ IMPORTANT

   ```
   Target: packages/issuance/deploy/docs/REOGovernanceChecklist.md
   ```

   - Pre-deployment checks
   - Deployment steps
   - Governance proposal review
   - Execution verification
   - Post-deployment monitoring

### Phase 3: Complete Structure (IA Ready)

**Goal:** Complete the patterns for IA deployment (not deploying yet, just structure)

**Duration:** 1-2 days

**Tasks:**

1. **Add gradual migration pattern** ✅ CRITICAL FOR IA

   ```
   Source: legacy/packages/issuance/deploy/ignition/modules/targets/ReplicatedAllocation.ts
   Target: packages/issuance/deploy/ignition/modules/contracts/IssuanceAllocatorReplicated.ts
   ```

   - Pattern for deploying IA at 100% to RM
   - Document 3-stage migration (deploy → activate → adjust)
   - Add to IA module as option

2. **Extend governance TX builder for IA** ✅ IMPORTANT

   ```
   Target: Update packages/issuance/deploy/governance/rewards-eligibility-upgrade.ts
   ```

   - Already supports IA, verify completeness
   - Add minter grant transaction
   - Add allocation adjustment transactions
   - Document usage

3. **Create IA deployment documentation** ✅ IMPORTANT

   ```
   Target: packages/issuance/deploy/docs/IADeployment.md
   ```

   - 3-stage migration strategy
   - Stage 1: Deploy with zero impact (100% to RM)
   - Stage 2: Activate with no distribution change
   - Stage 3: Gradual allocation adjustments
   - Monitoring between stages
   - Rollback procedures

4. **Add IA fork-based tests** ✅ IMPORTANT

   ```
   Target: packages/issuance/deploy/test/ia-governance-workflow.test.ts
   ```

   - Test each stage of migration
   - Test minter grant
   - Test allocation adjustments
   - Test rollback scenarios

### Phase 4: Cleanup & Convergence Complete

**Goal:** Remove legacy directory, all valuable code integrated

**Duration:** 0.5 days

**Tasks:**

1. **Final validation** ✅ CRITICAL
   - All tests passing
   - All documentation complete
   - All valuable patterns integrated
   - Nothing left in legacy that's not in current

2. **Update main documentation** ✅ IMPORTANT

   ```
   Target: packages/issuance/deploy/DEPLOYMENT.md
   ```

   - Reference new docs
   - Update structure to match new organization
   - Add governance workflow section

3. **Archive and remove legacy** ✅ FINAL STEP

   ```
   git rm -r packages/issuance/deploy/legacy/
   ```

   - Only after confirming all valuable code is integrated
   - Commit message: "feat(issuance): complete convergence, remove legacy"

---

## Implementation Checklist

### Foundation Merge (REO Priority)

- [ ] Copy IssuanceStateVerifier.sol, update for REO
- [ ] Copy mock contracts
- [ ] Extend address book with pendingImplementation
- [ ] Add governance checkpoint module
- [ ] Restructure modules: contracts/ governance/ proxy/
- [ ] Update imports across codebase

### REO Deployment Testing

- [ ] Create REO fork-based governance test
- [ ] Write REODeployment.md documentation
- [ ] Write REOGovernanceChecklist.md
- [ ] Test on local fork
- [ ] Dry run on Arbitrum Sepolia fork

### Complete Structure (IA Ready)

- [ ] Add IssuanceAllocatorReplicated module
- [ ] Extend governance TX builder for full IA workflow
- [ ] Write IADeployment.md with 3-stage migration
- [ ] Create IA fork-based tests
- [ ] Test 3-stage migration on fork

### Cleanup

- [ ] Run all tests
- [ ] Review all documentation
- [ ] Verify nothing valuable left in legacy
- [ ] Update main DEPLOYMENT.md
- [ ] Remove legacy directory
- [ ] Final commit

---

## File Migration Map

### Contracts to Migrate

| Legacy File                              | Target Location                          | Modifications    |
| ---------------------------------------- | ---------------------------------------- | ---------------- |
| `contracts/IssuanceStateVerifier.sol`    | `contracts/IssuanceStateVerifier.sol`    | Rename SQO → REO |
| `contracts/mocks/MockGraphToken.sol`     | `contracts/mocks/MockGraphToken.sol`     | None             |
| `contracts/mocks/MockRewardsManager.sol` | `contracts/mocks/MockRewardsManager.sol` | Add REO methods  |

### Modules to Adapt

| Legacy Pattern                              | Target Implementation                              | Notes                     |
| ------------------------------------------- | -------------------------------------------------- | ------------------------- |
| `modules/contracts/ServiceQualityOracle.ts` | Already exists as `RewardsEligibilityOracle.ts`    | Compare, merge best parts |
| `modules/contracts/GovernanceCheckpoint.ts` | `modules/governance/GovernanceCheckpoint.ts`       | New location              |
| `modules/contracts/GraphProxyAdmin2.ts`     | Optional - evaluate later                          | May not need shared admin |
| `modules/targets/ReplicatedAllocation.ts`   | `modules/contracts/IssuanceAllocatorReplicated.ts` | Merge into IA module      |

### Scripts/Tests to Adapt

| Legacy Pattern                         | Target Implementation                  | Notes              |
| -------------------------------------- | -------------------------------------- | ------------------ |
| `test-governance-workflow.ts`          | `test/reo-governance-workflow.test.ts` | Fork-based test    |
| `src/address-book.ts`                  | Extend Toolshed AddressBook            | Merge patterns     |
| `scripts/deploy-governance-upgrade.js` | Already covered by tasks               | Task-based instead |

---

## Risk Mitigation

### Critical Risks

1. **Breaking current Toolshed integration**
   - Mitigation: Test thoroughly after each change
   - Validation: Run existing tests continuously

2. **Losing valuable legacy patterns**
   - Mitigation: Use this convergence plan as checklist
   - Validation: Code review before deleting legacy

3. **Incomplete governance workflow**
   - Mitigation: Fork-based testing before testnet
   - Validation: Full dry-run on Arbitrum Sepolia fork

### Testing Strategy

1. **Unit tests** - All new/modified code
2. **Integration tests** - Ignition modules work together
3. **Fork tests** - Full governance workflow on fork
4. **Dry run** - Arbitrum Sepolia before mainnet

---

## Success Criteria

**Phase 1 Complete:**

- ✅ IssuanceStateVerifier integrated and tested
- ✅ Mock contracts available for tests
- ✅ Address book supports pending implementations
- ✅ Governance checkpoint module working
- ✅ Module structure reorganized

**Phase 2 Complete:**

- ✅ REO fork-based test passing
- ✅ REO deployment documentation complete
- ✅ REO governance checklist ready
- ✅ Dry run successful on Arbitrum Sepolia fork

**Phase 3 Complete:**

- ✅ IA gradual migration pattern implemented
- ✅ IA governance TX builder complete
- ✅ IA deployment documentation complete
- ✅ IA fork-based tests passing

**Phase 4 Complete:**

- ✅ All tests passing
- ✅ All documentation updated
- ✅ Legacy directory removed
- ✅ Confidence in production readiness

---

## Next Steps

**Immediate (Today):**

1. Review this convergence plan
2. Approve approach and priorities
3. Begin Phase 1, Task 1 (IssuanceStateVerifier)

**This Week:**

1. Complete Phase 1 (Foundation Merge)
2. Begin Phase 2 (REO Testing)

**Next Week:**

1. Complete Phase 2
2. Complete Phase 3 (IA Structure)
3. Complete Phase 4 (Cleanup)

**Timeline:** ~1 week to full convergence

---

**Status:** Plan ready for review and execution
