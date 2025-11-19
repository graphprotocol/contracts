# Pattern Conflicts & Design Decisions

**Date:** 2025-11-19
**Purpose:** Document where earlier deployment work and current Ignition spike use different approaches, requiring design decisions

---

## Summary

There are no fundamental conflicts that prevent integration. However, there are **architectural differences** where we must choose one approach or reconcile both. These are design decisions, not blockers.

---

## Design Decision 1: Proxy Administration Pattern

### Earlier Approach: GraphProxyAdmin2

**Pattern:**

- Creates new ProxyAdmin contract: `GraphProxyAdmin2`
- Issuance proxies owned by GraphProxyAdmin2
- Existing protocol proxies owned by GraphProxyAdmin (legacy)
- Both ProxyAdmins owned by governance multi-sig

**Rationale:**

- Isolates issuance system governance
- Independent upgrade paths
- Clear ownership boundaries

**Code:**

```solidity
// Deploy new ProxyAdmin
GraphProxyAdmin2 proxyAdmin2 = new GraphProxyAdmin2();
proxyAdmin2.transferOwnership(governance);

// Use for issuance proxies
TransparentUpgradeableProxy iaProxy = new TransparentUpgradeableProxy(
    implementation,
    address(proxyAdmin2),
    initData
);
```

### Current Approach: Standard TransparentUpgradeableProxy

**Pattern:**

- Uses OpenZeppelin's standard TransparentUpgradeableProxy pattern
- ProxyAdmin created per deployment or shared pattern (standard Ignition)
- No explicit GraphProxyAdmin2 contract

**Rationale:**

- Simpler deployment
- Standard OpenZeppelin pattern
- Ignition handles ProxyAdmin automatically

**Code:**

```typescript
// In Ignition module
const { proxy } = await deployWithTransparentUpgradeableProxy(
  m,
  'IssuanceAllocator',
  implementation,
  proxyAdmin,
  governor,
  initData,
)
```

### Decision Required

**Options:**

1. **Adopt GraphProxyAdmin2 pattern** (earlier approach):
   - ✅ Clear separation of issuance from legacy protocol
   - ✅ Independent governance control
   - ❌ Additional deployment step
   - ❌ More complex if not needed

2. **Keep standard pattern** (current approach):
   - ✅ Simpler deployment
   - ✅ Standard Ignition pattern
   - ✅ Works well with Horizon alignment
   - ❌ Less isolation from legacy protocol

3. **Hybrid: Use standard pattern but document governance separation**:
   - ✅ Simple implementation
   - ✅ Can still have governance control separation
   - ✅ ProxyAdmin ownership to governance multi-sig achieves same goal

**Recommendation:** **Option 3 - Keep standard pattern**

**Reasoning:**

- Current approach already transfers ProxyAdmin ownership to governor
- Functional separation achieved without additional contract
- Simpler for deployment and maintenance
- Can always add GraphProxyAdmin2 later if needed
- Horizon uses standard pattern - consistency is valuable

**Action:** Document ProxyAdmin governance in deployment guide, no code changes needed.

---

## Design Decision 2: Module Granularity

### Earlier Approach: Component vs Integration Targets

**Pattern:**

- **Component targets** (in issuance package):
  - `service-quality-oracle` - Deploy SQO contracts only
  - `issuance-allocator` - Deploy IA contracts only
  - Each component deployable independently

- **Integration targets** (in orchestration package):
  - `service-quality-oracle-active` - Integrate SQO with RewardsManager
  - `issuance-allocator-active` - Integrate IA with RewardsManager
  - `issuance-allocator-minter` - Grant IA minting authority
  - Each integration requires governance execution

**Structure:**

```text
packages/
  issuance/
    deploy/
      ignition/modules/
        service-quality-oracle.ts      # Component
        issuance-allocator.ts           # Component
  deploy/  (orchestration package)
    ignition/modules/
      service-quality-oracle-active.ts  # Integration
      issuance-allocator-active.ts      # Integration
      issuance-allocator-minter.ts      # Integration
```

**Rationale:**

- Clear separation: deployment vs governance-required activation
- Package boundaries match ownership
- Can deploy components without governance
- Integration targets verify governance has executed

### Current Approach: Single Orchestrated Deployment

**Pattern:**

- Single `deploy.ts` module that:
  - Deploys all three contracts with proxies
  - Transfers ProxyAdmin ownership
  - Calls acceptOwnership on each
  - Returns all references

**Structure:**

```text
packages/
  issuance/
    deploy/
      ignition/modules/
        IssuanceAllocator.ts           # Individual module
        RewardsEligibilityOracle.ts    # Individual module
        DirectAllocation.ts            # Individual module
        deploy.ts                       # Orchestrator
```

**Rationale:**

- Simpler for initial deployment
- All contracts deployed atomically
- Ignition handles dependencies
- Single entry point

### Decision Required

**Options:**

