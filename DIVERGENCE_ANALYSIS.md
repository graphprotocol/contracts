# Divergence Analysis: Incoming Design vs Current Implementation

## Summary

The incoming design documents (in `incoming/issuance/`) represent the original plan, but the current implementation has diverged significantly due to incorrect implementation by Claude.

---

## Key Differences

### 1. Contract Name Changes

| Incoming Design            | Current Implementation         | Status     |
| -------------------------- | ------------------------------ | ---------- |
| ServiceQualityOracle (SQO) | RewardsEligibilityOracle (REO) | ✅ Renamed |
| IssuanceAllocator (IA)     | IssuanceAllocator (IA)         | ✅ Same    |
| PilotAllocation            | DirectAllocation               | ✅ Renamed |
| GraphProxyAdmin2           | ???                            | ❌ Missing |

### 2. Package Structure Changes

**Incoming Design Expected:**

```
packages/
├── contracts/
│   └── deploy/          # RewardsManager deployment
├── issuance/
│   └── deploy/          # SQO, IA, PilotAllocation deployment
└── deploy/              # Cross-package orchestration
```

**Current Reality:**

```
packages/
├── contracts/           # Legacy contracts (no deploy subdirectory)
│   └── contracts/rewards/RewardsManager.sol
├── horizon/             # New! Not in original design
│   ├── contracts/
│   └── ignition/modules/
│       └── periphery/RewardsManager.ts  # RewardsManager deployment
├── issuance/
│   ├── contracts/eligibility/RewardsEligibilityOracle.sol
│   └── deploy/          # REO, IA, DirectAllocation deployment
└── deploy/              # Cross-package orchestration (WIP)
```

### 3. RewardsManager Ownership

| Aspect                    | Incoming Design             | Current Reality               |
| ------------------------- | --------------------------- | ----------------------------- |
| RewardsManager Source     | `packages/contracts`        | `packages/contracts` (source) |
| RewardsManager Deployment | `packages/contracts/deploy` | `packages/horizon`            |
| Owner Package             | contracts                   | **horizon**                   |

**Why:** Horizon emerged as "next iteration of Graph Protocol" and took ownership of RewardsManager deployment.

### 4. Proxy Administration

| Aspect           | Incoming Design                    | Current Reality                                        |
| ---------------- | ---------------------------------- | ------------------------------------------------------ |
| Legacy Proxies   | GraphProxyAdmin (shared)           | GraphProxyAdmin (in horizon, shared)                   |
| Issuance Proxies | **GraphProxyAdmin2** (shared, NEW) | **Individual ProxyAdmins per contract**                |
| Pattern          | Custom GraphProxyAdmin2            | OZ TransparentUpgradeableProxy auto-creates ProxyAdmin |
| Ownership        | Governance owns GraphProxyAdmin2   | Governance owns each ProxyAdmin                        |

**Current Implementation:**

- `IssuanceAllocatorProxyAdmin` (created by proxy)
- `RewardsEligibilityOracleProxyAdmin` (created by proxy)
- `DirectAllocationProxyAdmin` (created by proxy)

**Status:** MAJOR DIVERGENCE - No shared GraphProxyAdmin2. Using OZ pattern with individual ProxyAdmins instead.

---

## What Happened?

### Timeline (Inferred from Git History)

1. **Original Plan:** ServiceQualityOracle design created in `incoming/`
2. **Contract Rename:** ServiceQualityOracle → RewardsEligibilityOracle
3. **Horizon Emergence:** Horizon package created to own next-gen deployments
4. **RewardsManager Migration:** RewardsManager deployment moved from contracts to horizon
5. **Deploy Package WIP:** Cross-package orchestration started but incomplete

### Why the Divergence?

The incoming design was written **before Horizon package existed**. Key changes:

1. **Horizon became the deployment owner** for core contracts like RewardsManager
2. **Contract naming** evolved (ServiceQualityOracle → RewardsEligibilityOracle)
3. **packages/contracts** remained as source code only, no deployment modules
4. **GraphProxyAdmin2** decision unclear - may use existing GraphProxyAdmin

