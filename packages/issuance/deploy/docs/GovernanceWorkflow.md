# Governance Workflow for Issuance Deployment

**Last Updated:** 2025-11-19

---

## Overview

This document describes the governance workflow for deploying and integrating issuance contracts (RewardsEligibilityOracle and IssuanceAllocator). This workflow separates permissionless deployment from governance-required activation, enabling independent verification and safe production rollout.

---

## Three-Phase Governance Pattern

### Phase 1: Prepare (Permissionless)

**Who:** Anyone (typically core dev team)
**Impact:** None (no production changes)
**Purpose:** Deploy contracts and prepare governance proposal

**Activities:**

1. **Deploy Contracts**
   - Deploy implementations and proxies via Ignition
   - Initialize contracts with correct parameters
   - Transfer ownership to governance multi-sig
   - Verify contracts on block explorer

2. **Generate Governance Transaction Data**
   - Use existing tooling to generate Safe batch JSON
   - Document expected state transitions
   - Calculate transaction hashes

3. **Create Verification Materials**
   - Prepare verification checklist
   - Document current vs expected state
   - Gather contract addresses and parameters
   - Prepare monitoring plan

4. **Independent Review**
   - Code review by independent party
   - Contract audit verification
   - Parameter validation
   - Security assessment

**Outputs:**

- Deployed contract addresses
- Safe transaction batch JSON file
- Verification checklist
- Expected state documentation
- Independent review results

**Example: REO Deployment**

```bash
# 1. Deploy REO via Ignition
cd packages/issuance/deploy
npx hardhat ignition deploy ignition/modules/RewardsEligibilityOracle.ts \
  --network arbitrumSepolia \
  --parameters ignition/configs/issuance.arbitrumSepolia.json5 \
  --deployment-id reo-arbitrum-sepolia-001

# 2. Sync addresses
npx ts-node scripts/sync-addresses.ts reo-arbitrum-sepolia-001 421614

# 3. Generate governance batch
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --network arbitrumSepolia \
  --rewardsManagerImplementation 0x... \
  --rewardsEligibilityOracleAddress 0x... \
  --outputDir ./governance-proposals
```

**State after Phase 1:**

- ✅ Contracts deployed
- ✅ Governance proposal ready
- ❌ No production impact yet

---

### Phase 2: Execute (Governance Only)

**Who:** Governance multi-sig signers
**Impact:** Production changes occur
**Purpose:** Review and execute state transitions

**Activities:**

1. **Governance Review**
   - Review deployed contracts
   - Verify contract bytecode
   - Review transaction batch
   - Verify transaction data
   - Check independent review results
   - Discuss and approve in governance forum

2. **Safe Transaction Setup**
   - Upload JSON to Safe Transaction Builder UI
   - Review transactions in Safe UI
   - Simulate transactions (if supported)
   - Verify transaction ordering
   - Verify addresses and data

3. **Signature Collection**
   - First signer reviews and signs
   - Additional signers review and sign
   - Reach signature threshold

4. **Execution**
   - Final signer executes transaction
   - Monitor transaction status
   - Wait for confirmation

5. **Initial Verification**
   - Check transaction succeeded
   - Verify no reverts
   - Check events emitted

**Tools:**

- Gnosis Safe UI: <https://app.safe.global/>
- Block explorer for verification
- Generated Safe transaction batch JSON

**Governance Multi-sig Addresses:**

| Network          | Chain ID | Safe Address | Threshold |
| ---------------- | -------- | ------------ | --------- |
| Arbitrum One     | 42161    | TBD          | TBD       |
| Arbitrum Sepolia | 421614   | TBD          | TBD       |

**Example: Execute REO Integration**

1. Upload `tx-builder-<timestamp>.json` to Safe Transaction Builder
2. Review batch:
   - Transaction 1: Upgrade RewardsManager proxy
   - Transaction 2: Accept proxy implementation
   - Transaction 3: Set RewardsEligibilityOracle on RewardsManager
   - Transaction 4: Set IssuanceAllocator on RewardsManager (if deployed)
3. Collect signatures from governance multi-sig signers
4. Execute when threshold reached
5. Monitor transaction on block explorer

**State after Phase 2:**

- ✅ Transactions executed
- ✅ State transitions complete
- ✅ Production impact occurred

---

### Phase 3: Verify/Sync (Automated/Semi-automated)

**Who:** Dev team, automated scripts
**Impact:** None (verification only)
**Purpose:** Confirm expected state and update documentation

**Activities:**

1. **Run Verification Scripts**
   - Verify on-chain state matches expected
   - Check all contracts configured correctly
   - Verify events emitted correctly
   - Validate integration working

