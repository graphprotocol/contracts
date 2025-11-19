# Issuance Deployment Documentation

**Last Updated:** 2025-11-19

---

## Overview

This directory contains production-ready deployment documentation for Graph Protocol's issuance contracts. The documentation focuses on **RewardsEligibilityOracle (REO)** deployment (immediate priority) while preserving patterns for **IssuanceAllocator (IA)** deployment (future).

---

## Quick Start

### For REO Deployment (Immediate Priority)

**Read in this order:**

1. **[REODeploymentSequence.md](./REODeploymentSequence.md)** - Complete deployment sequence
2. **[GovernanceWorkflow.md](./GovernanceWorkflow.md)** - Three-phase governance pattern
3. **[VerificationChecklists.md](./VerificationChecklists.md)** - Comprehensive checklists for each phase
4. **[REOArchitecture.md](./REOArchitecture.md)** - Visual diagrams and architecture
5. **[APICorrectness.md](./APICorrectness.md)** - Correct method signatures and usage

### For IA Deployment (Future)

**When IA deployment is planned:**

1. **[IADeploymentGuide.md](./IADeploymentGuide.md)** - Critical 3-stage migration pattern
2. **[APICorrectness.md](./APICorrectness.md)** - IA section for correct integration
3. **[GovernanceWorkflow.md](./GovernanceWorkflow.md)** - Applies to IA as well

---

## Document Index

### REO Deployment Documents

#### [REODeploymentSequence.md](./REODeploymentSequence.md)

**Complete deployment sequence for RewardsEligibilityOracle**

**Contents:**

- **6-Phase Deployment:** RM Upgrade → REO Deployment → Testing → Integration → Monitoring → Enable Validation
- **Stage-by-stage breakdown** of Phase 2 deployment
- **Dependency graph** showing sequencing constraints
- **Risk mitigation strategies** for each phase
- **Rollback procedures** at each stage
- **Network-specific considerations** (testnet vs mainnet)
- **Existing tooling reference** (Ignition, governance tasks)
- **Configuration parameters** with rationale

**When to use:** Primary reference for planning and executing REO deployment

---

#### [GovernanceWorkflow.md](./GovernanceWorkflow.md)

**Three-phase governance pattern for deployment and integration**

**Contents:**

- **Phase 1: Prepare (Permissionless)** - Deploy contracts, generate proposals
- **Phase 2: Execute (Governance)** - Review and execute transactions
- **Phase 3: Verify/Sync (Automated)** - Confirm state and update docs
- **Governance transaction patterns** for all scenarios (upgrades, integration, config, roles)
- **Safe Transaction Builder guide** with step-by-step instructions
- **Verification procedures** for on-chain state
- **Emergency procedures** and rollback options
- **Communication plan** for governance and community

**When to use:** Understanding governance coordination, preparing proposals, executing governance actions

---

#### [VerificationChecklists.md](./VerificationChecklists.md)

**Comprehensive checklists for every deployment phase**

**Contents:**

- **Pre-Deployment Checklist** - Code, config, roles, infrastructure
- **Phase-by-phase checklists** for all 6 REO deployment phases
- **Contract deployment verification** - Addresses, initialization, ownership
- **Integration verification** - RM connection, role configuration
- **Testing period checklist** - Smart contracts, oracle operations, security
- **Monitoring period checklist** - Metrics, alerts, ongoing verification
- **Post-deployment documentation** checklist
- **Emergency procedures checklist**
- **Quick reference** tables and commands

**When to use:** During deployment execution, ensuring nothing is missed, creating audit trail

---

#### [REOArchitecture.md](./REOArchitecture.md)

**Visual diagrams and architecture documentation**

**Contents:**

- **Contract architecture** - Component relationships graph
- **Deployment sequence** - Phase-by-phase sequence diagram
- **Governance workflow** - Three-phase state diagram
- **REO lifecycle states** - State transition diagram
- **Integration flow** - RM + REO query flow
- **Oracle operations** - Data submission flow
- **Proxy administration** - Upgrade pattern
- **Dependency graph** - Critical path and governance gates
- **Rollback procedures** - Rollback flow diagram
- **Monitoring architecture** - Metrics and alerting
- **Access control** - Role-based permissions
- **Network topology** - Multi-network deployment
- **Future IA integration** - Complete issuance system

**When to use:** Communicating architecture, governance proposals, presentations, understanding system design

---

#### [APICorrectness.md](./APICorrectness.md)

**Correct method signatures and usage to prevent implementation errors**

**Contents:**

- **REO methods** with correct signatures and examples
- **RewardsManager integration** methods
- **IssuanceAllocator methods** (future use section)
- **GraphToken methods** for minting authority
- **Proxy administration** methods
- **Common mistakes** and how to avoid them
- **Quick reference tables** for all methods
- **Testing examples** using Hardhat console and scripts

**When to use:** Implementing integration code, writing scripts, debugging integration issues, preventing common errors

---

### IA Deployment Documents (Future)

#### [IADeploymentGuide.md](./IADeploymentGuide.md)

**Critical 3-stage gradual migration pattern for IssuanceAllocator**