---

## Current State Assessment

### What Matches the Design

✅ Three-phase governance pattern (Prepare → Execute → Verify)
✅ Pending implementation tracking in address book
✅ Checkpoint modules for verification
✅ Cross-package orchestration in `packages/deploy`
✅ Safe transaction builder for governance
✅ IssuanceAllocator structure

### What Diverged

❌ Contract names (SQO → REO, PilotAllocation → DirectAllocation)
❌ Horizon package not mentioned in design
❌ RewardsManager deployment in horizon, not contracts/deploy
❌ **GraphProxyAdmin2 pattern replaced with individual ProxyAdmins** (OZ pattern)
❌ Package structure different

### What's Incomplete (WIP)

⚠️ 2 tasks commented out in hardhat.config (type issues)
⚠️ 5 failing tests (fork tests, parameter issues)
⚠️ Empty addresses.json (no deployments yet)
⚠️ Some eslint warnings

---

## Recommendations

### Option A: Align with Incoming Design

**Revert to original plan:**

- Rename REO → SQO
- Create GraphProxyAdmin2
- Move RewardsManager deployment back to contracts/deploy
- Realign package structure

**Pros:** Matches original design docs
**Cons:** Major refactor, conflicts with Horizon's role

### Option B: Update Incoming Design to Match Reality

**Accept current architecture:**

- Update incoming docs to use REO instead of SQO
- Document Horizon's role
- Clarify GraphProxyAdmin strategy
- Update package structure diagrams

**Pros:** Minimal code changes, documents reality
**Cons:** Design docs become outdated reference

### Option C: Hybrid Approach

**Keep current names and Horizon, but add missing pieces:**

- Keep REO name (it's deployed)
- Keep Horizon owning RewardsManager
- Add GraphProxyAdmin2 if truly needed for issuance
- Update incoming design docs to reflect Horizon era

**Pros:** Pragmatic, fixes gaps
**Cons:** Still some divergence

---

## Immediate Next Steps

1. **Decide on names:** SQO vs REO (REO is already deployed)
2. **Clarify ProxyAdmin:** Do we need GraphProxyAdmin2 or reuse existing?
3. **Fix WIP issues:**
   - Uncomment and fix tasks in hardhat.config
   - Fix 5 failing tests
   - Clean up eslint warnings
4. **Update documentation:** Either incoming or current to match reality

---

## Questions to Answer

1. **Is RewardsEligibilityOracle the final name?** (appears to be yes based on deployed contracts)
2. **Do we need a separate GraphProxyAdmin2?**
   - Design says yes (shared admin)
   - Current implementation uses individual ProxyAdmins per contract (OZ pattern)
   - **Decision needed:** Refactor to use shared admin or accept current pattern?
3. **Should Horizon own RewardsManager deployment?** (currently does)
4. **Are the incoming docs still the canonical design?** (if so, need major realignment)

## Critical Decision: Proxy Administration Pattern

### Option A: Keep Individual ProxyAdmins (Current)

**Pros:**

- Already implemented
- Standard OZ pattern
- Less governance coordination (each contract independent)

**Cons:**

- Diverges from design
- More ProxyAdmin contracts to manage
- Higher gas for governance (multiple admin txs)

### Option B: Implement Shared GraphProxyAdmin2 (Design)

**Pros:**

- Matches original design
- Single governance interface for all issuance upgrades
- Lower gas for batched upgrades

**Cons:**

- Requires refactoring current ignition modules
- More complex to set up initially
- Need to create/deploy GraphProxyAdmin2 contract

---

## Files to Review

- `incoming/issuance/Design.md` - Original design (uses SQO)
- `packages/issuance/contracts/eligibility/RewardsEligibilityOracle.sol` - Actual contract (uses REO)
- `packages/horizon/ignition/modules/periphery/RewardsManager.ts` - RM deployment (in Horizon, not contracts)
- `packages/deploy/` - Current WIP orchestration