2. **Update Address Book**
   - Update addresses.json with active state
   - Remove pending implementation (if applicable)
   - Commit changes to repository

3. **Document Actual State**
   - Record transaction hashes
   - Document block numbers
   - Record timestamps
   - Note any deviations from expected

4. **Update Monitoring**
   - Add deployed contracts to monitoring
   - Set up alerts
   - Begin monitoring metrics

5. **Communication**
   - Announce successful deployment
   - Update documentation
   - Notify relevant stakeholders

**Example: Verify REO Integration**

```bash
# Run verification script (to be created in Phase 2 of recommendations)
npx ts-node scripts/verify/verify-reo-integration.ts --network arbitrumSepolia

# Expected output:
# ✅ RewardsManager.rewardsEligibilityOracle() == 0x...
# ✅ REO owned by governance
# ✅ REO parameters correct
# ✅ Events emitted correctly
```

**State after Phase 3:**

- ✅ Verification complete
- ✅ Address book updated
- ✅ Monitoring active
- ✅ Documentation updated

---

## Governance Transaction Patterns

### Pattern 1: Proxy Upgrade

**Use Case:** Upgrade RewardsManager to add integration methods

**Transactions:**

```typescript
// 1. Upgrade proxy to new implementation
graphProxyAdmin.upgrade(
  rewardsManagerProxy, // 0x... (proxy address)
  newImplementation, // 0x... (new implementation address)
)

// 2. Accept proxy implementation (accept upgrade)
graphProxyAdmin.acceptProxy(
  newImplementation, // 0x... (implementation address)
  rewardsManagerProxy, // 0x... (proxy address)
)
```

**Safe Batch JSON:**

Generated by `npx hardhat issuance:build-rewards-eligibility-upgrade`

**Verification:**

- [ ] Proxy points to new implementation
- [ ] New methods exist and are callable
- [ ] Existing functionality unchanged
- [ ] Events: `ProxyUpgraded(proxy, implementation)`

---

### Pattern 2: Integration

**Use Case:** Integrate REO with RewardsManager

**Transactions:**

```typescript
// Set RewardsEligibilityOracle on RewardsManager
rewardsManager.setRewardsEligibilityOracle(
  reoAddress, // 0x... (REO proxy address)
)
```

**Safe Batch JSON:**

Generated by `npx hardhat issuance:build-rewards-eligibility-upgrade`

**Verification:**

- [ ] `rewardsManager.rewardsEligibilityOracle()` returns REO address
- [ ] RewardsManager can query REO
- [ ] Events: `RewardsEligibilityOracleSet(oracle)`

---

### Pattern 3: Minting Authority (Future: IssuanceAllocator)

**Use Case:** Grant IssuanceAllocator minting authority on GraphToken

**Transactions:**

```typescript
// Grant minting authority
graphToken.addMinter(
  issuanceAllocatorAddress, // 0x... (IA proxy address)
)
```

**Safe Batch JSON:**

Can be added to existing batch or separate proposal

**Verification:**

- [ ] `graphToken.isMinter(ia)` returns `true`
- [ ] IA can mint tokens
- [ ] Events: `MinterAdded(minter)`

---

### Pattern 4: Configuration Update

**Use Case:** Update REO configuration parameters

**Transactions:**

```typescript
// Update eligibility period
reo.setEligibilityPeriod(
  1_209_600, // 14 days in seconds
)

// Update oracle timeout
reo.setOracleUpdateTimeout(
  604_800, // 7 days in seconds
)

// Enable/disable validation
reo.setEligibilityValidationEnabled(
  true, // or false
)
```

**Safe Batch JSON:**

Manual construction or extend tx-builder

**Verification:**

- [ ] Parameters updated on-chain
- [ ] Events: `ParameterUpdated(param, value)`

---

### Pattern 5: Role Management

**Use Case:** Grant roles for REO operation

**Transactions:**

```typescript
// Grant OPERATOR_ROLE
reo.grantRole(
  OPERATOR_ROLE, // bytes32 role identifier
  operatorAddress, // 0x... (operator address)
)

// Grant ORACLE_ROLE
reo.grantRole(
  ORACLE_ROLE, // bytes32 role identifier
  oracleAddress, // 0x... (oracle address)
)

// Revoke role if needed
reo.revokeRole(ROLE, address)
```

**Role Identifiers:**

```typescript
// From AccessControl
OPERATOR_ROLE = keccak256('OPERATOR_ROLE')
ORACLE_ROLE = keccak256('ORACLE_ROLE')
```

**Safe Batch JSON:**

Manual construction or extend tx-builder

**Verification:**

- [ ] `reo.hasRole(ROLE, address)` returns `true`
- [ ] Role holder can perform authorized actions
- [ ] Events: `RoleGranted(role, account, sender)`

