# Legacy Code Audit

> **ARCHIVED:** Historical analysis document. See [../../RemainingWork.md](../../RemainingWork.md) for current status.


**Created:** 2025-11-19
**Purpose:** Document what exists in `legacy/packages/` and recommendations for what to keep/discard

---

## Overview

The `legacy/packages/` directory contains **71 files** from the earlier issuance deployment work, organized into two package structures:

1. **`packages/deploy/`** - Orchestration package for "Active" targets (governance integration)
2. **`packages/issuance/deploy/`** - Component deployment package

**Total size:** 431KB

---

## Directory Structure

```
legacy/packages/
├── deploy/                           # Orchestration package (20 files)
│   ├── contracts/
│   │   └── IssuanceStateVerifier.sol        # ✅ VALUABLE - GovernanceAssertions helper
│   ├── ignition/modules/issuance/
│   │   ├── IssuanceAllocatorActive.ts       # ✅ REFERENCE - "Active" target pattern
│   │   ├── IssuanceAllocatorMinter.ts       # ✅ REFERENCE - Minter grant pattern
│   │   ├── IssuanceAllocatorTargetAllocated.ts  # ✅ REFERENCE - Allocation pattern
│   │   ├── PilotAllocationActive.ts         # ✅ REFERENCE - Pilot allocation pattern
│   │   ├── ServiceQualityOracleActive.ts    # ✅ REFERENCE - Oracle integration pattern
│   │   └── _refs/                           # Contract references for "Active" modules
│   ├── scripts/
│   │   ├── deployAll.js                     # Reference - orchestration script
│   │   └── verify.ts                        # ✅ REFERENCE - verification pattern
│   └── test/
│       ├── issuance-active-smoke.test.ts    # ✅ VALUABLE - smoke test pattern
│       └── issuance-active.test.ts          # ✅ VALUABLE - integration test pattern
│
└── issuance/deploy/                  # Component package (51 files)
    ├── contracts/
    │   ├── IssuanceStateVerifier.sol        # ✅ VALUABLE - duplicate of above
    │   └── mocks/
    │       ├── MockGraphToken.sol           # ✅ VALUABLE - test mocks
    │       └── MockRewardsManager.sol       # ✅ VALUABLE - test mocks
    ├── ignition/
    │   ├── configs/                         # ❌ DISCARD - network-specific (not Arbitrum-only)
    │   │   ├── issuance.arbitrumOne.json5   # ⚠️ REFERENCE ONLY - outdated addresses
    │   │   ├── issuance.arbitrumSepolia.json5  # ⚠️ REFERENCE ONLY - outdated addresses
    │   │   ├── issuance.fork.json5
    │   │   ├── issuance.hardhat.json5
    │   │   ├── issuance.localhost.json5
    │   │   ├── issuance.mainnet.json5       # ❌ DISCARD - not relevant
    │   │   └── issuance.sepolia.json5       # ❌ DISCARD - not relevant
    │   ├── modules/
    │   │   ├── contracts/                   # ✅ REFERENCE - module patterns
    │   │   │   ├── DirectAllocationImplementation.ts
    │   │   │   ├── GovernanceCheckpoint.ts  # ✅ VALUABLE - governance checkpoint pattern
    │   │   │   ├── GraphProxyAdmin2.ts      # ⚠️ REFERENCE - shared admin pattern (optional)
    │   │   │   ├── IssuanceAllocator.ts
    │   │   │   └── ServiceQualityOracle.ts
    │   │   └── targets/                     # ✅ REFERENCE - target patterns
    │   │       ├── BasicIssuanceInfrastructure.ts  # Component deployment
    │   │       ├── PilotAllocation.ts       # Pilot allocation deployment
    │   │       └── ReplicatedAllocation.ts  # ✅ VALUABLE - replication pattern
    │   └── parameters/                      # ❌ DISCARD - superseded by configs
    │       ├── arbitrumOne.json5
    │       ├── arbitrumSepolia.json5
    │       ├── hardhat.json5
    │       ├── local.json5
    │       ├── mainnet.json5
    │       └── testnet.json5
    ├── lib/                                 # ❌ DISCARD - compiled JS (generated)
    │   ├── ignition/modules/               # Old compiled modules
    │   └── src/                            # Old compiled sources
    ├── src/                                 # ✅ REFERENCE - utility libraries
    │   ├── address-book.ts                  # ✅ VALUABLE - pending impl tracking pattern
    │   ├── contracts.ts                     # Reference - contract loading
    │   └── index.ts
    ├── scripts/                             # ✅ REFERENCE - deployment scripts
    │   ├── README.md                        # Removed (duplicate)
    │   ├── address-book.js                  # ✅ REFERENCE - address book management
    │   ├── deploy-governance-upgrade.js     # ✅ VALUABLE - governance upgrade pattern
    │   ├── deploy-upgrade-prep.js           # ✅ VALUABLE - upgrade prep pattern
    │   ├── deploy.ts                        # Reference - deploy orchestration
    │   └── update-address-book.js           # ✅ REFERENCE - address book sync
    ├── test/                                # ✅ REFERENCE - test patterns
    │   ├── deployment.test.js               # Basic deployment test
    │   ├── issuance-state-verifier.test.ts  # ✅ VALUABLE - verifier test
    │   └── service-quality-oracle-deploy.test.ts  # Reference - component test
    ├── test-governance-workflow.ts          # ✅ VALUABLE - fork-based governance test
    ├── hardhat.config.ts                    # Reference - Hardhat config
    ├── package.json                         # Reference - dependencies
    └── tsconfig.json                        # Reference - TypeScript config
```

