# Issuance Deployment Docs (Canonical)

This folder contains the canonical documentation for deploying issuance system contracts from the issuance package. It focuses on component deployments only. Cross‑package integrations (governance steps that touch RewardsManager or GraphToken) live in the orchestration package (`packages/deploy`).

## Targets (canonical)

Issuance package (component-only deployments):

- rewards-eligibility-oracle
  - Deploys GraphProxyAdmin2 (if not present), REO implementation + proxy, initializes REO
  - No RewardsManager integration here
- issuance-allocator
  - Deploys GraphProxyAdmin2 (if not present), IssuanceAllocator implementation + proxy, initializes IA
  - No RewardsManager integration here

Orchestration package (cross-package integrations; governance required):

- rewards-eligibility-oracle-active
  - Requires governance to set RewardsManager.setRewardsEligibilityOracle(REO)
  - Verification: RewardsManager.rewardsEligibilityOracle() == REO
- issuance-allocator-active
  - Requires governance to set RewardsManager.setIssuanceAllocator(IA)
  - Verification: RewardsManager.issuanceAllocator() == IA
- issuance-allocator-minter
  - Requires governance to grant GraphToken.addMinter(IA)
  - Verification: GraphToken.isMinter(IA) == true
- issuance-allocator-reallocation
  - Requires governance to configure IssuanceAllocator allocations

Notes:

- "Active" targets are intentionally not implemented in this package; they belong to orchestration where external contracts are referenced.
- Ignition modules are idempotent; governance checkpoints should revert until state transitions are completed, and scripts should handle this gracefully.

## Quick links

- Design: Design.md (canonical)
- Guide: DeploymentGuide.md (API-correct and parameterized)
- Governance: Governance.md (three-phase upgrade, Safe batches, address lookup)

## API correctness highlights

- REO: setQualityChecking(true|false) (not setCheckingActive)
- IA: getTargetIssuancePerBlock(address).selfIssuancePerBlock is used by RewardsManager
- IA: setTargetAllocation(target, allocatorMintingPPM, selfMintingPPM, evenIfDistributionPending)

## Conventions

- All modules/scripts are modern TypeScript (.ts)
- Keep package.json scripts minimal; prefer a single deploy entry point that takes --target and --network
