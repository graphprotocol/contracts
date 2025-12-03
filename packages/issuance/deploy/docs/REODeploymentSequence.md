# RewardsEligibilityOracle Deployment Sequence

**Status:** Background / supplementary (planning)
**Priority:** HIGH - REO deployment planned soon
**Last Updated:** 2025-11-19

> Canonical issuance deployment design now lives in
> `packages/issuance/deploy/docs/Design.md`. Cross-package governance and
> orchestration patterns live in `packages/deploy/docs`.
>
> This document captures a detailed REO deployment sequence and is retained
> for planning/background. It should not be treated as the primary source of
> truth and should not be extended with new normative content.

---

## Overview

This document outlines the deployment sequence for RewardsEligibilityOracle
(REO), including the required RewardsManager upgrade. This sequence is based on
production-ready patterns from earlier deployment work, adapted for the
current Ignition implementation.

### Scope

- **Immediate:** RewardsEligibilityOracle deployment and integration
- **Future:** IssuanceAllocator deployment (separate sequence, documented separately)

### Key Principles

1. **Zero-impact deployment** - Deploy contracts without affecting production
2. **Governance-gated activation** - Integration only via governance approval
3. **Phased rollout** - Separate deployment from activation
4. **Comprehensive verification** - Verify at each step

---

## Deployment Phases

### Phase 1: RewardsManager Upgrade (Prerequisite)

**Purpose:** Add integration methods to RewardsManager

**Prerequisites:**

- [ ] New RewardsManager V6 implementation deployed
- [ ] Implementation adds `setRewardsEligibilityOracle(address)` method
- [ ] Implementation adds `setIssuanceAllocator(address)` method (for future IA integration)
- [ ] Implementation tested and audited
- [ ] Governance approval obtained

**Actions:**

1. Deploy new RewardsManager V6 implementation
2. Generate governance transaction batch (via existing tooling)
3. Governance reviews and executes upgrade
4. Verify upgrade successful

**Verification:**

- [ ] New implementation address recorded
- [ ] Proxy upgraded successfully
- [ ] New methods exist and are callable
- [ ] Existing RewardsManager functionality unchanged
- [ ] Events emitted correctly

**Outputs:**

- RewardsManager V6 implementation address
- Transaction hash of upgrade
- Verification results

**State after Phase 1:** RewardsManager upgraded, but no integration yet

---

### Phase 2: REO Deployment

**Purpose:** Deploy RewardsEligibilityOracle contracts (no production impact)

#### Stage 2.1: Contract Deployment

**Prerequisites:**

- [ ] Phase 1 complete (RM upgraded)
- [ ] REO implementation and proxy modules ready
- [ ] Configuration parameters validated
- [ ] Deployer has sufficient funds
- [ ] Network configuration correct

**Deployment Steps:**

1. **Deploy via Ignition:**

   ```bash
   cd packages/issuance/deploy
   npx hardhat ignition deploy ignition/modules/RewardsEligibilityOracle.ts \
     --network arbitrumSepolia \
     --parameters ignition/configs/issuance.arbitrumSepolia.json5 \
     --deployment-id reo-arbitrum-sepolia-001
   ```

2. **Sync addresses:**

   ```bash
   npx ts-node scripts/sync-addresses.ts \
     reo-arbitrum-sepolia-001 \
     421614
   ```

3. **Verify contracts:**

   ```bash
   # Block explorer verification
   npx hardhat ignition verify reo-arbitrum-sepolia-001
   ```

**Verification:**

- [ ] REO implementation deployed
- [ ] REO proxy deployed
- [ ] REO initialized with correct parameters
- [ ] ProxyAdmin ownership transferred to governance
- [ ] Contract ownership transferred to governance
- [ ] Contracts verified on block explorer
- [ ] Address book updated

**Configuration Parameters:**

From `ignition/configs/issuance.<network>.json5`:

```json5
{
  $global: {
    graphTokenAddress: '0x...', // GraphToken for this network
  },
  RewardsEligibilityOracle: {
    eligibilityPeriod: 1_209_600, // 14 days (from GIP-0079)
    oracleUpdateTimeout: 604_800, // 7 days (safety mechanism)
    eligibilityValidationEnabled: false, // Disabled initially, governance enables
  },
}
```

**State after Stage 2.1:** REO deployed but not integrated (zero production impact)

#### Stage 2.2: Role Configuration

**Purpose:** Configure roles for REO operation

**Prerequisites:**

- [ ] Stage 2.1 complete
- [ ] OPERATOR addresses identified
- [ ] ORACLE addresses identified
- [ ] Governance approval for role grants

