# Verification Checklists for REO Deployment

**Status:** Background / supplementary
**Last Updated:** 2025-11-19

> Canonical issuance deployment design now lives in
> `packages/issuance/deploy/docs/Design.md`. Cross-package governance and
> orchestration patterns live in `packages/deploy/docs`.
>
> This document is retained for detailed checklists and historical context; it
> should not be treated as the primary source of truth and should not be
> extended with new normative content.

---

## Overview

This document provides comprehensive verification checklists for each phase of
RewardsEligibilityOracle deployment. Use these checklists to ensure nothing is
missed and maintain audit trails.

---

## Pre-Deployment Checklist

### Code & Contracts

- [ ] **Contract code reviewed**
  - [ ] RewardsEligibilityOracle implementation reviewed
  - [ ] No security vulnerabilities identified
  - [ ] Code follows best practices

- [ ] **Audit complete**
  - [ ] Independent security audit performed
  - [ ] Audit report reviewed
  - [ ] All critical/high issues resolved
  - [ ] Medium/low issues addressed or documented

- [ ] **Tests passing**
  - [ ] Unit tests passing (`npx hardhat test`)
  - [ ] Integration tests passing
  - [ ] Coverage acceptable (>80% recommended)
  - [ ] Edge cases tested

### Configuration

- [ ] **Parameters validated**
  - [ ] `eligibilityPeriod`: 1_209_600 (14 days)
  - [ ] `oracleUpdateTimeout`: 604_800 (7 days)
  - [ ] `eligibilityValidationEnabled`: false (initially)
  - [ ] Parameters match GIP-0079 specifications

- [ ] **Network configuration correct**
  - [ ] RPC URLs configured
  - [ ] Chain ID correct
  - [ ] GraphToken address confirmed for network
  - [ ] RewardsManager address confirmed for network

### Roles & Permissions

- [ ] **Role addresses identified**
  - [ ] OPERATOR_ROLE address(es) identified
  - [ ] ORACLE_ROLE address(es) identified
  - [ ] Addresses controlled by appropriate parties
  - [ ] Backup/redundancy considered

- [ ] **Governance approval**
  - [ ] Forum discussion complete
  - [ ] Snapshot vote passed (if applicable)
  - [ ] Governance multi-sig ready
  - [ ] Timing coordinated

### Infrastructure

- [ ] **Deployer account ready**
  - [ ] Account has sufficient funds for deployment
  - [ ] Account has sufficient funds for verification
  - [ ] Private key secure

- [ ] **Oracle infrastructure ready**
  - [ ] Off-chain oracle system operational
  - [ ] Quality assessment pipeline working
  - [ ] Monitoring and alerting configured
  - [ ] Backup systems in place

---

## Phase 1: RewardsManager Upgrade

### Pre-Upgrade

- [ ] **New implementation deployed**
  - [ ] RewardsManager V6 implementation deployed
  - [ ] Implementation address recorded: `__________________`
  - [ ] Bytecode verified on block explorer

- [ ] **Implementation validation**
  - [ ] Has `setRewardsEligibilityOracle(address)` method
  - [ ] Has `setIssuanceAllocator(address)` method (for future)
  - [ ] Maintains all existing functionality
  - [ ] Tested on testnet/fork

- [ ] **Governance batch generated**
  - [ ] Safe transaction JSON generated
  - [ ] Transactions reviewed:
    - [ ] Transaction 1: `graphProxyAdmin.upgrade(rmProxy, newImpl)`
    - [ ] Transaction 2: `graphProxyAdmin.acceptProxy(newImpl, rmProxy)`
  - [ ] Addresses verified correct
  - [ ] Transaction data verified

### Execution

- [ ] **Governance review**
  - [ ] Independent review performed
  - [ ] Governance forum discussion complete
  - [ ] Snapshot vote passed (if required)

- [ ] **Safe execution**
  - [ ] Transaction batch uploaded to Safe
  - [ ] All signers reviewed
  - [ ] Threshold signatures collected
  - [ ] Transaction executed
  - [ ] Transaction hash recorded: `__________________`

### Post-Upgrade Verification

- [ ] **Upgrade successful**
  - [ ] Transaction status: Success ✅
  - [ ] Block number recorded: `__________________`
  - [ ] Timestamp recorded: `__________________`