**Contents:**

- **Stage 1: Deploy with Zero Impact** - Deploy without production changes
- **Stage 2: Activate with No Distribution Change** - Integrate at 100% to RM
- **Stage 3: Gradual Allocation Changes** - Incrementally adjust distribution
- **Why each stage matters** - Risk mitigation rationale
- **Rollback procedures** for each stage
- **Testing strategy** throughout migration
- **Monitoring requirements** between stages
- **Future enhancements needed** when IA deployment planned

**When to use:** Planning IA deployment, understanding migration strategy, **CRITICAL reading before any IA mainnet deployment**

⚠️ **IMPORTANT:** The 3-stage pattern is non-negotiable for mainnet safety

---

## Key Concepts

### Three-Phase Governance Pattern

**Phase 1: Prepare (Permissionless)**

- Anyone can deploy implementations
- Generate governance transaction data
- Independent verification
- **No production impact**

**Phase 2: Execute (Governance)**

- Governance multi-sig reviews
- Safe batch transaction execution
- State transitions occur
- **Production impact happens**

**Phase 3: Verify/Sync (Automated)**

- Verify expected state achieved
- Update address book
- Activate monitoring
- **Confirmation and documentation**

**Benefits:**

- Clear separation of deployment and governance
- Independent verification before execution
- Automated verification after execution
- Audit trail at each step

---

### Zero-Impact Deployment

**Concept:** Deploy contracts without affecting production system

**REO Example:**

- Phase 2: Deploy REO contracts
- REO exists but not integrated with RewardsManager
- Production rewards unchanged
- Can test, verify, and validate safely
- Phase 4: Governance integration (production impact)

**IA Example (Future):**

- Stage 1: Deploy IA configured at 100% to RM
- IA exists but not integrated
- Zero production impact
- Stage 2: Integrate IA with RM (but still 100% to RM)
- Stage 3: Change allocations gradually

**Benefits:**

- Safe deployment without production risk
- Time to validate before activation
- Independent verification possible
- Clear rollback at each step

---

### Gradual Migration (IA Specific)

**3-Stage Pattern:**

1. **Deploy** - Infrastructure ready, zero impact
2. **Replicate** - Activate while matching existing behavior
3. **Adjust** - Gradually change to target distribution

**Why Gradual:**

- Validates integration before economic changes
- Proves mechanics work (Stage 2)
- Small changes easier to monitor and rollback (Stage 3)
- Each step builds confidence
- Issues caught early with minimal impact

**Critical:** Do not skip stages or rush the process

---

## Deployment Status

### Current State

| Component                    | Status      | Documentation             |
| ---------------------------- | ----------- | ------------------------- |
| **RewardsEligibilityOracle** | 🟡 Planning | REODeploymentSequence.md  |
| **IssuanceAllocator**        | ⚪ Future   | IADeploymentGuide.md      |
| **Governance Tooling**       | 🟢 Ready    | GovernanceWorkflow.md     |
| **Verification**             | 🟡 Planned  | VerificationChecklists.md |

**Legend:**

- 🟢 Ready/Complete
- 🟡 In Progress/Planning
- 🔴 Blocked/Issues
- ⚪ Not Started/Future

---

## Related Documentation

### In This Repository

**Configuration:**

- `../ignition/README.md` - Ignition deployment modules
- `../ignition/configs/` - Network-specific configuration

**Governance:**

- `../governance/README.md` - Governance transaction tooling
- `../governance/rewards-eligibility-upgrade.ts` - TX builder for REO integration

**Existing Integration Docs:**

- `../../DEPLOYMENT.md` - Overview of what was created
- `../../INTEGRATION.md` - Horizon alignment and toolshed integration

### Analysis (Background)

**Earlier Deployment Work Analysis:**

- `../legacy/AnalysisREADME.md` - Overview of analysis
- `../legacy/GapAnalysis.md` - Comparison with current spike
- `../legacy/Conflicts.md` - Design decisions
- `../legacy/NextPhaseRecommendations.md` - Future implementation plan
- `../legacy/ConvergenceStrategy.md` - Convergence strategy (what to keep from each approach)
- Earlier docs in `../legacy/` - Design.md, DeploymentGuide.md, README.md

**Note:** Legacy directory contains background research and earlier work that informed these production docs

---

## Common Tasks

### Planning REO Deployment

1. Read [REODeploymentSequence.md](./REODeploymentSequence.md)
2. Review [GovernanceWorkflow.md](./GovernanceWorkflow.md)
3. Print [VerificationChecklists.md](./VerificationChecklists.md)
4. Identify governance addresses and role holders
5. Set up oracle infrastructure
6. Validate configuration parameters
7. Create deployment timeline

---

### Preparing Governance Proposal

1. Deploy contracts (Phase 1: Prepare)
2. Generate Safe transaction batch:

   ```bash
   cd packages/issuance/deploy
   npx hardhat issuance:build-rewards-eligibility-upgrade \
     --network <network> \
     --rewardsManagerImplementation <address> \
     --rewardsEligibilityOracleAddress <address> \
     --outputDir ./governance-proposals
   ```