**Actions:**

Governance grants roles via Safe batch:

```typescript
// OPERATOR_ROLE - Can update configuration
reo.grantRole(OPERATOR_ROLE, operatorAddress)

// ORACLE_ROLE - Can update oracle data
reo.grantRole(ORACLE_ROLE, oracleAddress)
```

**Verification:**

- [ ] OPERATOR_ROLE granted to correct addresses
- [ ] ORACLE_ROLE granted to correct addresses
- [ ] Roles can be used (test transactions)

**State after Stage 2.2:** REO configured with roles

#### Stage 2.3: Oracle Operations Setup

**Purpose:** Set up off-chain systems for oracle operations

**Prerequisites:**

- [ ] Stage 2.2 complete
- [ ] Oracle infrastructure ready
- [ ] Quality assessment systems operational
- [ ] Monitoring in place

**Actions:**

1. Deploy/configure oracle infrastructure
2. Set up quality assessment pipeline
3. Configure monitoring and alerting
4. Test oracle data submission (dry-run)

**Verification:**

- [ ] Oracle can fetch indexer data
- [ ] Quality assessment logic working
- [ ] Can construct oracle data updates
- [ ] Monitoring operational

**State after Stage 2.3:** REO ready for testing

---

### Phase 3: Testing Period (Recommended: 2-4 weeks)

**Purpose:** Validate REO deployment before integration

**Prerequisites:**

- [ ] Phase 2 complete
- [ ] Test plan prepared
- [ ] Monitoring established

**Testing Activities:**

1. **Smart Contract Testing:**
   - [ ] Call all view functions
   - [ ] Test oracle data updates (ORACLE_ROLE)
   - [ ] Test configuration updates (OPERATOR_ROLE)
   - [ ] Test edge cases and error conditions
   - [ ] Gas cost analysis

2. **Oracle Operations Testing:**
   - [ ] Submit test oracle data
   - [ ] Verify data stored correctly
   - [ ] Test oracle timeout mechanism
   - [ ] Test eligibility period expiration
   - [ ] Monitor for any issues

3. **Security Review:**
   - [ ] Independent code review
   - [ ] Audit reports reviewed
   - [ ] Security testing complete

4. **Parameter Validation:**
   - [ ] Confirm eligibilityPeriod is correct (14 days)
   - [ ] Confirm oracleUpdateTimeout is correct (7 days)
   - [ ] Confirm validation initially disabled

**Success Criteria:**

- All tests passing
- No critical issues found
- Oracle operations functioning correctly
- Security review complete
- Governance comfortable proceeding

**State after Phase 3:** REO validated and ready for integration

---

### Phase 4: Integration (Governance)

**Purpose:** Integrate REO with RewardsManager (production impact)

#### Stage 4.1: Governance Preparation

**Prerequisites:**

- [ ] Phase 3 complete (testing successful)
- [ ] Governance proposal prepared
- [ ] Independent verification performed
- [ ] Governance approval obtained

**Actions:**

1. **Generate governance transaction batch:**

   ```bash
   cd packages/issuance/deploy

   npx hardhat issuance:build-rewards-eligibility-upgrade \
     --network arbitrumSepolia \
     --rewardsManagerImplementation 0x... \
     --rewardsEligibilityOracleAddress 0x... \
     --outputDir ./governance-proposals
   ```

   **Note:** This task generates a batch that:
   - Upgrades RewardsManager (if Phase 1 not yet done)
   - Accepts proxy implementation
   - Sets IssuanceAllocator (if deployed, otherwise can be zero address or removed)
   - Sets RewardsEligibilityOracle

2. **Review transaction batch:**
   - [ ] Verify all transaction data correct
   - [ ] Verify transaction ordering
   - [ ] Verify addresses correct
   - [ ] Independent review by governance

3. **Upload to Safe Transaction Builder:**
   - Upload generated JSON file
   - Review in Safe UI
   - Simulate transactions
   - Collect governance signatures

**State after Stage 4.1:** Governance proposal ready for execution

#### Stage 4.2: Governance Execution

**Prerequisites:**

- [ ] Stage 4.1 complete
- [ ] Required governance signatures collected
- [ ] Execution timing coordinated

**Actions:**

1. **Execute Safe batch transaction**
2. **Monitor transaction execution**
3. **Verify all transactions succeed**

**Verification:**

- [ ] Transaction executed successfully
- [ ] RewardsManager.rewardsEligibilityOracle() returns REO address
- [ ] Events emitted correctly
- [ ] No reverts or errors

