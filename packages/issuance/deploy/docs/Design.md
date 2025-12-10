# Issuance Deployment Design (Canonical)

This document is the canonical design for deploying the issuance system
components on top of an existing Horizon deployment.

It is a deployment-focused restatement of `incoming/issuance/Design.md`.
That file is now treated as an archive/background copy; this one is the
single source of truth for issuance deployment.

---

## Goals

- Clean, target-based, idempotent deployments using Hardhat Ignition
- Separation of concerns:
  - Issuance deployment package (`packages/issuance/deploy`): deploy issuance
    components only (no cross‑package wiring)
  - Horizon deployment package (`packages/horizon`): deploy and upgrade core
    protocol contracts (GraphToken, RewardsManager, GraphProxyAdmin) using the
    shared contracts in `packages/contracts`
  - Orchestration package (`packages/deploy`): perform cross‑package
    integrations and governance wiring (e.g. activating issuance components in
    RewardsManager, managing address books)
- Minimal, parameterized CLI (network/parameters/target)
- Governance checkpoints encoded as assertion calls that revert until the
  governance transaction is executed
- Address book tracks active and pending implementations

---

## Components

- IssuanceAllocator (Upgradeable proxy + implementation, uses GraphToken)
- RewardsEligibilityOracle (Upgradeable proxy + implementation)
- PilotAllocation (Upgradeable proxy + implementation, using DirectAllocation
  implementation contract)
- RewardsManager (Existing upgradeable proxy, new implementation)
- GraphIssuanceProxyAdmin (contract name `GraphIssuanceProxyAdmin`, ProxyAdmin for
  issuance proxies; governance‑owned)
- TransparentUpgradeableProxy (standard OZ proxies per component)
- GraphToken (Existing contract, no action needed, just need module to
  reference)
- GraphProxyAdmin (Existing proxy admin for core contracts, no action needed,
  just need module to reference)

---

## Targets model

- Component targets (in this package):
  - `rewards-eligibility-oracle`
  - `issuance-allocator`
  - `pilot-allocation` (experimental/test allocation target, typically a small
    slice of IssuanceAllocator distribution)
- Integration targets (cross‑package; live in `packages/deploy`):
  - `rewards-eligibility-oracle-active`:
    `RewardsManager.setRewardsEligibilityOracle(REO)`
  - `issuance-allocator-active`:
    `RewardsManager.setIssuanceAllocator(IA)`
  - `issuance-allocator-minter`: `GraphToken.addMinter(IA)`
  - `issuance-allocator-reallocation`: configure IssuanceAllocator allocations
    over time (e.g. transition from replicated allocation to target
    distribution, including `pilot-allocation`)

Notes:

- "Active" targets assert equality (e.g.,
  `RewardsManager.rewardsEligibilityOracle() == REO`). They are intentionally
  not in the issuance package when they depend on external packages.

---

## Configuration state definitions

- Rewards Eligibility Oracle states:
  - **Rewards Eligibility Oracle**: deployed and ready to provide eligibility
    assessments
  - **Rewards Eligibility Oracle Active**: integrated via
    `RewardsManager.setRewardsEligibilityOracle()`
- Issuance Allocator states:
  - **Replicated Allocation**: IssuanceAllocator replicates current issuance
    per block with 100% allocated to RewardsManager
  - **Replicated Allocation Active**: integrated via
    `RewardsManager.setIssuanceAllocator()` with 100% allocation to
    RewardsManager
  - **Issuance Allocator Active**: RewardsManager uses IssuanceAllocator for
    issuance distribution
  - **Issuance Allocator Minter**: IssuanceAllocator has GraphToken minting
    authority via `GraphToken.addMinter(IA)`
  - **Pilot Allocation Active**: e.g. 99% to RewardsManager and 1% to a
    `PilotAllocation` (for testing only; not proposed for production)

Governance workflows, detailed phase sequencing, and transaction-level
guidance live in `packages/deploy/docs` and in the background docs in this
directory. This file focuses on what must be **true** in the target
deployment state, not on the exact sequence of commands.