---

### Pattern 6: Allocation Changes (Future: IssuanceAllocator)

**Use Case:** Adjust target allocations

**Transactions:**

```typescript
// Set allocation for RewardsManager (100%)
issuanceAllocator.setTargetAllocation(
  rewardsManagerAddress, // target
  1_000_000, // 100% in PPM (parts per million)
  0, // 0% self-minting
  false, // don't set if distribution pending
)

// Later: Adjust to 95% RM / 5% DirectAllocation
issuanceAllocator.setTargetAllocation(
  rewardsManagerAddress,
  950_000, // 95%
  0,
  false,
)
issuanceAllocator.setTargetAllocation(
  directAllocationAddress,
  50_000, // 5%
  0,
  false,
)
```

**Safe Batch JSON:**

Manual construction or extend tx-builder

**Verification:**

- [ ] `ia.getTargetAllocation(target)` returns expected percentages
- [ ] Distribution matches expected amounts
- [ ] Events: `TargetAllocationSet(target, allocatorPPM, selfPPM)`

---

## Safe Transaction Builder Guide

### Uploading Transaction Batch

1. **Navigate to Safe:**
   - Go to <https://app.safe.global/>
   - Connect wallet
   - Select correct network
   - Select governance Safe

2. **Open Transaction Builder:**
   - Click "New Transaction"
   - Select "Transaction Builder"
   - Click "Upload Batch"

3. **Upload JSON:**
   - Select generated `tx-builder-<timestamp>.json` file
   - Review transactions in UI
   - Verify addresses and data

4. **Review Transactions:**
   - Check each transaction
   - Verify "To" addresses
   - Verify transaction data (hex)
   - Check transaction order
   - Simulate if possible

5. **Create Proposal:**
   - Click "Create Batch"
   - Add description
   - Submit proposal

### Signing Process

1. **First Signer:**
   - Reviews proposal thoroughly
   - Verifies all details correct
   - Signs transaction
   - Proposal moves to "Awaiting Signatures"

2. **Additional Signers:**
   - Review proposal independently
   - Verify details
   - Sign transaction
   - Proposal reaches threshold

3. **Execution:**
   - Final signer or any signer can execute
   - Click "Execute"
   - Submit transaction to network
   - Wait for confirmation

### Transaction Simulation

Some networks support transaction simulation in Safe UI:

- Shows expected state changes
- Reveals potential reverts
- Displays events to be emitted
- **Highly recommended when available**

---

## Verification Procedures

### On-Chain State Verification

**Manual Verification:**

```typescript
// Using ethers.js or hardhat console
const rm = await ethers.getContractAt('IRewardsManager', RM_ADDRESS)
const reo = await ethers.getContractAt('IRewardsEligibilityOracle', REO_ADDRESS)

// Check integration
console.log('RM.rewardsEligibilityOracle():', await rm.rewardsEligibilityOracle())
// Should equal REO_ADDRESS

// Check REO configuration
console.log('REO.eligibilityPeriod():', await reo.eligibilityPeriod())
// Should equal 1_209_600 (14 days)

console.log('REO.oracleUpdateTimeout():', await reo.oracleUpdateTimeout())
// Should equal 604_800 (7 days)

console.log('REO.eligibilityValidationEnabled():', await reo.eligibilityValidationEnabled())
// Should equal false initially

// Check ownership
console.log('REO.owner():', await reo.owner())
// Should equal governance multi-sig address
```

**Automated Verification Scripts:**

To be created in Phase 2 of recommendations:

- `scripts/verify/verify-reo-deployment.ts` - Verify Phase 2
- `scripts/verify/verify-reo-integration.ts` - Verify Phase 4

### Event Verification

**Check emitted events:**

```bash
# Using block explorer or ethers.js
# Filter events by transaction hash
# Verify expected events emitted
```

**Expected events:**

**RewardsManager Upgrade:**

- `ProxyUpgraded(address indexed proxy, address implementation)`

**REO Integration:**

- `RewardsEligibilityOracleSet(address indexed oracle)`

**IA Integration (Future):**

- `IssuanceAllocatorSet(address indexed allocator)`

**Minting Authority (Future):**

- `MinterAdded(address indexed account)`

### Block Explorer Verification

1. **Find transaction on block explorer**
2. **Check status:** Success ✅
3. **Review events emitted**
4. **Check state changes** (if explorer supports)
5. **Verify contract interactions**

---

## Emergency Procedures

### Rollback REO Integration

**Scenario:** Critical issue with REO after integration

**Governance Action:**

```typescript
// Set REO to zero address (disables integration)
rewardsManager.setRewardsEligibilityOracle(ethers.ZeroAddress)
```

**Impact:**