1. **Adopt component/integration separation** (earlier approach):
   - ✅ Explicit deployment vs activation separation
   - ✅ Can deploy without governance coordination
   - ✅ Clear governance checkpoints
   - ❌ More complex module structure
   - ❌ Requires orchestration package (conflicts with user preference)

2. **Keep single orchestrator** (current approach):
   - ✅ Simple for initial deployment
   - ✅ Stays in issuance/deploy (user preference)
   - ✅ Clear atomic deployment
   - ❌ Less granular control
   - ❌ Deployment and activation less separated

3. **Hybrid: Multiple modules in issuance/deploy with clear deployment vs governance distinction**:
   - ✅ Granular control when needed
   - ✅ Stays in issuance/deploy
   - ✅ Can still use orchestrator for common case
   - ✅ Clear separation of deployment vs governance

**Recommendation:** **Option 3 - Multiple modules with orchestrator**

**Reasoning:**

- Keep current deploy.ts as default orchestrator
- Individual modules (IssuanceAllocator.ts, etc.) provide granularity when needed
- Add governance-specific modules later (e.g., `activate-issuance.ts`)
- Stays in issuance/deploy package (user preference)
- Best of both worlds: simple default, granular when needed

**Action:**

- Keep current structure
- Add governance activation modules when implementing governance workflow
- Document when to use orchestrator vs individual modules

---

## Design Decision 3: Pending Implementation Tracking

### Earlier Approach: Address Book with Pending State

**Pattern:**

- Address book tracks both active and pending implementations
- `setPendingImplementation()` records deployed-but-not-active implementation
- `activatePendingImplementation()` moves pending → active after governance
- Clear audit trail of upgrade workflow

**Format:**

```json
{
  "IssuanceAllocator": {
    "address": "0x1111...",
    "proxy": true,
    "implementation": {
      "address": "0x2222...",
      "version": "1.0.0"
    },
    "pendingImplementation": {
      "address": "0x3333...",
      "version": "1.1.0",
      "deployedAt": "2024-11-15T10:30:00Z",
      "deployedBy": "0x4444...",
      "readyForUpgrade": true,
      "governanceProposal": "https://..."
    }
  }
}
```

**Workflow:**

1. Deploy new implementation → record as pending
2. Generate governance proposal → link in pending
3. Governance executes upgrade
4. Sync script moves pending → active

### Current Approach: Standard Ignition Deployment Tracking

**Pattern:**

- Ignition tracks deployments in `deployed_addresses.json`
- `sync-addresses.ts` script updates main `addresses.json`
- Address book shows current active state only

**Format:**

```json
{
  "42161": {
    "IssuanceAllocator": {
      "address": "0x1111...",
      "proxy": "transparent",
      "proxyAdmin": "0x2222...",
      "implementation": "0x3333..."
    }
  }
}
```

**Workflow:**

1. Deploy via Ignition → creates deployment artifacts
2. Run sync script → updates addresses.json
3. Address book reflects deployed state

### Decision Required

**Options:**

1. **Adopt pending implementation tracking** (earlier approach):
   - ✅ Clear governance workflow state
   - ✅ Audit trail of upgrades
   - ✅ Supports multi-step governance
   - ❌ More complex address book
   - ❌ Additional scripting needed

2. **Keep standard Ignition tracking** (current approach):
   - ✅ Simple and standard
   - ✅ Ignition handles state
   - ✅ Works well for initial deployment
   - ❌ No pending state tracking
   - ❌ Harder to coordinate upgrades

3. **Hybrid: Extend address book format to support pending when needed**:
   - ✅ Simple for initial deployment (no pending)
   - ✅ Can add pending for upgrades
   - ✅ Optional complexity
   - ✅ Clear workflow for both scenarios

**Recommendation:** **Option 3 - Extend address book for upgrades**

**Reasoning:**

- Initial deployment doesn't need pending state
- Upgrades benefit from pending tracking
- Can add `pendingImplementation` field when doing first upgrade
- Update sync-addresses.ts to handle pending when present
- Document upgrade workflow using pending state

**Action:**

- Keep current format for initial deployment
- Document pending implementation pattern for upgrades
- Update sync-addresses.ts to support optional pending field
- Add pending workflow to governance documentation

---

## Design Decision 4: Deployment Sequencing

### Earlier Approach: Four-Phase Deployment

**Pattern:**

- **Phase 1:** RewardsManager Upgrade (prerequisite)
- **Phase 2:** GraphProxyAdmin2 Deployment
- **Phase 3:** ServiceQualityOracle Deployment (8 stages)
- **Phase 4:** IssuanceAllocator Deployment (3 stages)

**Explicit dependencies:**

```
RewardsManager V6 ← SQO, IA (need integration methods)
GraphProxyAdmin2 ← SQO, IA (manage proxies)
SQO → RewardsManager (integration)
IA → RewardsManager (integration)
IA → GraphToken (minting authority)
```

**Granular stages:**

- Deploy contracts
- Configure roles
- Configure parameters
- Testing period (2-4 weeks)
- Governance integration
- Monitoring period (4-8 weeks)

### Current Approach: Single Deployment