3. Follow governance workflow ([GovernanceWorkflow.md](./GovernanceWorkflow.md))
4. Create forum post with proposal
5. Collect governance signatures
6. Execute when ready

---

### Verifying Deployment

1. Use appropriate checklist from [VerificationChecklists.md](./VerificationChecklists.md)
2. Verify contract addresses and configuration
3. Check ownership and roles
4. Test view functions
5. Verify block explorer
6. Run verification scripts (when created)
7. Update address book
8. Document results

---

### Integrating REO with RewardsManager

1. Ensure Phase 1-3 complete (RM upgraded, REO deployed and tested)
2. Generate governance transaction (see "Preparing Governance Proposal")
3. Governance reviews and executes
4. Verify integration using [VerificationChecklists.md](./VerificationChecklists.md) Phase 4
5. Begin monitoring period (Phase 5)

---

### Planning IA Deployment (Future)

1. **READ [IADeploymentGuide.md](./IADeploymentGuide.md) FIRST**
2. Understand 3-stage migration is required
3. Plan Stage 1: Deploy with zero impact
4. Plan Stage 2: Integrate at 100% RM
5. Plan Stage 3: Gradual allocation changes
6. Budget 4-8 weeks between Stage 2 and 3
7. Create monitoring plan
8. Identify rollback triggers

⚠️ **Do not skip stages or rush the process**

---

## Questions & Support

### Common Questions

**Q: Can I deploy REO without upgrading RewardsManager first?**
A: No. Phase 1 (RM upgrade) is a prerequisite. RM must have `setRewardsEligibilityOracle()` method.

**Q: Can I skip the testing period (Phase 3)?**
A: Not recommended for mainnet. Testing period (2-4 weeks) validates deployment before production integration.

**Q: Can I enable REO validation immediately after integration?**
A: Not recommended. Phase 5 monitoring period (4-8 weeks) proves oracle reliability before enforcement.

**Q: Why is the IA 3-stage migration required?**
A: Safety. Stage 2 validates integration without economic changes. Stage 3 makes changes gradually with clear rollback.

**Q: Can I deploy IA and REO together?**
A: Technically yes, but REO is prioritized. Current governance tooling supports both in one batch.

**Q: What if something goes wrong after deployment?**
A: Each document includes rollback procedures. Phase-dependent rollback options available.

### Getting Help

**For deployment questions:**

- Review relevant documentation in this directory
- Check [APICorrectness.md](./APICorrectness.md) for method usage
- Check existing tooling in `../governance/` and `../ignition/`

**For governance questions:**

- See [GovernanceWorkflow.md](./GovernanceWorkflow.md)
- Check existing task: `npx hardhat issuance:build-rewards-eligibility-upgrade --help`

**For technical integration:**

- See [APICorrectness.md](./APICorrectness.md)
- Check contract interfaces in `@graphprotocol/interfaces`
- Review integration tests in `../../test/`

---

## Contributing

### Updating Documentation

**When to update:**

- Contract interfaces change
- Deployment procedures change
- New networks added
- Lessons learned from deployment
- Issues discovered or resolved

**How to update:**

- Maintain consistency across documents
- Update related documents together
- Add dates to updated sections
- Preserve Mermaid diagrams (update if architecture changes)
- Keep checklists actionable

**Documentation style:**

- Clear, concise, technical
- Actionable (tell what to do, not just what exists)
- Include examples
- Document both correct and incorrect usage
- Explain _why_ not just _what_

---

## Document Changelog

### 2025-11-19 - Initial Release

**Created:**

- REODeploymentSequence.md - Complete REO deployment guide
- GovernanceWorkflow.md - Three-phase governance pattern
- VerificationChecklists.md - Comprehensive verification checklists
- REOArchitecture.md - Visual diagrams and architecture
- APICorrectness.md - Method signatures and correct usage
- IADeploymentGuide.md - 3-stage IA migration pattern (future)
- README.md (this file)

**Source:**

- Extracted and adapted from earlier deployment work
- Focused on REO immediate deployment needs
- Preserved IA patterns for future use
- Integrated with existing Ignition and governance tooling

---

## Additional Resources

**Deployment Tools:**

- Hardhat Ignition: <https://hardhat.org/ignition>
- Gnosis Safe: <https://app.safe.global/>
- Block Explorers: Arbiscan (Arbitrum One, Arbitrum Sepolia)

**Protocol Documentation:**

- Graph Protocol Docs: <https://thegraph.com/docs/>
- GIP-0079: [Rewards Eligibility Oracle proposal]

**Development:**

- Hardhat: <https://hardhat.org/>
- Ethers.js: <https://docs.ethers.org/>
- OpenZeppelin: <https://docs.openzeppelin.com/>

---

**Next Steps:**

1. **Review REO deployment sequence** ([REODeploymentSequence.md](./REODeploymentSequence.md))
2. **Identify governance addresses** for your network
3. **Set up oracle infrastructure** for REO operations
4. **Validate configuration parameters**
5. **Begin Phase 1** when ready (RM upgrade)

---

**Remember:** Safety first. Follow the phased approach. Use the checklists. Verify at each step.