---

## Categorization

### ✅ HIGH VALUE - Should Extract/Adapt

These provide patterns worth implementing in the current codebase:

**Contracts:**

- `IssuanceStateVerifier.sol` - GovernanceAssertions helper contract (novel pattern)
- `MockGraphToken.sol` / `MockRewardsManager.sol` - Test mocks

**Ignition Modules:**

- `GovernanceCheckpoint.ts` - Governance checkpoint detection pattern
- `ReplicatedAllocation.ts` - Gradual migration pattern (100% → adjusted)
- "Active" target modules (IssuanceAllocatorActive, etc.) - Integration patterns

**Scripts:**

- `deploy-governance-upgrade.js` - Governance upgrade workflow
- `deploy-upgrade-prep.js` - Upgrade preparation workflow
- `address-book.ts` - Pending implementation tracking

**Tests:**

- `test-governance-workflow.ts` - Fork-based governance testing
- `issuance-active.test.ts` / `issuance-active-smoke.test.ts` - Integration tests
- `issuance-state-verifier.test.ts` - Verification testing

### ⚠️ REFERENCE ONLY - Keep for Patterns, Not Code

These show how things were done but shouldn't be copied verbatim:

**Ignition Modules:**

- Component deployment modules (show structure but use old contract names)
- Target modules (show orchestration patterns)

**Configs:**

- `issuance.arbitrumOne.json5` / `issuance.arbitrumSepolia.json5` - Show config shape but addresses are outdated

**Scripts:**

- `deployAll.js` - Shows orchestration flow
- `verify.ts` - Shows verification approach

### ❌ DISCARD - Not Needed

These can be safely deleted:

**Compiled Code:**

- Entire `lib/` directory - Generated JavaScript, not source

**Non-Arbitrum Configs:**

- `issuance.mainnet.json5` - Not relevant (Arbitrum-only deployment)
- `issuance.sepolia.json5` - Not relevant (Arbitrum-only deployment)

**Duplicate Parameters:**

- `ignition/parameters/` directory - Superseded by `configs/`

**Build Artifacts:**

- `.prettierignore` - Not needed for legacy reference
- `.markdownlint.json` - Not needed for legacy reference
- `.solhint.json` - Not needed for legacy reference

---

## Recommendations

### Phase 1: Immediate Actions

**Delete low-value files:**

```bash
# Remove compiled code
rm -rf legacy/packages/issuance/deploy/lib/

# Remove non-Arbitrum configs
rm legacy/packages/issuance/deploy/ignition/configs/issuance.mainnet.json5
rm legacy/packages/issuance/deploy/ignition/configs/issuance.sepolia.json5

# Remove duplicate parameters directory
rm -rf legacy/packages/issuance/deploy/ignition/parameters/

# Remove config files
rm legacy/packages/*/.*
```

