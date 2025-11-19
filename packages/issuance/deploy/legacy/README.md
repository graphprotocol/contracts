# Legacy Deployment Code

This directory contains earlier issuance deployment work that is being progressively migrated to the current codebase.

## Goals

Incorporate valuable patterns from earlier work to address critical gaps in the current implementation:

### Implementation Targets

**Smart Contracts & Helpers:**

- ✅ **IssuanceStateVerifier contract** - GovernanceAssertions helper for verification
- ✅ **Mock contracts** - MockGraphToken, MockRewardsManager for testing

**Governance Workflow:**

- ✅ **Three-phase governance workflow** - Prepare/Execute/Verify pattern (checkpoint modules)
- ⏳ **Fork-based governance testing** - Full E2E test with Safe execution
- ✅ **Verification scripts** - Automated state verification (checkpoint modules)

**Deployment Patterns:**

- ✅ **Package structure** - Two-package orchestration architecture established
- ⏳ **Gradual migration strategy** - Deploy → Replicate → Adjust (Phase 3, for IssuanceAllocator)
- ⏳ **Pending implementation tracking** - Address book support for upgrade workflows

**Documentation & Verification:**

- ✅ **Checkpoint module pattern** - Deployment-time state validation
- ⏳ **Comprehensive governance testing** - Fork-based E2E validation

**Legend:** ✅ Complete | ⏳ Remaining | ❌ Blocked

See [RemainingWork.md](./RemainingWork.md) for detailed implementation plan.

## Status

**Progress:** ~90% of work complete (Phase 1, 2, & 2.5 complete)

**Current Phase:** Phase 2.5 Complete → Phase 3 ready when IssuanceAllocator work begins

**What's Done (Phase 1):**

- ✅ Contracts (IssuanceStateVerifier, mocks) - Incorporated
- ✅ Checkpoint modules (9 files) - Fully migrated
- ✅ Component modules (5 files) - Superseded
- ✅ Package structure - Two-package architecture established

**What Remains:**

- ⏳ Fork-based governance testing (1 file) - **Phase 2: Start when REO testnet deployment begins**
- ⏳ Pending implementation tracking (1 file) - **Phase 2: Start when planning governance upgrades**
- ⏳ Gradual migration patterns - **Phase 3: Start when IssuanceAllocator work begins**
- ⏳ Reference scripts (20 files) - Review during Phase 2-3
- ⏳ Config files (4 files) - Reference only

See [LegacyStatus.md](./LegacyStatus.md) for detailed progress tracking.

## Active Documentation

- **[RemainingWork.md](./RemainingWork.md)** - File-by-file inventory of remaining work (27 files)
- **[LegacyStatus.md](./LegacyStatus.md)** - High-level progress summary and timeline

## Legacy Code

The `packages/` directory contains 27 files from earlier deployment work:

- **3 high-value files** - Must incorporate in Phase 2-3
- **5 testing patterns** - Adapt for migrated components
- **7 configuration files** - Extract deployment patterns
- **12 reference scripts** - Compare with current implementation

See [RemainingWork.md](./RemainingWork.md) for detailed breakdown.

## Implementation Plan

### Phase 2 (Before REO Testing) - ✅ COMPLETE

**Status: ✅ COMPLETE**
**Completed: 2025-11-19**

**Tasks Completed:**

1. ✅ **Fork-based governance test** - Created `packages/deploy/test/reo-governance-fork.test.ts`
   - Complete E2E test with network forking
   - **Defaults to Arbitrum One (mainnet)** for realistic governance testing
   - **Supports Arbitrum Sepolia** for testnet validation (via FORK_NETWORK env var)
   - Impersonates governance Controller
   - Tests deployment → integration → verification workflow
   - Uses checkpoint modules for validation

2. ✅ **Pending implementation tracking** - Documented recommendation
   - Decision: Defer to Phase 3+ (not needed for REO deployment)
   - Documentation: `packages/deploy/docs/PendingImplementationTracking.md`
   - Manual tracking sufficient for Phase 2
   - Full implementation recommended when upgrade frequency increases

3. ✅ **Governance scripts review** - Current implementation superior
   - Comparison: `packages/deploy/docs/GovernanceComparison.md`
   - Conclusion: Current TX builder approach is better than legacy
   - No valuable patterns to extract from legacy governance scripts
   - Safe TX JSON generation is production-ready

### Phase 2.5 (Orchestration & Pending Implementation) - ✅ COMPLETE

**Status: ✅ COMPLETE**
**Completed: 2025-11-19**

**Tasks Completed:**

1. ✅ **EnhancedIssuanceAddressBook** - Created `packages/deploy/lib/enhanced-address-book.ts`
   - Extends toolshed's GraphIssuanceAddressBook
   - Adds pending implementation tracking
   - Methods: `setPendingImplementation()`, `activatePendingImplementation()`, `getPendingImplementation()`
   - Enables resumable governance-gated deployments

2. ✅ **Deployment orchestration task** - Created `packages/deploy/tasks/deploy-reo-implementation.ts`
   - Single-command deployment workflow
   - Auto-updates address book with pending implementation
   - Auto-generates Safe TX JSON
   - Prints clear next steps

