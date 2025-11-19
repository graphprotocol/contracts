# IssuanceAllocator Deployment Guide (Future Use)

**Status:** FUTURE - Not yet scheduled for deployment
**Priority:** LOWER - REO deployment first
**Last Updated:** 2025-11-19

---

## Overview

This document outlines the deployment strategy for IssuanceAllocator (IA) when it's ready to deploy. The IA is not currently planned for immediate deployment, but this guide preserves the critical patterns from earlier deployment work.

⚠️ **CRITICAL:** The 3-stage gradual migration pattern is **non-negotiable** for mainnet safety.

---

## Critical Pattern: 3-Stage Gradual Migration

### Why This Pattern is Critical

The IssuanceAllocator fundamentally changes how tokens are minted and distributed in the protocol. A direct deployment and activation carries significant risk:
- Could disrupt existing rewards distribution
- Difficult to verify correct operation
- No clear rollback if issues arise
- High impact if something goes wrong

The 3-stage migration pattern **eliminates these risks** by:
1. Deploying without production impact (Stage 1)
2. Activating while replicating existing behavior (Stage 2)
3. Gradually changing distribution with monitoring (Stage 3)

---

## Stage 1: Deploy with Zero Impact

**Purpose:** Deploy IA infrastructure without affecting production

### Actions

1. **Deploy IA Contracts**
   ```bash
   cd packages/issuance/deploy
   npx hardhat ignition deploy ignition/modules/IssuanceAllocator.ts \
     --network arbitrumSepolia \
     --parameters ignition/configs/issuance.arbitrumSepolia.json5 \
     --deployment-id ia-arbitrum-sepolia-001
   ```

2. **Configure to Replicate Existing Distribution**
   ```typescript
   // Set 100% allocation to RewardsManager
   await issuanceAllocator.setTargetAllocation(
     rewardsManagerAddress,
     1_000_000,  // 100% in PPM (parts per million)
     0,          // 0% self-minting
     false       // Don't set if distribution pending
   )
   ```

3. **Set Initial Issuance Rate**
   ```typescript
   // Match current RewardsManager issuance rate
   const currentRate = await rewardsManager.getIssuancePerBlock()
   await issuanceAllocator.setIssuancePerBlock(currentRate)
   ```

### Verification

- [ ] IA deployed and initialized
- [ ] IA owned by governance
- [ ] IA configured with 100% to RewardsManager
- [ ] IA issuance rate matches current RM rate
- [ ] IA **NOT** integrated with RewardsManager yet
- [ ] IA **NOT** granted minting authority yet
- [ ] GraphToken.isMinter(ia) returns `false`
- [ ] RewardsManager.issuanceAllocator() returns `address(0)`

**State after Stage 1:** Deployed but completely inactive (zero production impact)

---

## Stage 2: Activate with No Distribution Change

**Purpose:** Integrate IA with protocol while maintaining existing distribution

### Prerequisites

- [ ] Stage 1 complete
- [ ] Comprehensive testing complete
- [ ] Governance approval obtained
- [ ] Independent verification performed

### Actions

**Generate governance transaction batch:**
```bash
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --network arbitrumSepolia \
  --rewardsManagerImplementation <address> \
  --rewardsEligibilityOracleAddress <address> \
  --outputDir ./governance-proposals
```

**Note:** Current task generates batch for both REO and IA integration. If REO already integrated, would need separate task (future enhancement).

**Governance executes:**

1. **Integrate IA with RewardsManager**
   ```typescript
   await rewardsManager.setIssuanceAllocator(iaAddress)
   ```

2. **Grant Minting Authority**
   ```typescript
   await graphToken.addMinter(iaAddress)
   ```

### Verification

- [ ] RewardsManager.issuanceAllocator() returns IA address
- [ ] GraphToken.isMinter(ia) returns `true`
- [ ] IA can mint tokens
- [ ] Distribution still 100% to RewardsManager
- [ ] **Rewards to indexers unchanged** (critical!)
- [ ] Monitor for 24 hours: no issues

### Verification Script (to be created)

```typescript
// scripts/verify/verify-ia-stage2.ts
const rm = await ethers.getContractAt("RewardsManager", RM_ADDRESS)
const ia = await ethers.getContractAt("IssuanceAllocator", IA_ADDRESS)
const gt = await ethers.getContractAt("GraphToken", GT_ADDRESS)

// Check integration
console.log("RM.issuanceAllocator():", await rm.issuanceAllocator())
// Should equal IA_ADDRESS

// Check minting authority
console.log("GT.isMinter(ia):", await gt.isMinter(ia.address))
// Should equal true

// Check allocation (should still be 100% RM)
const [allocatorPPM, selfPPM] = await ia.getTargetAllocation(rm.address)
console.log("RM Allocation:", (allocatorPPM.toNumber() / 10000).toFixed(2) + "%")
// Should equal 100.00%

// Check other targets have 0% allocation
const targets = await ia.getAllTargets() // If this method exists
for (const target of targets) {
  if (target !== rm.address) {
    const [ppm, _] = await ia.getTargetAllocation(target)
    console.log(`${target} Allocation:`, (ppm.toNumber() / 10000).toFixed(2) + "%")
    // Should equal 0.00%
  }
}
```