**Result:** Reduce from 71 files to ~45 files (~300KB)

### Phase 2: Extract High-Value Patterns

**Create examples directory:**

```
legacy/examples/
├── contracts/
│   ├── IssuanceStateVerifier.sol           # GovernanceAssertions pattern
│   └── mocks/                              # Test mocks
├── ignition-modules/
│   ├── ActiveTargets.md                    # Explain "Active" target pattern
│   ├── IssuanceAllocatorActive.ts          # Example implementation
│   └── GovernanceCheckpoint.ts             # Checkpoint pattern
├── scripts/
│   ├── governance-upgrade-workflow.md      # Explain the pattern
│   ├── deploy-governance-upgrade.js        # Example implementation
│   └── address-book.ts                     # Pending impl tracking
└── tests/
    ├── fork-based-testing.md               # Explain the pattern
    ├── test-governance-workflow.ts         # Example implementation
    └── issuance-active.test.ts             # Integration test example
```

### Phase 3: Archive or Delete Remaining

**Option A: Archive for reference**

- Keep `legacy/packages/` as-is for historical reference
- Add `legacy/packages/README.md` explaining it's archived

**Option B: Delete after extraction**

- Once patterns are extracted to `legacy/examples/`
- Delete entire `legacy/packages/` directory
- Keeps legacy/ focused on analysis docs only

---

## File Count Summary

| Category                      | Files  | Action                               |
| ----------------------------- | ------ | ------------------------------------ |
| High-value code               | ~15    | Extract patterns to examples/        |
| Reference patterns            | ~20    | Keep or extract as examples          |
| Configs (reference)           | ~7     | Keep Arbitrum, delete others         |
| Discard (compiled/duplicates) | ~29    | Delete immediately                   |
| **Total**                     | **71** | **Reduce to ~25-30 reference files** |

---

## Current State vs. Target State

**Current:**

```
legacy/
├── [9 analysis markdown files]
└── packages/ [71 files, 431KB]
```

**Target (Option A - Archive):**

```
legacy/
├── [9 analysis markdown files]
├── packages/ [~30 reference files, ~200KB]
└── packages/README.md [explains archive purpose]
```

**Target (Option B - Extract then Delete):**

```
legacy/
├── [9 analysis markdown files]
└── examples/
    ├── contracts/ [2-3 example files]
    ├── ignition-modules/ [3-4 example files]
    ├── scripts/ [3-4 example files]
    └── tests/ [3-4 example files]
```

---

## Decision Points

**For User to Decide:**

1. **Keep full packages/ directory?**
   - **YES** → Keep as historical reference (Phase 1 cleanup only)
   - **NO** → Extract patterns to examples/, then delete (Phases 1-3)

2. **When to do extraction?**
   - **Now** → Part of current Phase 1 cleanup
   - **Later** → When actually implementing Phase 2 (before testnet)
   - **Never** → Just reference the files directly when needed

3. **Archive location?**
   - Current location: `legacy/packages/`
   - Alternative: `legacy/code-examples/`
   - Alternative: Delete after analysis docs are sufficient

---

## Recommended Next Steps

**Immediate (now):**

1. Run Phase 1 cleanup (delete ~29 low-value files)
2. Add `legacy/packages/README.md` explaining the directory
3. Update `legacy/Analysis.md` to reference the code examples

**Before implementing convergence:**

1. Extract specific patterns as needed into working codebase
2. Reference these files for implementation guidance
3. Delete `legacy/packages/` once patterns are integrated

**Long term:**

1. Once convergence is complete, decide if legacy/ should be:
   - Archived to `docs/archive/`
   - Kept as reference documentation
   - Deleted (documented elsewhere)

---

## Notes

- **No immediate action required** - can keep as-is for reference
- **Phase 1 cleanup is optional** - saves ~130KB and removes clutter
- **Extraction can be deferred** - do it when actually implementing patterns
- **Primary value is in analysis docs** - code is secondary reference

---

**Status:** Audit complete. Awaiting user decision on cleanup/extraction approach.