- [ ] **Implementation updated**
  - [ ] `graphProxyAdmin.getProxyImplementation(rmProxy)` returns new address
  - [ ] New implementation address: `__________________`

- [ ] **New methods exist**
  - [ ] Can call `rm.setRewardsEligibilityOracle.staticCall(address)`
  - [ ] Can call `rm.setIssuanceAllocator.staticCall(address)`
  - [ ] Methods accept correct parameters

- [ ] **Existing functionality intact**
  - [ ] `rm.rewardsManager()` still works (check existing method)
  - [ ] No state variables corrupted
  - [ ] Contract still owned by governance
  - [ ] No unexpected behavior

- [ ] **Events emitted**
  - [ ] `ProxyUpgraded(rmProxy, newImpl)` emitted
  - [ ] Event parameters correct

- [ ] **Block explorer**
  - [ ] Transaction visible
  - [ ] Status: Success
  - [ ] Events visible
  - [ ] Contract shows as upgraded

---

## Phase 2: REO Deployment

### Stage 2.1: Contract Deployment

#### Pre-Deployment

- [ ] **Phase 1 complete**
  - [ ] RewardsManager upgraded
  - [ ] Verification complete

- [ ] **Ignition ready**
  - [ ] Module tested: `ignition/modules/RewardsEligibilityOracle.ts`
  - [ ] Configuration file ready: `ignition/configs/issuance.<network>.json5`
  - [ ] Parameters validated
  - [ ] Deployment ID chosen: `__________________`

#### Deployment

- [ ] **Deploy via Ignition**

  ```bash
  npx hardhat ignition deploy ignition/modules/RewardsEligibilityOracle.ts \
    --network <network> \
    --parameters ignition/configs/issuance.<network>.json5 \
    --deployment-id <deployment-id>
  ```

  - [ ] Deployment successful
  - [ ] Transaction hashes recorded
  - [ ] Gas costs recorded

- [ ] **Sync addresses**

  ```bash
  npx ts-node scripts/sync-addresses.ts <deployment-id> <chain-id>
  ```

  - [ ] Addresses synced to `addresses.json`
  - [ ] Address book updated correctly

- [ ] **Verify contracts**

  ```bash
  npx hardhat ignition verify <deployment-id>
  ```

  - [ ] Implementation verified
  - [ ] Proxy verified
  - [ ] Verification successful on block explorer

#### Post-Deployment Verification

- [ ] **Contract addresses recorded**
  - [ ] REO Proxy: `__________________`
  - [ ] REO Implementation: `__________________`
  - [ ] ProxyAdmin: `__________________`

- [ ] **Deployment verification**
  - [ ] REO proxy deployed at expected address
  - [ ] REO implementation deployed
  - [ ] TransparentUpgradeableProxy pattern correct
  - [ ] Proxy points to implementation

- [ ] **Initialization verification**
  - [ ] Contract initialized (cannot re-initialize)
  - [ ] `reo.rewardsManager()` returns correct address: `__________________`
  - [ ] `reo.eligibilityPeriod()` returns `1_209_600`
  - [ ] `reo.oracleUpdateTimeout()` returns `604_800`
  - [ ] `reo.eligibilityValidationEnabled()` returns `false`

- [ ] **Ownership verification**
  - [ ] `reo.owner()` returns governance multi-sig: `__________________`
  - [ ] ProxyAdmin owned by governance
  - [ ] Owner can call owner-only functions

- [ ] **Interface verification**
  - [ ] Implements IRewardsEligibilityOracle
  - [ ] All interface methods exist
  - [ ] Can call view functions
  - [ ] Returns expected data types

- [ ] **Block explorer verification**
  - [ ] REO proxy verified on block explorer
  - [ ] REO implementation verified on block explorer
  - [ ] Source code visible
  - [ ] Contract info correct (name, compiler version)

- [ ] **Address book verification**
  - [ ] `addresses.json` contains correct entries
  - [ ] Chain ID correct
  - [ ] Proxy address correct
  - [ ] Implementation address correct
  - [ ] ProxyAdmin address correct

### Stage 2.2: Role Configuration

#### Pre-Configuration

- [ ] **Stage 2.1 complete**
  - [ ] Contracts deployed
  - [ ] Verification complete

