# Issuance Deployment Target Model (Legacy-Aligned Proposal)

**Goal:** Define a concrete, non-cyclic target model for Issuance that:

- Keeps `packages/issuance` **component-only** (no cross-package wiring).
- Moves all governance-sensitive transitions into a separate orchestration layer.
- Aligns with the legacy Prepare / Execute / Verify workflow and 3‑stage migration.
- Focuses on Arbitrum + testnets first, with a clean path to mainnet.

---

## 1. Component Targets (in `packages/issuance`)

**Principle:** Ignition modules in `packages/issuance/deploy/ignition/modules` deploy and initialize Issuance contracts, but do **not** directly modify RewardsManager or GraphToken production state.

### 1.1 `issuance-allocator`

- Implemented by: `deploy/ignition/modules/IssuanceAllocator.ts`.
- Outputs:
  - `IssuanceAllocator` (TransparentUpgradeableProxy).
  - `IssuanceAllocatorImplementation`.
  - `IssuanceAllocatorProxyAdmin`.
- Parameters (from Ignition configs):
  - `$global.graphTokenAddress`.
  - `IssuanceAllocator.issuancePerBlock`.
- Allowed side effects:
  - Ownership transfers / `acceptOwnership` by governor.
  - Internal configuration needed to make IA self-consistent.
- **Not allowed here:**
  - `RewardsManager.setIssuanceAllocator(...)`.
  - `GraphToken.addMinter(IssuanceAllocator)`.

### 1.2 `rewards-eligibility-oracle`

- Implemented by: `deploy/ignition/modules/RewardsEligibilityOracle.ts`.
- Outputs:
  - `RewardsEligibilityOracle` proxy/impl/admin.
- Parameters:
  - `eligibilityPeriod`.
  - `oracleUpdateTimeout`.
  - `eligibilityValidationEnabled` (typically `false` initially).
- **Not allowed here:**
  - Any direct call into RewardsManager (e.g. `setRewardsEligibilityOracle`).

### 1.3 `direct-allocation-<program>`

- Implemented by: `deploy/ignition/modules/DirectAllocation.ts` (possibly multiple instances).
- Outputs:
  - `DirectAllocation` proxy/impl/admin per program.
- Parameters:
  - Target address / label / metadata per allocation program.
- **Not allowed here:**
  - Calls that change IA allocations.

### 1.4 Zero-Impact Stage for IA (Stage 1)

Within Issuance component modules, IA can be configured such that:

- If wired into RewardsManager, it would initially replicate existing behavior (100% to legacy path).
- IA exists, is testable, but not yet integrated.

This corresponds to **Stage 1 – Deploy with zero impact** from the legacy docs.

---

## 2. Active / Integration Targets (Orchestration Layer)

**Principle:** All state transitions that affect live protocol behavior live in a separate orchestration/governance package (e.g. `packages/deploy` or a new `packages/issuance-orchestration`). That package imports Issuance Ignition modules, but Issuance never depends back on it.

### 2.1 `rewards-eligibility-oracle-active`

- Goal: integrate `RewardsEligibilityOracle` with RewardsManager.
- Governance transactions (Safe batch):
  - `RewardsManager.setRewardsEligibilityOracle(RewardsEligibilityOracle)`.
  - Any role grants required for oracle operation.
- Assertions (GovernanceAssertions or TS checks):
  - `rewardsManager.rewardsEligibilityOracle() == RewardsEligibilityOracle`.
  - Required roles/permissions set.

### 2.2 `issuance-allocator-active`

- Goal: make IA the live issuance source **without changing distribution**.
- Governance transactions:
  - `RewardsManager.setIssuanceAllocator(IssuanceAllocator)`.
  - `GraphToken.addMinter(IssuanceAllocator)` (or equivalent mint authority grant).
- Assertions:
  - `rewardsManager.issuanceAllocator() == IssuanceAllocator`.
  - `graphToken.isMinter(IssuanceAllocator) == true`.

This is **Stage 2 – Activate with no distribution change**.

### 2.3 `issuance-allocator-allocation-stage<N>`

- Goal: encode gradual allocation adjustments as discrete, testable states.
- Example stages:
  - `stage0`: 100% to legacy path (baseline).
  - `stage1`: 99% / 1%.
  - `stage2`: 95% / 5%.
- For each stage:
  - Governance TXs:
    - `IssuanceAllocator.setTargetAllocation(DirectAllocation_X, bp)` etc.
  - Assertions:
    - Sum of allocations = 100%.
    - Each target allocation matches configuration.

This is **Stage 3 – Gradual allocation adjustments**.

### 2.4 Optional `rewards-eligibility-oracle-rollout-stage<N>`

- If staged rollout for REO is desired:
  - Stage A: integrated but `eligibilityValidationEnabled = false`.
  - Stage B: flip to `true` after monitoring/test period.
- Each stage wraps:
  - One Safe batch.
  - One assertion target.

---

## 3. Sequencing on Arbitrum & Testnets

For Arbitrum Sepolia / Arbitrum One forks:

1. **Component deploys (Issuance package):**
   - Run Ignition deployment for `issuance-allocator`, `rewards-eligibility-oracle`, and needed `direct-allocation-*` targets.
2. **Prepare governance (orchestration):**
   - Generate Safe TX batches for:
     - `rewards-eligibility-oracle-active`.
     - `issuance-allocator-active`.
     - One or more `issuance-allocator-allocation-stage<N>`.
3. **Fork-based tests:**
   - Fork Arbitrum; deploy components via Ignition.
   - Impersonate governance; replay Safe batches in order.
   - Call GovernanceAssertions-style helpers; they revert until correct state is reached.

This mirrors the legacy Prepare / Execute / Verify workflow and keeps governance flows explicit and testable.

---

## 4. Non-Cyclic Packaging

- `packages/issuance`:
  - Exposes Ignition modules (`IssuanceAllocatorModule`, `DirectAllocationModule`, `RewardsEligibilityOracleModule`, `GraphIssuanceModule`).
  - No imports from orchestration/governance packages.
- Orchestration/governance package:
  - Imports Issuance Ignition modules as dependencies.
  - Defines active/migration targets and governance scripts.
  - Owns GovernanceAssertions helper and any address-book extensions.

This keeps references clean and one-directional while enabling rich governance workflows and fork-based validation.

