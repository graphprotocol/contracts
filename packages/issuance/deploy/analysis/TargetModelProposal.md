# Issuance Deployment Target Model Proposal

**Goal:** Define a concrete, non-cyclic target model for Issuance deployments that:

- Keeps `packages/issuance` **component-only** (no cross-package wiring).
- Moves all **governance-sensitive state transitions** into an orchestration package.
- Aligns with the legacy Prepare / Execute / Verify workflow and 3-stage migration.
- Fits Arbitrum + testnet focus first, with a path to mainnet.

---

## 1. Component Targets (in `packages/issuance`)

**Principle:** Ignition modules in `packages/issuance/deploy/ignition/modules` deploy and initialize Issuance contracts, but do **not** directly modify RewardsManager or GraphToken production state.

### 1.1 Issuance Allocator Component Target: `issuance-allocator`

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
  - Internal configuration to make IA self-consistent.
- **Not allowed here:**
  - `RewardsManager.setIssuanceAllocator(...)`.
  - `GraphToken.addMinter(IssuanceAllocator)`.

### 1.2 Rewards Eligibility Oracle Component Target: `rewards-eligibility-oracle`

- Implemented by: `deploy/ignition/modules/RewardsEligibilityOracle.ts`.
- Outputs:
  - `RewardsEligibilityOracle` proxy/impl/admin.
- Parameters:
  - `eligibilityPeriod`.
  - `oracleUpdateTimeout`.
  - `eligibilityValidationEnabled` (typically `false` initially).
- **Not allowed here:**
  - Direct wiring into RewardsManager (e.g. `setRewardsEligibilityOracle`).

### 1.3 Direct Allocation Component Targets: `direct-allocation-<program>`

- Implemented by: `deploy/ignition/modules/DirectAllocation.ts` (possibly invoked multiple times).
- Outputs:
  - `DirectAllocation` proxy/impl/admin for each program/target.
- Parameters:
  - Target address / label / metadata per allocation program.
- **Not allowed here:**
  - Calls that change IA allocations.

### 1.4 Zero-Impact Stage for Issuance Allocator (Stage 1)

- Within Issuance component modules, we **can** optionally configure IA so that:
  - If wired in, it would replicate current RewardsManager behavior (100% to existing destination).
- This encodes **Stage 1 0 Deploy with Zero Impact**:
  - IA exists and is testable.
  - No wiring into RewardsManager yet.
  - No economic change.

---

## 2. Active / Integration Targets (Orchestration Package)

**Principle:** All state transitions that affect live protocol behavior live in a separate orchestration/governance package (e.g. `packages/deploy` or a new `packages/issuance-orchestration`). That package imports Issuance Ignition modules, but Issuance never depends back on it.

### 2.1 Oracle Integration Target: `rewards-eligibility-oracle-active`

- Goal: Integrate `RewardsEligibilityOracle` with RewardsManager.
- Governance transactions (Safe batch):
  - `RewardsManager.setRewardsEligibilityOracle(RewardsEligibilityOracle)`.
  - Any role grants required for oracle operation (e.g. `ORACLE_ROLE`).
- Assertions (GovernanceAssertions or TS checks):
  - `rewardsManager.rewardsEligibilityOracle() == RewardsEligibilityOracle`.
  - Required roles/permissions set.

### 2.2 Issuance Allocator Activation Target: `issuance-allocator-active`

- Goal: Make IA the live issuance source **without changing distribution**.
- Governance transactions:
  - `RewardsManager.setIssuanceAllocator(IssuanceAllocator)`.
  - `GraphToken.addMinter(IssuanceAllocator)` (or equivalent mint authority grant).
- Assertions:
  - `rewardsManager.issuanceAllocator() == IssuanceAllocator`.
  - `graphToken.isMinter(IssuanceAllocator) == true`.
- Corresponds to **Stage 2 0 Activate with No Distribution Change**.

### 2.3 Allocation Migration Targets: `issuance-allocator-allocation-stage<N>`

- Goal: Encode gradual allocation adjustments as discrete, testable states.
- Example stages:
  - `stage0`: 100% to legacy path (baseline).
  - `stage1`: 99% / 1%.
  - `stage2`: 95% / 5%.
- For each stage:
  - Governance TXs:
    - `IssuanceAllocator.setTargetAllocation(DirectAllocation_X, bp)` etc.
  - Assertions:
    - Sum of allocations = 100%.
    - Each target's allocation matches configuration.
- Corresponds to **Stage 3 0 Gradual Allocation Adjustments**.

### 2.4 Optional Oracle Rollout Stages: `rewards-eligibility-oracle-rollout-stage<N>`

- If desired, staged rollout for REO:
  - Stage A: integrated but `eligibilityValidationEnabled = false`.
  - Stage B: flip to `true` after monitoring/test period.
- Each stage wraps:
  - One Safe batch.
  - One assertion target.

---

## 3. Sequencing on Arbitrum & Testnets

For Arbitrum Sepolia / testnets:

1. **Component deploys (Issuance package):**
   - Run Ignition deployment for `issuance-allocator`, `rewards-eligibility-oracle`, and needed `direct-allocation-*` targets.
2. **Prepare governance (orchestration package):**
   - Generate Safe TX batches for:
     - `rewards-eligibility-oracle-active`.
     - `issuance-allocator-active`.
     - One or more `issuance-allocator-allocation-stage<N>`.
3. **Fork-based tests:**
   - Fork Arbitrum Sepolia / One.
   - Deploy components via Ignition.
   - Impersonate governance; replay Safe batches in order.
   - Call GovernanceAssertions-style helpers; they revert until correct state is reached.

This mirrors the legacy Prepare / Execute / Verify workflow and aligns with the preference for explicit governance transactions exercised in tests.

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