- [ ] **Role addresses confirmed**
  - [ ] OPERATOR addresses: `__________________`
  - [ ] ORACLE addresses: `__________________`
  - [ ] Addresses controlled securely

- [ ] **Governance batch prepared**
  - [ ] Transaction data for role grants prepared
  - [ ] Safe transaction JSON created (if using Safe)

#### Configuration

- [ ] **Grant OPERATOR_ROLE**
  - [ ] Transaction submitted or batch executed
  - [ ] Transaction hash: `__________________`
  - [ ] `reo.hasRole(OPERATOR_ROLE, operatorAddress)` returns `true`
  - [ ] Event: `RoleGranted(OPERATOR_ROLE, operatorAddress, sender)` emitted

- [ ] **Grant ORACLE_ROLE**
  - [ ] Transaction submitted or batch executed
  - [ ] Transaction hash: `__________________`
  - [ ] `reo.hasRole(ORACLE_ROLE, oracleAddress)` returns `true`
  - [ ] Event: `RoleGranted(ORACLE_ROLE, oracleAddress, sender)` emitted

#### Post-Configuration Verification

- [ ] **Roles granted successfully**
  - [ ] OPERATOR can call operator-only functions
  - [ ] ORACLE can call oracle-only functions
  - [ ] Non-role addresses cannot call restricted functions

- [ ] **Test role functionality**
  - [ ] OPERATOR can call `setEligibilityPeriod()` (test with static call)
  - [ ] ORACLE can call `updateOracleData()` (test with static call)
  - [ ] Random address cannot call restricted functions (expect revert)

### Stage 2.3: Oracle Operations Setup

#### Infrastructure

- [ ] **Oracle system operational**
  - [ ] Off-chain oracle deployed/running
  - [ ] Can fetch indexer data
  - [ ] Can assess quality
  - [ ] Can construct oracle updates

- [ ] **Monitoring configured**
  - [ ] Oracle health monitoring active
  - [ ] Data quality monitoring active
  - [ ] Alerts configured
  - [ ] Dashboards available

- [ ] **Testing completed**
  - [ ] Dry-run oracle updates successful
  - [ ] Quality assessment tested
  - [ ] Error handling tested
  - [ ] Backup procedures tested

#### Documentation

- [ ] **Oracle operations documented**
  - [ ] How to run oracle
  - [ ] How to submit data
  - [ ] How to monitor
  - [ ] Emergency procedures

- [ ] **Runbooks created**
  - [ ] Normal operations
  - [ ] Troubleshooting
  - [ ] Emergency response

---

## Phase 3: Testing Period

### Smart Contract Testing

- [ ] **View function testing**
  - [ ] All view functions callable
  - [ ] Return expected values
  - [ ] No reverts on valid inputs
  - [ ] Reverts correctly on invalid inputs

- [ ] **Oracle data testing**
  - [ ] Can submit test oracle data
  - [ ] Data stored correctly
  - [ ] Events emitted correctly
  - [ ] Can query stored data

- [ ] **Configuration testing**
  - [ ] OPERATOR can update parameters
  - [ ] Parameter updates take effect
  - [ ] Events emitted on updates
  - [ ] Validation logic works correctly

- [ ] **Edge case testing**
  - [ ] Oracle timeout handling
  - [ ] Eligibility period expiration
  - [ ] Empty oracle data
  - [ ] Invalid oracle data (expect reverts)

- [ ] **Gas cost analysis**
  - [ ] Oracle update costs acceptable
  - [ ] Query costs acceptable
  - [ ] No unexpected gas spikes

### Oracle Operations Testing

- [ ] **Data submission**
  - [ ] Multiple oracle data submissions successful
  - [ ] Data covers expected indexer set
  - [ ] Frequency matches requirements
  - [ ] No failures or errors

- [ ] **Data quality**
  - [ ] Assessment logic working correctly
  - [ ] Data accuracy validated
  - [ ] Edge cases handled
  - [ ] Quality metrics acceptable

- [ ] **Monitoring**
  - [ ] All metrics collecting
  - [ ] Dashboards updating
  - [ ] Alerts triggering correctly
  - [ ] No blind spots

### Security Review

- [ ] **Audit verification**
  - [ ] Deployed code matches audited code
  - [ ] No changes since audit
  - [ ] Audit findings addressed

- [ ] **Operational security**
  - [ ] Private keys secure
  - [ ] Access controls correct
  - [ ] Monitoring for anomalies
  - [ ] Incident response plan ready

