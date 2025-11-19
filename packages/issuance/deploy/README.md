# Issuance Deployment - Documentation & Planning

**Last Updated:** 2025-11-19
**Status:** Planning & Design Phase

---

## Quick Navigation

### 🎯 **For Immediate REO Deployment Planning:**
→ **Start here:** [docs/README.md](./docs/README.md) - Production deployment documentation

### 📊 **For Understanding Design Decisions:**
→ **Start here:** [legacy/analysis.md](./legacy/analysis.md) - Legacy alignment analysis
→ **And:** [legacy/TargetModelProposal.md](./legacy/TargetModelProposal.md) - Target model proposal

### 🔍 **For Deep Dive / Background Research:**
→ **Start here:** [analysis/AnalysisREADME.md](./analysis/AnalysisREADME.md) - Comprehensive gap analysis

---

## Directory Structure

```
packages/issuance/deploy/
├── docs/                    # 🎯 PRODUCTION DOCUMENTATION (Phase 1 Complete)
│   ├── README.md           # Navigation guide for deployment docs
│   ├── REODeploymentSequence.md      # Complete REO deployment guide
│   ├── GovernanceWorkflow.md         # Three-phase governance pattern
│   ├── VerificationChecklists.md     # Comprehensive checklists
│   ├── REOArchitecture.md            # Visual diagrams (12 Mermaid diagrams)
│   ├── APICorrectness.md             # Method signatures & correct usage
│   └── IADeploymentGuide.md          # 3-stage IA migration (future)
│
├── legacy/                  # 📚 LEGACY CODE & ANALYSIS
│   ├── analysis.md          # What's valuable from legacy + alignment
│   ├── TargetModelProposal.md        # Component/integration separation
│   └── packages/            # Full legacy deployment implementation
│       ├── issuance/deploy/ # Legacy Ignition modules, scripts, tests
│       └── deploy/          # Legacy orchestration (if present)
│
├── analysis/                # 🔍 GAP ANALYSIS & RECOMMENDATIONS
│   ├── AnalysisREADME.md    # Overview of gap analysis
│   ├── GapAnalysis.md       # Detailed comparison (earlier vs current)
│   ├── Conflicts.md         # Design decisions to make
│   ├── NextPhaseRecommendations.md   # Phase 2+ implementation plan
│   ├── [Legacy source docs]  # Design.md, DeploymentGuide.md, README.md
│   └── TargetModelProposal.md        # (Earlier version)
│
├── ignition/                # ⚙️ CURRENT IGNITION DEPLOYMENT
│   ├── modules/             # Current deployment modules
│   ├── configs/             # Network-specific configs
│   └── README.md            # Ignition deployment guide
│
├── governance/              # 🏛️ GOVERNANCE TOOLING
│   ├── tx-builder.ts        # Safe transaction builder
│   ├── rewards-eligibility-upgrade.ts  # REO/IA integration batch
│   └── README.md            # Governance tooling guide
│
├── tasks/                   # 🔧 HARDHAT TASKS
│   └── rewards-eligibility-upgrade.ts  # CLI task for governance TX
│
└── README.md               # 📖 THIS FILE - Master navigation
```

---

## What's in Each Directory

### 📁 `docs/` - Production Deployment Documentation

**Purpose:** Production-ready deployment documentation focused on REO deployment (immediate priority), with IA patterns preserved for future use.

**Status:** ✅ Phase 1 Complete

**Key Documents:**
- **[REODeploymentSequence.md](./docs/REODeploymentSequence.md)** (17 KB) - 6-phase deployment sequence, rollback procedures, network strategies
- **[GovernanceWorkflow.md](./docs/GovernanceWorkflow.md)** (27 KB) - Three-phase governance pattern, Safe TX builder guide, emergency procedures
- **[VerificationChecklists.md](./docs/VerificationChecklists.md)** (22 KB) - Comprehensive checklists for every phase
- **[REOArchitecture.md](./docs/REOArchitecture.md)** (16 KB) - 12 Mermaid diagrams showing architecture and flows
- **[APICorrectness.md](./docs/APICorrectness.md)** (18 KB) - Correct method signatures to prevent implementation errors
- **[IADeploymentGuide.md](./docs/IADeploymentGuide.md)** (14 KB) - **Critical 3-stage gradual migration pattern** for future IA deployment