**State after Stage 4.2:** REO integrated with RewardsManager

---

### Phase 5: Monitoring Period (Recommended: 4-8 weeks)

**Purpose:** Monitor REO integration before enabling validation

**Prerequisites:**

- [ ] Phase 4 complete (integration successful)
- [ ] Monitoring systems operational

**Monitoring Activities:**

**Immediate (First 24 Hours):**

- [ ] Monitor oracle data updates (hourly)
- [ ] Monitor RewardsManager queries to REO (hourly)
- [ ] Monitor for reverts or errors (continuous)
- [ ] Monitor gas costs
- [ ] Check for unexpected events

**Ongoing (First Week):**

- [ ] Daily oracle data review
- [ ] Daily verification that eligibility checks working
- [ ] Monitor RewardsManager rewards (should be unchanged while validation disabled)
- [ ] User feedback monitoring

**Medium-term (Weeks 2-8):**

- [ ] Weekly oracle data quality review
- [ ] Weekly system performance review
- [ ] Monitor for any issues or concerns
- [ ] Prepare for enabling validation

**Metrics to Track:**

- Oracle update frequency
- Oracle data coverage (% of indexers assessed)
- Eligibility percentages
- System performance
- Gas costs
- Any errors or reverts

**Success Criteria:**

- Oracle operating reliably
- Data quality acceptable
- No system issues
- Governance comfortable enabling validation

**State after Phase 5:** REO integrated and validated, ready to enable validation

---

### Phase 6: Enable Validation (Governance)

**Purpose:** Enable eligibility validation (affects rewards distribution)

**Prerequisites:**

- [ ] Phase 5 complete (monitoring successful)
- [ ] Oracle operation proven reliable
- [ ] Data quality validated
- [ ] Governance approval obtained

**Actions:**

Governance enables validation via Safe transaction:

```typescript
// Enable eligibility validation
reo.setEligibilityValidationEnabled(true)
```

**Verification:**

- [ ] Validation enabled successfully
- [ ] RewardsManager now enforcing eligibility
- [ ] Eligible indexers receive rewards
- [ ] Ineligible indexers do not receive rewards
- [ ] System operating as expected

**Monitoring:**

- [ ] Monitor rewards distribution changes
- [ ] Monitor for any disputes or issues
- [ ] Track eligibility percentages
- [ ] User feedback

**State after Phase 6:** REO fully operational with validation enabled

---

## Dependency Graph

```
RewardsManager V6 Upgrade (Phase 1)
    ↓
REO Deployment (Phase 2)
    ↓
Testing Period (Phase 3)
    ↓
Integration (Phase 4) - Governance Required
    ↓
Monitoring Period (Phase 5)
    ↓
Enable Validation (Phase 6) - Governance Required
```

---

## Sequencing Constraints

1. **RewardsManager MUST be upgraded first** - Provides `setRewardsEligibilityOracle()` method
2. **REO deployment has no dependencies** - Can deploy anytime after RM upgrade
3. **Integration requires governance** - Cannot self-activate
4. **Validation should be disabled initially** - Enable only after monitoring period
5. **Testing period recommended** - Validate before production integration
6. **Monitoring period recommended** - Validate integration before enabling enforcement

---

## Rollback Procedures

### Before Integration (Phases 1-3)

- **No rollback needed** - REO not integrated, zero production impact
- Can redeploy REO if issues found
- Can extend testing period indefinitely

### After Integration (Phases 4-5)

- **Rollback:** Governance sets `rewardsManager.setRewardsEligibilityOracle(address(0))`
- **Result:** RewardsManager reverts to previous behavior
- **Impact:** No rewards disruption, validation simply not enforced

### After Enabling Validation (Phase 6)

- **Rollback:** Governance calls `reo.setEligibilityValidationEnabled(false)`
- **Result:** Validation disabled, all indexers treated as eligible
- **Impact:** Rewards continue, but without quality enforcement

---

## Risk Mitigation

### Deployment Risks

- **Mitigation:** Zero-impact deployment (Phase 2) - not integrated until Phase 4
- **Mitigation:** Comprehensive testing period (Phase 3)
- **Mitigation:** Independent verification before governance execution

### Integration Risks

- **Mitigation:** Validation disabled initially (Phase 4-5)
- **Mitigation:** Monitoring period before enabling enforcement (Phase 5)
- **Mitigation:** Clear rollback procedure at each stage

### Oracle Operation Risks

- **Mitigation:** Oracle timeout safety mechanism (7 days)
- **Mitigation:** OPERATOR role can update configuration
- **Mitigation:** Validation can be disabled by governance if issues arise