### Duration & Sign-off

- [ ] **Testing period complete**
  - [ ] Duration: 2-4 weeks (recommended)
  - [ ] Start date: `__________________`
  - [ ] End date: `__________________`

- [ ] **Sign-off**
  - [ ] Dev team approval
  - [ ] Security team approval
  - [ ] Governance approval to proceed

---

## Phase 4: Integration

### Stage 4.1: Governance Preparation

#### Proposal Preparation

- [ ] **Phase 3 complete**
  - [ ] Testing successful
  - [ ] All issues resolved
  - [ ] Sign-off obtained

- [ ] **Governance batch generated**

  ```bash
  npx hardhat issuance:build-rewards-eligibility-upgrade \
    --network <network> \
    --rewardsManagerImplementation <address> \
    --rewardsEligibilityOracleAddress <address> \
    --outputDir ./governance-proposals
  ```

  - [ ] Safe transaction JSON generated
  - [ ] File location: `__________________`

- [ ] **Transaction review**
  - [ ] Transaction 1: Upgrade RM (if not done in Phase 1)
  - [ ] Transaction 2: Accept proxy (if upgrading)
  - [ ] Transaction 3: Set IssuanceAllocator (if deployed, or can be removed)
  - [ ] Transaction 4: Set RewardsEligibilityOracle
  - [ ] All addresses verified correct
  - [ ] All data verified correct
  - [ ] Transaction ordering correct

#### Independent Verification

- [ ] **Contract verification**
  - [ ] REO bytecode verified
  - [ ] REO configuration verified
  - [ ] REO ownership verified
  - [ ] No unexpected changes since testing

- [ ] **Transaction verification**
  - [ ] Independent party reviews transactions
  - [ ] Addresses correct
  - [ ] Data correct
  - [ ] No malicious actions
  - [ ] Expected state transitions documented

- [ ] **Documentation prepared**
  - [ ] Current state documented
  - [ ] Expected state documented
  - [ ] Verification checklist prepared
  - [ ] Rollback procedure documented

#### Governance Approval

- [ ] **Forum discussion**
  - [ ] Proposal posted
  - [ ] Discussion period complete
  - [ ] Questions answered
  - [ ] Consensus reached

- [ ] **Snapshot vote** (if applicable)
  - [ ] Vote created
  - [ ] Voting period complete
  - [ ] Quorum reached
  - [ ] Approval threshold met

### Stage 4.2: Governance Execution

#### Safe Setup

- [ ] **Transaction batch uploaded**
  - [ ] Uploaded to Safe Transaction Builder
  - [ ] Transactions visible in Safe UI
  - [ ] Addresses correct
  - [ ] Data correct

- [ ] **Safe review**
  - [ ] All signers reviewed independently
  - [ ] No objections raised
  - [ ] Simulation run (if available)
  - [ ] Expected state changes confirmed

#### Execution

- [ ] **Signatures collected**
  - [ ] Signer 1 signed: ✓
  - [ ] Signer 2 signed: ✓
  - [ ] Signer 3 signed: ✓
  - [ ] (Add more as needed)
  - [ ] Threshold reached: ✓

- [ ] **Transaction executed**
  - [ ] Final signer executed
  - [ ] Transaction submitted to network
  - [ ] Transaction hash: `__________________`
  - [ ] Block number: `__________________`
  - [ ] Timestamp: `__________________`

#### Post-Execution Verification

- [ ] **Transaction successful**
  - [ ] Status: Success ✅
  - [ ] No reverts
  - [ ] All sub-transactions successful

- [ ] **Integration verified**
  - [ ] `rm.rewardsEligibilityOracle()` returns REO address: `__________________`
  - [ ] REO address matches expected
  - [ ] RewardsManager can query REO
  - [ ] No errors when querying

- [ ] **Events verification**
  - [ ] `RewardsEligibilityOracleSet(reoAddress)` emitted
  - [ ] Event parameters correct
  - [ ] Block and transaction correct

- [ ] **Functionality verification**
  - [ ] RewardsManager queries working
  - [ ] REO responses correct (validation disabled, so all eligible)
  - [ ] No unexpected behavior
  - [ ] No reverts in normal operation