**Pattern:**

- Deploy all three contracts together
- No explicit phases or stages documented
- Governance integration via Safe TX builder (RewardsManager only)

**Dependencies:**

- Implicit in code (constructor args)
- No documentation of sequencing requirements

### Decision Required

**Options:**

1. **Adopt four-phase deployment** (earlier approach):
   - ✅ Explicit risk mitigation
   - ✅ Testing periods defined
   - ✅ Clear dependencies
   - ❌ More complex documentation
   - ❌ Longer deployment timeline

2. **Keep single deployment** (current approach):
   - ✅ Simple and fast
   - ✅ Good for testnets
   - ❌ Higher risk for mainnet
   - ❌ No testing periods

3. **Hybrid: Document phased rollout for production, keep simple deployment for testing**:
   - ✅ Fast iteration on testnets
   - ✅ Safe mainnet deployment
   - ✅ Clear distinction between environments

**Recommendation:** **Option 3 - Environment-specific strategies**

**Reasoning:**

- Testnets: Use simple deployment for iteration speed
- Mainnet: Use phased rollout for safety
- Document both approaches
- Make deployment strategy configurable

**Action:**

- Document phased rollout strategy for mainnet
- Keep simple deployment for development/testnets
- Add deployment strategy selection to deployment guide

---

## Design Decision 5: Gradual Migration Strategy

### Earlier Approach: 3-Stage IssuanceAllocator Migration

**Stage 4.1 - Deploy & Configure:**

- Deploy IA with zero production impact
- Configure to exactly replicate RewardsManager (100% allocation)
- Comprehensive validation
- **State:** Deployed but not active

**Stage 4.2 - Migrate to Allocator Control:**

- Governance integrates IA with RewardsManager
- Grant minting authority
- **State:** Live, but 100% to RM (no distribution change)

**Stage 4.3 - Allocation Changes:**

- Deploy DirectAllocation targets
- Gradually adjust allocations (99%/1%, then 95%/5%, etc.)
- **State:** New distribution model active

**Key insight:** Separate deployment, activation, and allocation changes

### Current Approach: No Documented Migration Strategy

**Pattern:**

- Deploy contracts
- Integrate with RewardsManager (via Safe TX builder)
- No explicit strategy for allocation changes

### Decision Required

**Options:**

1. **Adopt 3-stage migration** (earlier approach):
   - ✅ Zero-risk initial deployment
   - ✅ Validate before changing distribution
   - ✅ Clear rollback points
   - ✅ Essential for mainnet safety

2. **Wing it**:
   - ❌ High risk
   - ❌ No rollback plan
   - ❌ **NOT RECOMMENDED**

**Recommendation:** **Option 1 - MUST adopt 3-stage migration**

**Reasoning:**

- This is not a design decision; it's a safety requirement
- Mainnet deployment without this is too risky
- Replicating existing distribution (100% to RM) validates integration without changing economics
- Gradual allocation changes allow monitoring and rollback

**Action:**

- **CRITICAL:** Document 3-stage migration in deployment guide
- Implement verification that Stage 4.2 truly replicates existing distribution
- Create governance TX builders for each stage
- Add monitoring requirements for each stage

**Priority:** CRITICAL for mainnet

---

## Non-Conflicts (Just Missing Features)

The following are not conflicts but rather features in earlier work that are missing in current spike:

### Not Conflicts

1. **GovernanceAssertions helper contract** - Missing, should add
2. **Verification scripts** - Missing, should add
3. **Comprehensive checklists** - Missing, should add
4. **Mermaid diagrams** - Missing, should add
5. **Testing periods** - Missing, should document
6. **Operational procedures** - Missing, should document

These are **additive** - they don't conflict with current implementation, they enhance it.

---

## Summary of Decisions

| Decision                   | Recommendation                                                | Priority     | Action                            |
| -------------------------- | ------------------------------------------------------------- | ------------ | --------------------------------- |
| **Proxy Administration**   | Keep standard pattern, document governance                    | LOW          | Document only                     |
| **Module Granularity**     | Keep orchestrator, add governance modules later               | MEDIUM       | Add governance modules in Phase 2 |
| **Pending Implementation** | Extend address book for upgrades                              | HIGH         | Update sync script & docs         |
| **Deployment Sequencing**  | Environment-specific (simple for testnet, phased for mainnet) | HIGH         | Document both strategies          |
| **Gradual Migration**      | **MUST adopt 3-stage migration**                              | **CRITICAL** | Document & implement verification |

---

## Next Steps

1. **Review these decisions** with user
2. **Confirm recommendations** or adjust based on user preference
3. **Prioritize implementation** based on criticality
4. **Proceed with Phase 1** (documentation integration) incorporating these decisions

---

## Notes

- Most "conflicts" are actually design choices, not fundamental incompatibilities
- **Gradual migration strategy is the only CRITICAL decision** - must adopt for mainnet safety
- Current implementation is excellent; these decisions enhance it
- User's preference to keep everything in issuance/deploy is compatible with all recommendations
