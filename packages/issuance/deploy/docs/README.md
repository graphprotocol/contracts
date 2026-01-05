# Issuance Deployment Documentation

Documentation for deploying Graph Issuance contracts.

## Primary Guide

See **[HardhatDeployGuide.md](./HardhatDeployGuide.md)** for complete deployment instructions.

## Available Documentation

### Deployment

- **[HardhatDeployGuide.md](./HardhatDeployGuide.md)** - Complete hardhat-deploy deployment guide
- **[GovernanceWorkflow.md](./GovernanceWorkflow.md)** - Governance transaction workflow
- **[VerificationChecklists.md](./VerificationChecklists.md)** - Deployment verification checklists

### Architecture

- **[Design.md](./Design.md)** - Issuance system design and architecture
- **[REOArchitecture.md](./REOArchitecture.md)** - RewardsEligibilityOracle architecture diagrams

### Component-Specific Guides

- **[REODeploymentSequence.md](./REODeploymentSequence.md)** - RewardsEligibilityOracle deployment sequence
- **[IADeploymentGuide.md](./IADeploymentGuide.md)** - IssuanceAllocator deployment guide
- **[REO-RMRolloutPlan.md](./REO-RMRolloutPlan.md)** - REO + RewardsManager integration plan

## Quick Reference

### Deploy All Contracts

```bash
pnpm hardhat deploy --tags issuance --network <network>
```

### Verify Deployment

Use checklists in [VerificationChecklists.md](./VerificationChecklists.md)

### Generate Governance Transactions

See [GovernanceWorkflow.md](./GovernanceWorkflow.md) for Safe transaction generation

## Documentation Status

| Document                  | Status | Focus                          |
| ------------------------- | ------ | ------------------------------ |
| HardhatDeployGuide.md     | ✅     | Component deployment (PRIMARY) |
| VerificationChecklists.md | ✅     | Deployment validation          |
| GovernanceWorkflow.md     | ✅     | Governance transactions        |
| Design.md                 | ✅     | System architecture            |
| REODeploymentSequence.md  | 📋     | REO-specific deployment        |
| IADeploymentGuide.md      | 📋     | IA-specific deployment         |
| REOArchitecture.md        | 📋     | Visual diagrams                |
| REO-RMRolloutPlan.md      | 📋     | Integration planning           |

Legend: ✅ Core • 📋 Reference

## Note on Scope

This directory documents **component deployment** for the issuance package.

Cross-package orchestration and governance integration documentation belongs in `packages/deploy/`.