- RewardsManager reverts to previous behavior
- No rewards disruption
- Validation not enforced

**Recovery:**

- Fix issue with REO
- Test thoroughly
- Re-integrate when safe

---

### Disable REO Validation

**Scenario:** Oracle issues, need to disable validation temporarily

**Governance Action:**

```typescript
// Disable validation
reo.setEligibilityValidationEnabled(false)
```

**Impact:**

- All indexers treated as eligible
- Rewards continue normally
- No quality enforcement

**Recovery:**

- Fix oracle issues
- Validate oracle operation
- Re-enable when ready

---

### Pause REO (If Pause Functionality Exists)

**Scenario:** Emergency, need to pause REO operations

**Governance Action:**

```typescript
// Pause REO (if Pausable inherited)
reo.pause()
```

**Impact:**

- REO operations paused
- RewardsManager queries may revert
- May affect rewards distribution

**Recovery:**

- Fix issue
- Test thoroughly
- Unpause when safe

---

## Communication Plan

### Pre-Deployment

- [ ] Forum post announcing deployment plans
- [ ] Technical details shared with governance
- [ ] Independent review results published
- [ ] Community feedback period

### Deployment (Phase 1)

- [ ] Announce deployment complete
- [ ] Share deployed contract addresses
- [ ] Publish verification results
- [ ] Link to governance proposal

### Governance Execution (Phase 2)

- [ ] Announce governance proposal created
- [ ] Share Safe transaction link
- [ ] Provide review period
- [ ] Announce execution timing
- [ ] Announce execution complete

### Post-Deployment (Phase 3)

- [ ] Announce verification complete
- [ ] Share monitoring dashboard (if available)
- [ ] Provide update on system status
- [ ] Document any issues encountered

### Ongoing

- [ ] Regular status updates during monitoring period
- [ ] Report any issues promptly
- [ ] Announce enabling of validation (Phase 6)
- [ ] Ongoing monitoring reports

---

## Governance Approval Process

### Forum Discussion

1. **Create governance forum post**
   - Title: "[Proposal] Deploy RewardsEligibilityOracle"
   - Description: What, why, when, how
   - Technical details: Contract addresses, parameters
   - Review results: Audits, testing
   - Timeline: Proposed phases
   - Request for feedback

2. **Discussion period**
   - Answer questions
   - Address concerns
   - Incorporate feedback
   - Build consensus

3. **Move to Snapshot** (if applicable)
   - Create Snapshot vote
   - Voting period (e.g., 7 days)
   - Reach quorum and approval threshold

### Safe Execution

4. **Create Safe proposal**
   - Upload transaction batch
   - Link to forum discussion
   - Link to Snapshot vote (if applicable)
   - Request signatures

5. **Signature collection**
   - Governance multi-sig signers review independently
   - Sign when comfortable
   - Reach signature threshold

6. **Execution**
   - Execute transaction
   - Announce completion
   - Verify success

---

## Tooling Reference

### Existing Tools

**Deployment:**

- Hardhat Ignition: `npx hardhat ignition deploy`
- Ignition modules: `ignition/modules/`
- Configuration: `ignition/configs/`

**Governance:**

- TxBuilder class: `deploy/governance/tx-builder.ts`
- REO upgrade builder: `deploy/governance/rewards-eligibility-upgrade.ts`
- Hardhat task: `npx hardhat issuance:build-rewards-eligibility-upgrade`

**Address Management:**

- Sync script: `scripts/sync-addresses.ts`
- Address book: `addresses.json`

**Toolshed Integration:**

- `@graphprotocol/toolshed`: `connectGraphIssuance()`, `connectGraphHorizon()`
- Typed contract instances for all interactions

### Tools to Create (Phase 2 of Recommendations)

**Verification:**

- `scripts/verify/verify-reo-deployment.ts`
- `scripts/verify/verify-reo-integration.ts`
- GovernanceAssertions helper contract

**Monitoring:**

- `scripts/monitor/check-reo-status.ts`
- `scripts/monitor/check-oracle-data.ts`

**Address Book Enhancement:**

- Support for pending implementation tracking
- `scripts/activate-pending.ts`

---

## Next Steps

1. **Review this workflow** with team and governance
2. **Identify governance multi-sig addresses** for each network
3. **Set up communication channels** (forum, Discord, etc.)
4. **Prepare governance proposal templates**
5. **Begin Phase 1 deployment** when ready

---

## References

- Safe Transaction Builder: <https://app.safe.global/>
- Earlier workflow documentation: `packages/issuance/deploy/analysis/Design.md`
- Deployment sequence: `packages/issuance/deploy/docs/REODeploymentSequence.md`
- Governance README: `packages/issuance/deploy/governance/README.md`