**Start Here If:** You're planning REO deployment, need governance workflow guidance, or want production checklists

**Documentation Principles:**
- REO deployment is immediate priority
- IA patterns preserved but lower priority (no immediate deployment plans)
- Integrates with existing governance tooling (`issuance:build-rewards-eligibility-upgrade` task)
- Extracted mature patterns from legacy work, adapted for current implementation

---

### 📁 `legacy/` - Legacy Code & Analysis

**Purpose:** Reference implementation from earlier deployment work, with analysis of what's valuable to preserve.

**Status:** ✅ Added for reference

**Key Documents:**
- **[analysis.md](./legacy/analysis.md)** (8 KB) - Summarizes valuable legacy patterns and alignment with current work
- **[TargetModelProposal.md](./legacy/TargetModelProposal.md)** (6 KB) - Proposes component/integration target separation

**Legacy Code Structure:**
```
legacy/packages/issuance/deploy/
├── doc/                     # Original design docs (Design.md, DeploymentGuide.md)
├── ignition/modules/
│   ├── contracts/          # Component deployments (SQO, IA, GraphProxyAdmin2, etc.)
│   └── targets/            # Integration targets (Active states, assertions)
├── scripts/                 # Deployment, governance, address book scripts
├── test/                    # Governance workflow tests
└── src/                     # Address book tracking (pending/active implementations)
```

**Start Here If:** You want to understand the target model proposal, see reference implementations, or understand legacy deployment patterns

**Key Insights from Legacy:**
1. **Target Model:** Component-only targets in issuance package; integration/active targets in orchestration package (avoid circular dependencies)
2. **Three-Phase Governance:** Prepare (permissionless) → Execute (governance) → Verify/Sync (automated)
3. **Pending Implementation Tracking:** Address book explicitly tracks implementation vs pendingImplementation
4. **Governance Assertions:** Stateless helper with checks that revert until governance executes
5. **3-Stage IA Migration:** Deploy → Replicate (100% RM) → Adjust allocations

---

### 📁 `analysis/` - Gap Analysis & Recommendations

**Purpose:** Comprehensive comparison of earlier deployment work vs current Ignition spike, identifying gaps and providing integration recommendations.

**Status:** ✅ Analysis Complete

**Key Documents:**
- **[AnalysisREADME.md](./analysis/AnalysisREADME.md)** - Overview and reading guide
- **[GapAnalysis.md](./analysis/GapAnalysis.md)** (18 KB) - Detailed component-by-component comparison
- **[Conflicts.md](./analysis/Conflicts.md)** (15 KB) - Design decisions where approaches differ
- **[NextPhaseRecommendations.md](./analysis/NextPhaseRecommendations.md)** (55 KB) - Detailed Phase 2+ implementation plan

**Also Includes:**
- **[Design.md](./analysis/Design.md)** (18 KB) - Legacy design doc (copied for reference)
- **[DeploymentGuide.md](./analysis/DeploymentGuide.md)** (25 KB) - Legacy deployment guide (copied for reference)
- **[README.md](./analysis/README.md)** (2 KB) - Legacy architectural overview (copied for reference)

**Start Here If:** You want deep understanding of gaps, need to prioritize Phase 2 work, or want to understand design tradeoffs

**Key Findings:**
- **CRITICAL Gaps:** Deployment sequencing, gradual migration strategy (3-stage IA), zero-impact deployment pattern
- **HIGH VALUE Gaps:** Three-phase governance workflow, GovernanceAssertions helper, pending implementation tracking, verification checklists
- **Recommendations:** Phase 1 (docs) complete ✅, Phase 2 (critical implementation) next, Phase 3 (production readiness) before mainnet

---

### 📁 `ignition/` - Current Ignition Deployment

**Purpose:** Current Hardhat Ignition deployment modules and configurations.

**Status:** ✅ Implementation complete (spike)