---

## Network-Specific Considerations

### Arbitrum Sepolia (Testnet)

**Advantages:**

- Lower stakes, can test thoroughly
- Faster iteration
- Lower gas costs

**Deployment Strategy:**

- Full phased rollout recommended
- Use for validating procedures
- Test governance workflow end-to-end

### Arbitrum One (Mainnet)

**Advantages:**

- Production environment
- Real economics

**Requirements:**

- **MUST follow full phased rollout**
- **MUST complete testing on Arbitrum Sepolia first**
- **MUST have governance approval at each stage**
- **MUST have comprehensive monitoring**
- **MUST have clear rollback procedures**

---

## Existing Tooling

### Ignition Deployment Modules

Located in `packages/issuance/deploy/ignition/modules/`:

- **RewardsEligibilityOracle.ts** - Deploys REO with proxy
- **deploy.ts** - Orchestrator that deploys all contracts (including REO)

### Governance Transaction Builder

Located in `packages/issuance/deploy/governance/`:

- **tx-builder.ts** - TxBuilder class for Safe transaction JSONs
- **rewards-eligibility-upgrade.ts** - Builds RM upgrade + REO/IA integration batch

**Hardhat Task:**

```bash
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --network <network> \
  --rewardsManagerImplementation <address> \
  [--rewardsEligibilityOracleAddress <address>] \
  [--graphProxyAdmin <address>] \
  [--outputDir <path>]
```

See `packages/issuance/deploy/governance/README.md` for details.

### Address Sync Script

Located in `packages/issuance/scripts/`:

- **sync-addresses.ts** - Syncs Ignition deployment artifacts to main address book

---

## Future: IssuanceAllocator Integration

When IssuanceAllocator is ready to deploy:

1. Follow similar phased approach
2. Use **3-stage gradual migration pattern** (critical for safety)
3. Deploy → Replicate (100% to RM) → Adjust allocations
4. Governance transaction builder already supports IA integration
5. See separate documentation: `IADeploymentSequence.md` (to be created)

---

## Checklist Summary

**Pre-Deployment:**

- [ ] RewardsManager V6 implementation ready
- [ ] REO contracts audited
- [ ] Configuration parameters validated
- [ ] Governance approval obtained for RM upgrade

**Phase 1: RM Upgrade**

- [ ] Implementation deployed
- [ ] Governance batch generated
- [ ] Governance executes upgrade
- [ ] Upgrade verified

**Phase 2: REO Deployment**

- [ ] REO deployed via Ignition
- [ ] Addresses synced
- [ ] Contracts verified
- [ ] Roles configured
- [ ] Oracle operations set up

**Phase 3: Testing**

- [ ] Smart contract tests complete
- [ ] Oracle operations validated
- [ ] Security review complete
- [ ] 2-4 week testing period complete

**Phase 4: Integration**

- [ ] Governance batch generated
- [ ] Independent verification performed
- [ ] Governance executes integration
- [ ] Integration verified

**Phase 5: Monitoring**

- [ ] 4-8 week monitoring period complete
- [ ] Oracle operating reliably
- [ ] Data quality validated
- [ ] Governance approves enabling validation

**Phase 6: Enable Validation**

- [ ] Governance enables validation
- [ ] System operating as expected
- [ ] Monitoring continues

---

## Questions for Resolution

1. **Governance multi-sig address** - Confirmed for each network?
2. **OPERATOR_ROLE addresses** - Who should have operator privileges?
3. **ORACLE_ROLE addresses** - Who/what runs the oracle?
4. **Oracle infrastructure** - Where does it run? Who maintains it?
5. **Monitoring responsibility** - Who monitors REO operations?
6. **Testing timeline** - How long for testnet validation?
7. **Integration timeline** - When is target mainnet integration?
8. **Emergency contacts** - Who can execute emergency procedures?

---

## Next Steps

1. **Review this sequence** with team and governance
2. **Validate configuration parameters**
3. **Identify role addresses** (OPERATOR, ORACLE)
4. **Set up oracle infrastructure**
5. **Begin Phase 1** (RM upgrade) when ready
6. **Create verification checklists** (separate document)
7. **Create monitoring documentation** (separate document)

---

## References

- Earlier deployment work: `packages/issuance/deploy/analysis/DeploymentGuide.md`
- Governance tooling: `packages/issuance/deploy/governance/README.md`
- Ignition deployment: `packages/issuance/deploy/ignition/README.md`
- GIP-0079: [Link to GIP if available]