**State after Stage 2:** Live system, but economically identical to before (100% to RM)

**Critical Success Metric:** Indexer rewards **must be unchanged** from before integration

---

## Stage 3: Gradual Allocation Changes

**Purpose:** Transition to new distribution model gradually and safely

### Prerequisites

- [ ] Stage 2 complete
- [ ] Monitoring period complete (4-8 weeks recommended)
- [ ] System proven stable
- [ ] Governance approval for allocation changes

### Approach: Gradual Incremental Changes

**Week 1: Pilot (99% RM / 1% New Target)**

1. **Deploy DirectAllocation target** (if not already deployed)
   ```bash
   npx hardhat ignition deploy ignition/modules/DirectAllocation.ts \
     --network arbitrumSepolia \
     --deployment-id da-pilot-001
   ```

2. **Governance adjusts allocations**
   ```typescript
   // Set 99% to RewardsManager
   await ia.setTargetAllocation(rewardsManagerAddress, 990_000, 0, false)

   // Set 1% to DirectAllocation (pilot)
   await ia.setTargetAllocation(directAllocationAddress, 10_000, 0, false)
   ```

3. **Monitor for 1-2 weeks**
   - Verify 1% of issuance goes to DirectAllocation
   - Verify 99% still goes to RewardsManager
   - Monitor for any issues
   - Collect feedback

**Week 3-4: Small Increase (95% RM / 5% New)**

4. **If pilot successful, governance increases allocation**
   ```typescript
   // Set 95% to RewardsManager
   await ia.setTargetAllocation(rewardsManagerAddress, 950_000, 0, false)

   // Set 5% to DirectAllocation
   await ia.setTargetAllocation(directAllocationAddress, 50_000, 0, false)
   ```

5. **Monitor for 1-2 weeks**
   - Same verification as pilot
   - More significant impact, watch closely

**Ongoing: Continued Gradual Adjustments**

6. **Based on governance decisions, continue adjusting**
   - Each change requires governance approval
   - Monitor after each change
   - Example progression: 95% → 90% → 85% → ...
   - Or add additional targets: 85% RM / 10% DA1 / 5% DA2

### Important Considerations

**Monitoring After Each Change:**
- Verify on-chain allocations match expected
- Verify distribution amounts match expected percentages
- Monitor RewardsManager rewards (should decrease proportionally)
- Monitor new target balances (should increase as expected)
- Check for reverts or errors
- User feedback

**Rollback Capability:**
- At any point, governance can reset to 100% RM:
  ```typescript
  await ia.setTargetAllocation(rewardsManagerAddress, 1_000_000, 0, false)
  await ia.setTargetAllocation(directAllocationAddress, 0, 0, false)
  ```
- This immediately reverts to Stage 2 state (safe)

**Validation:**
```typescript
// scripts/verify/verify-allocations.ts
const ia = await ethers.getContractAt("IssuanceAllocator", IA_ADDRESS)

// Get all targets and their allocations
const targets = [
  { name: "RewardsManager", address: RM_ADDRESS },
  { name: "DirectAllocation", address: DA_ADDRESS },
  // Add more targets as deployed
]

let totalPPM = 0
for (const target of targets) {
  const [allocatorPPM, selfPPM] = await ia.getTargetAllocation(target.address)
  const percentage = (allocatorPPM.toNumber() / 10000).toFixed(2)

  console.log(`${target.name}: ${percentage}%`)
  totalPPM += allocatorPPM.toNumber()
}

console.log(`Total Allocation: ${(totalPPM / 10000).toFixed(2)}%`)
// Should equal 100.00%

if (totalPPM !== 1_000_000) {
  console.error("❌ Total allocation does not equal 100%!")
  process.exit(1)
}
```

**State after Stage 3:** New distribution model active, gradually adjusted to target allocation

---

## Why Each Stage Matters

### Stage 1: Risk-Free Deployment

**Without Stage 1:**
- Deploy and immediately activate ← High risk
- Difficult to test in production environment
- No opportunity for verification

**With Stage 1:**
- Deploy without impact ← Zero risk
- Can test thoroughly in production
- Can verify configuration correct
- Can take time to validate

**Critical:** This stage makes the rest safe.

---

### Stage 2: Validate Integration Before Economic Changes