- [ ] **Block explorer verification**
  - [ ] Transaction visible
  - [ ] Events visible
  - [ ] State changes visible
  - [ ] Everything as expected

---

## Phase 5: Monitoring Period

### Initial Monitoring (First 24 Hours)

- [ ] **Hourly checks**
  - [ ] Oracle data updates occurring
  - [ ] RewardsManager queries working
  - [ ] No reverts or errors
  - [ ] Events emitting correctly

- [ ] **Metrics collection**
  - [ ] Oracle update frequency tracked
  - [ ] Indexer coverage tracked
  - [ ] Query counts tracked
  - [ ] Gas costs tracked

- [ ] **Issue monitoring**
  - [ ] No errors logged
  - [ ] No user complaints
  - [ ] No unexpected behavior
  - [ ] System stable

### Ongoing Monitoring (First Week)

- [ ] **Daily checks**
  - [ ] Oracle operating normally
  - [ ] Data quality acceptable
  - [ ] RewardsManager integration working
  - [ ] No issues reported

- [ ] **Weekly summary**
  - [ ] Metrics reviewed
  - [ ] Performance acceptable
  - [ ] Any issues documented and resolved
  - [ ] Team briefed

### Medium-term Monitoring (Weeks 2-8)

- [ ] **Weekly checks**
  - [ ] Oracle reliability confirmed
  - [ ] Data accuracy validated
  - [ ] Integration stable
  - [ ] Ready for enabling validation

- [ ] **Monitoring period complete**
  - [ ] Duration: 4-8 weeks (recommended)
  - [ ] Start date: `__________________`
  - [ ] End date: `__________________`

- [ ] **Sign-off for Phase 6**
  - [ ] Dev team approval
  - [ ] Operations team approval
  - [ ] Governance approval to enable validation

### Metrics Tracked

- [ ] **Oracle metrics**
  - [ ] Update frequency
  - [ ] Data coverage (% indexers)
  - [ ] Data accuracy
  - [ ] Oracle uptime

- [ ] **System metrics**
  - [ ] Query counts
  - [ ] Gas costs
  - [ ] Response times
  - [ ] Error rates (should be zero)

- [ ] **Impact metrics**
  - [ ] Rewards distribution (should be unchanged while validation disabled)
  - [ ] User feedback
  - [ ] System stability

---

## Phase 6: Enable Validation

### Pre-Enablement

- [ ] **Phase 5 complete**
  - [ ] Monitoring period complete
  - [ ] Oracle proven reliable
  - [ ] Data quality validated
  - [ ] Team sign-off obtained

- [ ] **Governance approval**
  - [ ] Forum discussion
  - [ ] Snapshot vote (if applicable)
  - [ ] Governance batch prepared

### Enablement

- [ ] **Governance execution**
  - [ ] Transaction: `reo.setEligibilityValidationEnabled(true)`
  - [ ] Transaction submitted
  - [ ] Transaction hash: `__________________`
  - [ ] Status: Success ✅

### Post-Enablement Verification

- [ ] **Validation enabled**
  - [ ] `reo.eligibilityValidationEnabled()` returns `true`
  - [ ] Event: `EligibilityValidationEnabled(true)` emitted

- [ ] **Functionality verification**
  - [ ] RewardsManager enforcing eligibility
  - [ ] Eligible indexers receive rewards
  - [ ] Ineligible indexers do not receive rewards
  - [ ] System operating correctly

- [ ] **Impact verification**
  - [ ] Rewards distribution changes as expected
  - [ ] Eligibility percentages as expected
  - [ ] No unexpected behavior
  - [ ] User feedback acceptable

### Ongoing Monitoring

- [ ] **Continuous monitoring**
  - [ ] Oracle operation
  - [ ] Eligibility enforcement
  - [ ] Rewards distribution
  - [ ] User feedback

- [ ] **Regular reviews**
  - [ ] Weekly metrics review
  - [ ] Monthly governance report
  - [ ] Quarterly comprehensive review

---

## Emergency Procedures Checklist

### Rollback Integration (After Phase 4)

- [ ] **Identify issue**
  - [ ] Issue documented
  - [ ] Severity assessed
  - [ ] Rollback decision made

- [ ] **Governance emergency action**
  - [ ] Transaction: `rm.setRewardsEligibilityOracle(ethers.ZeroAddress)`
  - [ ] Emergency approval obtained
  - [ ] Transaction executed
  - [ ] Transaction hash: `__________________`