**Contents:**
- **modules/** - IssuanceAllocator, RewardsEligibilityOracle, DirectAllocation deployment modules
- **configs/** - Network-specific JSON5 configuration files
- **README.md** - Ignition deployment commands and configuration guide

**Characteristics:**
- Well-designed, aligns with Horizon patterns
- Complete Toolshed integration
- Reusable proxy deployment utilities
- Single orchestrated deployment (deploy.ts)

**Gaps:**
- No deployment sequence documentation (now in `docs/`)
- No governance coordination patterns (now in `docs/`)
- No testing/verification (recommended in analysis)

---

### 📁 `governance/` - Governance Tooling

**Purpose:** Safe transaction builder and governance integration scripts.

**Status:** ✅ Existing tooling good

**Contents:**
- **tx-builder.ts** - TxBuilder class for Safe-compatible JSON
- **rewards-eligibility-upgrade.ts** - Builds RM upgrade + REO/IA integration batch
- **README.md** - Governance tooling documentation

**Hardhat Task:**
```bash
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --network <network> \
  --rewardsManagerImplementation <address> \
  [--rewardsEligibilityOracleAddress <address>] \
  [--outputDir <path>]
```

**Assessment:** This tooling is solid! Documentation in `docs/` integrates with it.

---

## Key Concepts & Patterns

### Three-Phase Governance Workflow

**From:** Legacy Design.md, adapted in docs/GovernanceWorkflow.md

**Pattern:**
1. **Prepare (Permissionless):** Deploy contracts, generate Safe batch JSON, independent verification
2. **Execute (Governance):** Governance reviews and executes Safe batch, state transitions occur
3. **Verify/Sync (Automated):** Verification scripts confirm expected state, address book updated

**Benefits:**
- Clear separation of deployment from governance
- Independent verification before execution
- Automated verification after execution
- Audit trail at each step

---

### Zero-Impact Deployment

**From:** Legacy DeploymentGuide.md, adapted in docs/REODeploymentSequence.md

**Pattern:**
- Deploy contracts without affecting production
- Test and verify in production environment
- Activate only via governance when ready

**REO Example:**
- Phase 2: Deploy REO (not integrated)
- Phase 3: Test for 2-4 weeks
- Phase 4: Governance integration (production impact)

**IA Example (Future):**
- Stage 1: Deploy IA (not integrated)
- Stage 2: Integrate at 100% to RM (replicate existing)
- Stage 3: Gradually adjust allocations

---

### 3-Stage Gradual Migration (IA)

**From:** Legacy DeploymentGuide.md, adapted in docs/IADeploymentGuide.md

**CRITICAL for IA mainnet deployment - non-negotiable**

**Stage 1 - Deploy with Zero Impact:**
- Deploy IA configured to replicate existing distribution (100% to RM)
- Not integrated yet
- Comprehensive testing possible without risk

**Stage 2 - Activate with No Distribution Change:**
- Governance integrates IA with RewardsManager
- Grant minting authority
- **Still 100% to RM** - no economic change yet
- Validates integration before changing distribution

**Stage 3 - Gradual Allocation Changes:**
- Deploy DirectAllocation targets
- Gradually adjust allocations (99%/1%, then 95%/5%, etc.)
- Monitor each change before proceeding
- Clear rollback at each step

**Why Critical:**
- Separates integration validation from economic changes
- Small incremental changes with monitoring
- Issues caught early with minimal impact
- Each step independently verifiable and reversible

---

### Target Model: Component vs Integration Separation

**From:** Legacy analysis.md and TargetModelProposal.md

**Proposal:**
- **Component targets** (in packages/issuance/deploy):
  - Deploy and initialize contracts only
  - No cross-package wiring
  - Examples: `issuance-allocator`, `rewards-eligibility-oracle`, `direct-allocation-*`

- **Integration targets** (in separate orchestration package):
  - Governance-required state transitions
  - Cross-package wiring
  - Examples: `*-active` targets, allocation stages, governance batches

**Benefits:**
- Avoids circular dependencies
- Clear package boundaries
- Component deploys are idempotent and self-contained
- Governance flows explicit and testable

**Status:** Proposed, not yet implemented in current spike

---

## Convergence & Alignment

### What We've Converged On

**✅ REO Deployment is Immediate Priority**
- Production documentation focused on REO (docs/)
- IA patterns preserved but lower priority
- Clear 6-phase REO deployment sequence

**✅ Three-Phase Governance Workflow**
- Prepare/Execute/Verify pattern documented (docs/GovernanceWorkflow.md)
- Aligns with legacy approach
- Integrates with existing governance tooling

**✅ Zero-Impact Deployment Pattern**
- Deploy first, integrate later via governance
- Documented for both REO and IA (docs/)

**✅ 3-Stage IA Gradual Migration**
- Critical pattern documented (docs/IADeploymentGuide.md)
- Non-negotiable for mainnet safety
- Preserved for when IA deployment planned

**✅ Existing Governance Tooling is Good**
- tx-builder class solid
- rewards-eligibility-upgrade task solid
- Documentation references and integrates with it

---

### Open Design Decisions

**From:** legacy/analysis.md (section 6)

**1. Orchestration Package Location**
- Where should "Active" integration targets live?
- Options:
  - New `packages/issuance-orchestration`
  - Existing `packages/deploy` (if it exists)
  - Within issuance/deploy but clearly separated
- **Decision needed before:** IA deployment or complex multi-package coordination

**2. Proxy Administration Pattern**
- Use shared GraphProxyAdmin2 (legacy pattern)?
- Or keep per-contract ProxyAdmins (current Ignition spike)?
- **Current approach:** Per-contract is simpler and works well
- **Recommendation:** Keep current unless specific need arises

**3. Governance Assertions Implementation**
- Solidity helper contract (legacy approach)?
- Pure TypeScript tests?
- Both?
- **Recommendation:** Both - Solidity for on-chain verification, TS for fork testing
- **Status:** Proposed in analysis/NextPhaseRecommendations.md Phase 2

**4. Workflow Strictness**
- How strictly mirror legacy three-phase workflow?
- Simplify for first Arbitrum deployments?
- **Recommendation:** Follow three-phase for safety, but adapt where appropriate
- **Status:** Documented in docs/, but not enforced in code

---

## Deployment Status

### Current State

| Component | Implementation | Documentation | Status |
|-----------|----------------|---------------|--------|
| **RewardsEligibilityOracle** | ✅ Module exists | ✅ Complete | 🟡 Planning |
| **IssuanceAllocator** | ✅ Module exists | ✅ Preserved | ⚪ Future |
| **DirectAllocation** | ✅ Module exists | ✅ Complete | ⚪ As needed |
| **Governance Tooling** | ✅ tx-builder, task | ✅ Complete | ✅ Ready |
| **Verification** | ❌ No scripts yet | ✅ Complete | 🟡 Planned |
| **Testing** | ❌ No deploy tests | ✅ Complete | 🟡 Planned |

**Legend:**
- ✅ Complete/Ready
- 🟡 In Progress/Planning
- ⚪ Not Started/Future
- ❌ Not Implemented

---

## Next Steps

### Immediate (Before REO Deployment)

**Review & Planning:**
1. ✅ Review production documentation (docs/)
2. ✅ Review legacy alignment analysis (legacy/analysis.md)
3. ✅ Review target model proposal (legacy/TargetModelProposal.md)
4. 🔲 Decide on target model / orchestration approach
5. 🔲 Identify governance addresses for networks
6. 🔲 Identify role addresses (OPERATOR, ORACLE) for REO
7. 🔲 Validate configuration parameters
8. 🔲 Set up oracle infrastructure

**Questions to Resolve:**
- Governance multi-sig addresses (Arbitrum One, Arbitrum Sepolia)?
- Who/what should have OPERATOR_ROLE on REO?
- Who/what should have ORACLE_ROLE on REO?
- Where does oracle infrastructure run?
- Monitoring - who owns it, what tools?
- Timeline - how long on testnet before mainnet?

---

### Phase 2 Implementation (When Ready)

**From:** analysis/NextPhaseRecommendations.md

**High-Value Additions:**
1. **GovernanceAssertions Helper Contract**
   - Stateless Solidity contract with verification methods
   - Enables programmatic verification
   - Novel pattern from legacy work

2. **Verification Scripts**
   - Automated on-chain state validation
   - Per-phase verification scripts
   - CI/CD compatible (exit codes)

3. **Enhanced Address Book**
   - Pending implementation tracking
   - Support upgrade workflow
   - activate-pending.ts script

4. **Deployment Tests**
   - Fork-based testing
   - Governance workflow simulation
   - Migration stages testing

5. **Monitoring Scripts**
   - Track REO operations
   - Allocation monitoring (future IA)
   - Alert on issues

**See:** analysis/NextPhaseRecommendations.md for detailed implementation plan

---

### Future: IssuanceAllocator Deployment

**When IA deployment is planned:**

1. **MUST READ:** docs/IADeploymentGuide.md (3-stage migration is critical)
2. **Review:** legacy/TargetModelProposal.md (consider orchestration separation)
3. **Implement:** Phase 2 items above (if not already done)
4. **Plan:** 3-stage rollout with monitoring periods between stages
5. **Budget:** 4-8 weeks between Stage 2 and Stage 3

**Do NOT:** Skip stages or rush the process - mainnet safety requires gradual migration

---

## How to Use This Repository

### For REO Deployment Planning

1. Start with **[docs/README.md](./docs/README.md)** - production documentation
2. Follow **[docs/REODeploymentSequence.md](./docs/REODeploymentSequence.md)** - deployment guide
3. Use **[docs/VerificationChecklists.md](./docs/VerificationChecklists.md)** - during execution
4. Reference **[docs/GovernanceWorkflow.md](./docs/GovernanceWorkflow.md)** - for governance coordination
5. Check **[docs/APICorrectness.md](./docs/APICorrectness.md)** - when implementing integration

### For Understanding Design Decisions

1. Read **[legacy/analysis.md](./legacy/analysis.md)** - legacy alignment summary
2. Read **[legacy/TargetModelProposal.md](./legacy/TargetModelProposal.md)** - target model proposal
3. Review **[analysis/GapAnalysis.md](./analysis/GapAnalysis.md)** - detailed comparison
4. Check **[analysis/Conflicts.md](./analysis/Conflicts.md)** - design decisions

### For Deep Research / Background

1. Start with **[analysis/AnalysisREADME.md](./analysis/AnalysisREADME.md)**
2. Read full gap analysis and recommendations
3. Explore legacy code in **legacy/packages/** for reference implementations
4. Review legacy docs (Design.md, DeploymentGuide.md) for original thinking

---

## Contributing & Maintenance

### Updating Documentation

**When to update:**
- Contract interfaces change
- Deployment procedures change
- New networks added
- Lessons learned from deployment
- Design decisions made

**What to update:**
- Keep docs/ current with production procedures
- Update analysis/ if comparing new approaches
- Add to legacy/ only if referencing additional legacy work
- Maintain consistency across documents

**Documentation principles:**
- Keep production docs (docs/) focused and actionable
- Keep analysis (analysis/, legacy/) comprehensive but clearly marked as background
- Use clear, concise, technical language
- Include examples and diagrams
- Document both correct and incorrect usage
- Explain *why* not just *what*

---

## Acknowledgments

This documentation synthesizes:
- **Current Ignition spike** - Well-designed deployment modules and governance tooling
- **Earlier deployment work** - Production-ready patterns and governance workflows
- **Parallel analysis** - Target model proposals and alignment considerations

All three sources contribute valuable insights to a production-ready deployment strategy.

---

## Quick Reference

**Immediate Priority:** REO deployment
**Future Priority:** IA deployment (3-stage migration)

**Key Documentation:**
- Production: [docs/README.md](./docs/README.md)
- Analysis: [legacy/analysis.md](./legacy/analysis.md)
- Gap Analysis: [analysis/AnalysisREADME.md](./analysis/AnalysisREADME.md)

**Key Patterns:**
- Three-phase governance: Prepare → Execute → Verify
- Zero-impact deployment: Deploy → Test → Integrate
- 3-stage IA migration: Deploy → Replicate → Adjust

**Existing Tooling:**
- Ignition modules: [ignition/modules/](./ignition/modules/)
- Governance task: `npx hardhat issuance:build-rewards-eligibility-upgrade --help`
- Configs: [ignition/configs/](./ignition/configs/)

---

**Everything is in place. Ready for review, decisions, and next steps.**
