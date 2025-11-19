# Legacy Issuance Deployment – Alignment & Considerations

This document summarizes what is valuable in the legacy issuance deployment work (now exposed under `/git/graphprotocol/contracts/private`) and how it should inform the current Ignition-based deployment in this repo.

## Legacy design patterns worth preserving

From legacy `doc/README.md` and `Design.md`:

1. **Targets model & separation of concerns**
   - Component-only targets in issuance package (no cross-package wiring):
     - `service-quality-oracle` – deploy SQO proxy+impl, initialize.
     - `issuance-allocator` – deploy IA proxy+impl, initialize.
   - Integration ("Active") targets live in a separate orchestration package:
     - `service-quality-oracle-active`: `RewardsManager.setServiceQualityOracle(SQO)`.
     - `issuance-allocator-active`: `RewardsManager.setIssuanceAllocator(IA)`.
     - `issuance-allocator-minter`: `GraphToken.addMinter(IA)`.
     - `issuance-allocator-reallocation`: configure IA allocations.
   - **Key idea**: component deploys are idempotent and self-contained; any state transitions that require governance live elsewhere.

2. **Three-phase governance workflow**
   - Phase 1 – **Prepare (permissionless)**: deploy new impls, proxies, helpers; mark them as `pendingImplementation` in address book.
   - Phase 2 – **Execute (governance)**: Safe batch executes upgrades and configuration calls.
   - Phase 3 – **Verify/Sync**: small assertion modules/scripts revert until governance has actually run; then address book flips pending→active.
   - This matches the preference to keep governance flows explicit, and to have tests replay the same transactions on a fork.

3. **Assertions helper & address book**
   - Stateless helper (TS or Solidity) with checks like:
     - `assertServiceQualityOracleSet(rewardsManager, expectedSQO)`.
     - `assertIssuanceAllocatorSet(rewardsManager, expectedIA)`.
     - `assertMinter(graphToken, minter)`.
   - Address book explicitly tracks `implementation` vs `pendingImplementation`, and is updated only after governance executes.
   - This dovetails with the current `addresses.json` + Toolshed integration and can be adapted for Arbitrum.

4. **Ignition vs. scripts responsibilities**
   - Ignition handles: deployments, proxies, deterministic idempotent `m.call` operations, dependency graphs, persisted state.
   - Scripts handle: governance proposal generation, Safe batches, verification/go-live checks, and address-book sync.
   - Important: "Active" targets are **not** implemented as Ignition `m.call` to governance-owned contracts; instead, Ignition asserts the correct state, which reverts until the governance batch has been executed.

## 3. Mapping to the current issuance deployment

Current components (from `DEPLOYMENT.md` and Ignition modules):

- `IssuanceAllocator` – proxy + implementation.
- `DirectAllocation` – proxy + implementation (replaces legacy "PilotAllocation" conceptually).
- `RewardsEligibilityOracle` – proxy + implementation (replaces legacy `ServiceQualityOracle`).

Rough mapping:

- Legacy `ServiceQualityOracle` → `RewardsEligibilityOracle`.
- Legacy `PilotAllocation` → `DirectAllocation` (same role: additional allocation targets).
- Legacy `GraphProxyAdmin2` → we currently have per-module `ProxyAdmin` contracts in Ignition; we may still adopt a shared admin pattern if helpful, but that is an implementation choice.

Key alignment points:

1. **Keep issuance deploy package component-only**
   - `packages/issuance/deploy/ignition/modules/*` should focus on deploying and initializing:
     - `IssuanceAllocator` (with GraphToken address parameterized).
     - `DirectAllocation` instances.
     - `RewardsEligibilityOracle` (with eligibility period/timeouts etc.).
   - They should not directly call into RewardsManager or GraphToken governance functions for production flows.

2. **Introduce (or reuse) an orchestration layer for "Active" states**
   - Somewhere else (either a new `packages/deploy` or an existing Horizon/orchestration package), define targets/sequences that:
     - Upgrade RewardsManager implementation where needed.
     - Call `RewardsManager.setIssuanceAllocator(IA)`.
     - Call `RewardsManager.setServiceQualityOracle(Oracle)`.
     - Call `GraphToken.addMinter(IA)`.
     - Adjust allocations via `IssuanceAllocator.setTargetAllocation(...)`.
   - These are the steps that should be modelled as explicit Safe transactions and replayed in fork-based tests.

3. **Make governance checkpoints explicit in tests**
   - Fork-based Arbitrum tests should:
     - Run Ignition deploy modules for new components.
     - Then impersonate governance and execute the exact sequence of transactions described in the legacy `DeploymentGuide.md` (adapted to the new contracts).
     - Then run assertion helpers that mirror the legacy `GovernanceAssertions` pattern.

## 4. Arbitrum & testnet focus

Legacy docs talk about mainnet + Arbitrum + Sepolia, but for this repo we care about:

- **Arbitrum One / Arbitrum Sepolia** as primary; mainnet notes are structural inspiration.
- Legacy `ignition/configs/issuance.arbitrumOne.json5` and `issuance.arbitrumSepolia.json5` show the shape of parameters we’ll likely need:
  - Governance addresses (multisig, council).
  - Existing RewardsManager proxy, GraphToken, existing ProxyAdmin(s).
  - Optional `pendingImplementation` slots for upgrades.

These can guide how we structure `deploy/ignition/configs/issuance.arbitrum*.json5` and any future orchestration configs.

## 5. Suggested reuse / what to look at next

When deciding what to copy from `raw/v1` into `deploy/legacy` proper, the highest-value items are:

- Docs:
  - `doc/Design.md` – for target model and governance phases.
  - `doc/DeploymentGuide.md` – for the multi-phase (RewardsManager → ProxyAdmin → SQO → Allocator) sequencing.
- Ignition:
  - `ignition/modules/contracts/*` – how they modeled component deployments and shared admin.
  - `ignition/modules/targets/*` – patterns for "Active" targets as assertions.
- Scripts/tests:
  - `scripts/deploy-upgrade-prep.js` & `deploy-governance-upgrade.js` – proposal and upgrade flows.
  - `scripts/address-book.js` / `update-address-book.js` – how pending/active implementations are tracked.
  - `test-governance-workflow.ts` – governance workflow encoding that we can adapt into Arbitrum fork tests.

These should be read with the intent to **port patterns**, not code verbatim, to the new contracts and package layout.

## 6. Open design choices (to be decided collaboratively)

1. Where exactly should the new orchestration/governance package live (for "Active" targets)?
2. Do we want a shared `GraphProxyAdmin2`-style admin for issuance proxies on Arbitrum, or keep per-contract ProxyAdmins as in the current Ignition spike?
3. Should the governance assertions live as:
   - A small Solidity helper contract, or
   - Pure TypeScript tests that directly query live state?
4. How strictly do we want to mirror the three-phase legacy workflow vs simplifying for first Arbitrum deployments (while keeping upgrade safety)?