- [ ] **Verification**
  - [ ] Integration removed
  - [ ] RewardsManager operating normally
  - [ ] No rewards disruption

- [ ] **Recovery**
  - [ ] Issue fixed
  - [ ] Testing complete
  - [ ] Re-integration when safe

### Disable Validation (After Phase 6)

- [ ] **Identify issue**
  - [ ] Oracle issue or concern documented
  - [ ] Decision to disable made

- [ ] **Governance action**
  - [ ] Transaction: `reo.setEligibilityValidationEnabled(false)`
  - [ ] Emergency approval obtained
  - [ ] Transaction executed
  - [ ] Transaction hash: `__________________`

- [ ] **Verification**
  - [ ] Validation disabled
  - [ ] All indexers treated as eligible
  - [ ] Rewards continue normally

- [ ] **Recovery**
  - [ ] Oracle issue resolved
  - [ ] Testing complete
  - [ ] Re-enable when safe

---

## Post-Deployment Documentation

### Final Documentation

- [ ] **Deployment record**
  - [ ] All contract addresses recorded
  - [ ] All transaction hashes recorded
  - [ ] All block numbers recorded
  - [ ] Timeline documented

- [ ] **Address book updated**
  - [ ] `addresses.json` up to date
  - [ ] Committed to repository
  - [ ] Published (if public repository)

- [ ] **Documentation updated**
  - [ ] README updated
  - [ ] Integration guide updated
  - [ ] Monitoring guide updated
  - [ ] Emergency procedures updated

- [ ] **Communication complete**
  - [ ] Forum post with results
  - [ ] Team notified
  - [ ] Users informed
  - [ ] Documentation published

### Lessons Learned

- [ ] **Retrospective conducted**
  - [ ] What went well
  - [ ] What could improve
  - [ ] Issues encountered
  - [ ] Solutions applied

- [ ] **Documentation updated**
  - [ ] Checklists improved
  - [ ] Procedures refined
  - [ ] Common issues documented
  - [ ] Best practices captured

---

## Appendix: Quick Reference

### Key Addresses

**Network:** **\*\*\*\***\_\_**\*\*\*\***
**Chain ID:** **\*\*\*\***\_\_**\*\*\*\***

| Component                     | Address                      |
| ----------------------------- | ---------------------------- |
| GraphToken                    | **\*\*\*\***\_\_**\*\*\*\*** |
| RewardsManager Proxy          | **\*\*\*\***\_\_**\*\*\*\*** |
| RewardsManager Implementation | **\*\*\*\***\_\_**\*\*\*\*** |
| GraphProxyAdmin               | **\*\*\*\***\_\_**\*\*\*\*** |
| REO Proxy                     | **\*\*\*\***\_\_**\*\*\*\*** |
| REO Implementation            | **\*\*\*\***\_\_**\*\*\*\*** |
| REO ProxyAdmin                | **\*\*\*\***\_\_**\*\*\*\*** |
| Governance Multi-sig          | **\*\*\*\***\_\_**\*\*\*\*** |
| OPERATOR Address              | **\*\*\*\***\_\_**\*\*\*\*** |
| ORACLE Address                | **\*\*\*\***\_\_**\*\*\*\*** |

### Key Parameters

| Parameter                    | Value                  |
| ---------------------------- | ---------------------- |
| eligibilityPeriod            | 1_209_600 (14 days)    |
| oracleUpdateTimeout          | 604_800 (7 days)       |
| eligibilityValidationEnabled | false → true (Phase 6) |

### Key Commands

```bash
# Deploy
npx hardhat ignition deploy ignition/modules/RewardsEligibilityOracle.ts \
  --network <network> \
  --parameters ignition/configs/issuance.<network>.json5 \
  --deployment-id <deployment-id>

# Sync addresses
npx ts-node scripts/sync-addresses.ts <deployment-id> <chain-id>

# Verify
npx hardhat ignition verify <deployment-id>

# Generate governance batch
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --network <network> \
  --rewardsManagerImplementation <address> \
  --rewardsEligibilityOracleAddress <address> \
  --outputDir ./governance-proposals
```

---

**Note:** Check off items as you complete them. Fill in addresses, hashes, and dates as you go. This document serves as both a checklist and an audit trail.