**Without Stage 2:**
- Deploy and change distribution simultaneously ← Very high risk
- Multiple changes at once, hard to debug
- Can't isolate integration issues from distribution issues

**With Stage 2:**
- Integrate while replicating existing ← Moderate risk
- Validates integration works correctly
- Economic model unchanged, so safer
- Can verify IA ↔ RM interaction works
- Proves minting and distribution mechanics work

**Critical:** This stage proves the plumbing works before changing economics.

---

### Stage 3: Gradual Change with Monitoring

**Without Stage 3:**
- Change distribution immediately to target ← High risk
- Large impact, hard to rollback
- May not notice issues until significant damage

**With Stage 3:**
- Small incremental changes ← Low risk per change
- Monitor after each change
- Can rollback easily
- Issues caught early with minimal impact
- Build confidence with each step

**Critical:** This stage makes economic changes safely and reversibly.

---

## Rollback Procedures

### From Stage 3 (After Allocation Changes)

**Issue:** New distribution not working as expected

**Action:**
```typescript
// Governance resets to 100% RM
await ia.setTargetAllocation(rewardsManagerAddress, 1_000_000, 0, false)
await ia.setTargetAllocation(otherTarget, 0, 0, false)
```

**Result:** Reverts to Stage 2 state (IA active but 100% RM)

---

### From Stage 2 (After Integration)

**Issue:** Major problem with IA integration

**Action:**
```typescript
// Governance disconnects IA from RM
await rewardsManager.setIssuanceAllocator(ethers.ZeroAddress)

// Governance removes minting authority
await graphToken.removeMinter(iaAddress)
```

**Result:** Reverts to Stage 1 state (IA deployed but not active)

**Note:** RewardsManager reverts to self-minting (original behavior)

---

### From Stage 1 (Deployment Only)

**Issue:** Problem with IA deployment itself

**Action:**
- No rollback needed (not active, zero impact)
- Can redeploy IA if necessary
- Can fix issues and redeploy

**Result:** System unchanged (IA never activated)

---

## Testing Strategy

### Before Stage 1

- [ ] Comprehensive unit tests
- [ ] Integration tests with RewardsManager
- [ ] Fork testing on mainnet state
- [ ] Security audit complete
- [ ] Testnet deployment and validation

### During Stage 1

- [ ] Deploy on testnet first
- [ ] Validate configuration
- [ ] Test allocation math (100% to RM)
- [ ] Verify issuance rate matches RM

### During Stage 2

- [ ] Monitor continuously for 24 hours
- [ ] Verify rewards distribution unchanged
- [ ] Check for reverts or errors
- [ ] Validate minting working correctly
- [ ] Continue monitoring for 4-8 weeks

### During Stage 3

- [ ] Monitor after each allocation change
- [ ] Verify percentages match expected
- [ ] Track distribution amounts
- [ ] User feedback collection
- [ ] Performance metrics

---

## Future Enhancements

### Additional Tooling Needed

1. **Separate Governance TX Builder for IA**
   - Current tool combines REO + IA integration
   - Need separate task for IA-only integration
   - Need task for allocation changes

2. **Verification Scripts**
   - `scripts/verify/verify-ia-deployment.ts` (Stage 1)
   - `scripts/verify/verify-ia-integration.ts` (Stage 2)
   - `scripts/verify/verify-allocations.ts` (Stage 3)

3. **Monitoring Scripts**
   - `scripts/monitor/check-ia-distribution.ts`
   - `scripts/monitor/check-allocations.ts`
   - Track historical distribution data

4. **GovernanceAssertions Helper**
   - Add IA-specific assertions
   - `assertIssuanceAllocatorSet(rm, ia)`
   - `assertReplicationAllocation(ia, rm)` (100% check)
   - `assertMinter(gt, ia)`

---

## Differences from Earlier Work

The earlier deployment work documented an 8-stage ServiceQualityOracle (now REO) rollout and this 3-stage IA migration. The current implementation has:

**Preserved:**
- ✅ 3-stage gradual migration pattern (critical)
- ✅ Zero-impact deployment concept
- ✅ Replication before adjustment
- ✅ Monitoring between stages

**Not Yet Implemented:**
- ❌ Separate governance tasks for IA
- ❌ Verification scripts for IA stages
- ❌ GovernanceAssertions with IA checks
- ❌ Comprehensive monitoring tooling

These can be added when IA deployment becomes imminent.

---

## References

- Earlier deployment work: `packages/issuance/deploy/analysis/DeploymentGuide.md`
- Current IA implementation: `packages/issuance/contracts/IssuanceAllocator.sol`
- API Reference: `APICorrectness.md`
- Governance Workflow: `GovernanceWorkflow.md`

---

**Remember:** The 3-stage pattern is not optional. It is the **only safe way** to deploy IssuanceAllocator on mainnet. Do not skip stages or rush the process.
