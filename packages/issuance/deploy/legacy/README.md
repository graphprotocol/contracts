# Legacy Deployment Code

This directory contains earlier issuance deployment work that is being progressively migrated to the current codebase.

## Goals

Incorporate valuable patterns from earlier work to address critical gaps in the current implementation:

### Critical Implementation Targets

**Smart Contracts & Helpers:**

- ⏳ **IssuanceStateVerifier contract** - GovernanceAssertions helper for verification
- ⏳ **Mock contracts** - MockGraphToken, MockRewardsManager for testing

**Governance Workflow:**

- ⏳ **Three-phase governance workflow** - Prepare/Execute/Verify pattern
- ⏳ **Fork-based governance testing** - Full E2E test with Safe execution
- ⏳ **Verification scripts** - Automated state verification

**Deployment Patterns:**

- ⏳ **Gradual migration strategy** - Deploy → Replicate → Adjust (CRITICAL for mainnet safety)
- ⏳ **Zero-impact deployment pattern** - Deploy without affecting production
- ⏳ **Deployment sequencing** - Documented phase-by-phase rollout
- ⏳ **Pending implementation tracking** - Address book support for upgrade workflows

**Documentation & Verification:**

- ⏳ **Comprehensive verification checklists** - Pre/post deployment validation
- ⏳ **Mermaid diagrams** - Architecture and workflow visualization
- ⏳ **Risk mitigation documentation** - Safety procedures and rollback plans

**Legend:** ✅ Complete | ⏳ Remaining | ❌ Blocked

See [RemainingWork.md](./RemainingWork.md) for detailed implementation plan.

## Status

**Progress:** ~63% complete (17 of 44 files migrated)

**What's Done:**

- ✅ Contracts (IssuanceStateVerifier, mocks) - Incorporated
- ✅ Checkpoint modules (9 files) - Fully migrated
- ✅ Component modules (5 files) - Superseded
- ✅ Package structure - Two-package architecture established

**What Remains:**

- ⏳ Fork-based governance testing (1 file) - CRITICAL for Phase 2
- ⏳ Pending implementation tracking (1 file) - IMPORTANT for Phase 2
- ⏳ Reference scripts (20 files) - Review needed
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

### Phase 2 (Before REO Testing)

**Priority: HIGH** - Required before testnet deployment

1. **Fork-based governance test** - Adapt `test-governance-workflow.ts` for REO
   - Test complete governance flow on forked Arbitrum
   - Validate Safe transaction execution
   - Test checkpoint module assertions

2. **Pending implementation tracking** - Extend address book for upgrades
   - Add `pendingImplementation` field support
   - Update sync-addresses script
   - Document upgrade workflow

3. **Governance scripts review** - Compare with current implementation
   - Extract missing patterns from `lib/` governance modules
   - Ensure TX builder has complete coverage

### Phase 3 (IA Structure)

**Priority: MEDIUM** - Required for IssuanceAllocator gradual migration

1. **Gradual migration patterns** - Recreate when needed
   - ReplicatedAllocation pattern (IA at 100% to RewardsManager)
   - Checkpoint modules for allocation verification
   - Zero-impact deployment validation

2. **Allocation testing** - Comprehensive IA test coverage
   - Allocation adjustment tests
   - Multi-target distribution tests
   - Rollback scenario tests

### Phase 4 (Final Cleanup)

**Priority: LOW** - After Phases 2-3 complete

1. Delete reference scripts after patterns extracted
2. Delete test files after patterns documented
3. Delete config files after addresses captured
4. Delete entire `legacy/packages/` directory

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

## Timeline

- **After Phase 2:** ~85% complete → Fork tests + address book incorporated
- **After Phase 3:** ~95% complete → Gradual migration patterns recreated
- **After Phase 4:** 100% complete → Entire `legacy/packages/` deletable