3. ✅ **Sync task** - Created `packages/deploy/tasks/sync-pending-implementation.ts`
   - Verifies on-chain state matches pending
   - Syncs address book after governance execution
   - Prevents errors from mismatched state

4. ✅ **Utility task** - Created `packages/deploy/tasks/list-pending-implementations.ts`
   - Lists all contracts with pending implementations
   - Shows deployment metadata and status

5. ✅ **Updated TX builder** - Enhanced `packages/deploy/tasks/rewards-eligibility-upgrade.ts`
   - Auto-detects pending implementation from address book
   - No longer requires `--implementation` parameter
   - Falls back to pending if not explicitly provided

6. ✅ **Documentation** - Created `packages/deploy/docs/GovernanceWorkflow.md`
   - Complete workflow guide
   - Examples and troubleshooting
   - Error handling documentation

### Phase 3 (IA Structure)

**Status: NOT STARTED**
**Trigger:** Begin when IssuanceAllocator structure work starts
**Priority: MEDIUM** - Required for IssuanceAllocator gradual migration

**Concrete Tasks:**

1. **Gradual migration patterns** - Recreate from documented legacy patterns
   - **Recreate:** `ReplicatedAllocation` module (IA at 100% allocation to RewardsManager)
   - **Recreate:** Checkpoint modules for allocation verification
   - **Pattern:** Zero-impact deployment (deploy without affecting production)
   - **Reference:** See `legacy/packages/issuance/deploy/ignition/modules/targets/`
   - **Done when:** Can deploy IA that initially replicates current behavior

2. **Allocation testing** - Comprehensive IA test coverage
   - **Test:** Allocation adjustment scenarios
   - **Test:** Multi-target distribution
   - **Test:** Rollback scenarios
   - **Done when:** Full test coverage for IA allocation changes

### Phase 4 (Final Cleanup)

**Status: NOT STARTED**
**Trigger:** After Phases 2-3 complete
**Priority: LOW** - Final cleanup

**Concrete Tasks:**

1. **Delete reference scripts** (20 files) - After patterns extracted and validated
2. **Delete legacy test files** - After patterns adapted to current tests
3. **Delete config files** - After addresses captured in current configs
4. **Delete entire `legacy/packages/` directory** - After all value extracted
5. **Archive legacy docs** - Move planning docs to archive/

**Done when:** Entire `legacy/` directory can be safely deleted

## Archive

Historical analysis and planning documents are archived in [docs/archive/](./docs/archive/):

- Analysis.md - Initial comparison of earlier work vs current implementation
- GapAnalysis.md - Detailed gap analysis
- Conflicts.md - Design conflicts and resolutions
- ConvergenceStrategy.md - Strategic convergence planning
- ConvergencePlan.md - Actionable merger plan
- NextPhaseRecommendations.md - Detailed phase recommendations
- OrchestratorPackageProposal.md - Orchestration package decision (implemented)
- LegacyCodeAudit.md - Initial code inventory

These documents provided valuable analysis during Phase 1 cleanup but are now superseded by the active documentation above.

## What to Do Next

**Current State:** Phase 1 complete, Phase 2 ready to start

**Next action depends on your current work:**

1. **If starting REO testnet deployment:**
   - Begin Phase 2, Task 1: Fork-based governance test
   - See detailed instructions in [RemainingWork.md](./RemainingWork.md#1-fork-based-governance-testing--critical---phase-2)

2. **If planning governance upgrades:**
   - Begin Phase 2, Task 2: Pending implementation tracking
   - See detailed instructions in [RemainingWork.md](./RemainingWork.md#2-address-book-with-pending-implementation--important---phase-2)

3. **If starting IssuanceAllocator work:**
   - Begin Phase 3: Gradual migration patterns
   - See [RemainingWork.md](./RemainingWork.md#4-replicatedallocation-pattern--critical-for-ia)

4. **Otherwise:**
   - No action needed - legacy code is properly organized and waiting for Phase 2/3 triggers

## Timeline

- **Phase 1:** ✅ Complete (Contracts, checkpoint modules, package structure)
- **Phase 2:** ✅ Complete (Fork tests, governance review, documentation)
- **Phase 2.5:** ✅ Complete (Pending implementation tracking, orchestration automation)
- **Phase 3:** Ready when IssuanceAllocator work begins (Gradual migration patterns)
- **Phase 4:** Final cleanup (Delete legacy/packages/ directory)

## Key Accomplishments

### From Legacy Code

**Incorporated:**

- ✅ IssuanceStateVerifier contract with assertion helpers
- ✅ Mock contracts for testing (MockGraphToken, MockRewardsManager)
- ✅ Checkpoint module pattern for deployment validation
- ✅ Pending implementation tracking for governance workflows
- ✅ Reference module pattern (_refs/ directories)

**Improved Upon:**

- ✅ TX builder generates Safe-compatible JSON (legacy didn't)
- ✅ Type-safe orchestration tasks (vs. brittle shell scripts)
- ✅ Fork-based governance testing (legacy only had stubs)
- ✅ Hardhat task integration (vs. standalone scripts)

### New Infrastructure

**Created:**

- ✅ Complete fork-based governance workflow test
- ✅ Enhanced address book with pending implementation support
- ✅ Automated deployment orchestration tasks
- ✅ Comprehensive workflow documentation
- ✅ Error handling and verification safeguards
