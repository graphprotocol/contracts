# Graph Protocol Issuance System - Complete Deployment Guide

For architecture and target definitions, see Design.md (canonical). This guide is procedural; governance workflow details live in Governance.md.

This guide covers the complete deployment of the Graph Protocol Issuance System, including all dependencies and components.

## **Deployment Overview**

The deployment consists of four major phases:

1. **Phase 1: RewardsManager Upgrade** - Ensure the Horizon RewardsManager proxy is on an implementation that exposes the issuance integration interfaces
2. **Phase 2: GraphIssuanceProxyAdmin (GraphProxyAdmin2) Deployment** - Shared proxy administration for issuance contracts
3. **Phase 3: RewardsEligibilityOracle Deployment** - Quality enforcement system
4. **Phase 4: IssuanceAllocator & PilotAllocation Deployment** - Token distribution system, including optional experimental pilot-allocation target

## 📋 **Prerequisites**

- [ ] Governance multi-sig access
- [ ] Network configuration (mainnet/arbitrum/sepolia)
- [ ] Existing Horizon deployment (GraphToken, RewardsManager, GraphProxyAdmin) on the target network, or equivalent contracts deployed via `packages/horizon`
- [ ] GraphToken contract address
- [ ] Current RewardsManager proxy address
- [ ] Deployment environment setup

## 🔄 **Phase 1: RewardsManager Upgrade**

The RewardsManager needs to be upgraded to support the new issuance system interfaces.

### **1.1 Prepare RewardsManager Upgrade**

Deploy the upgraded RewardsManager implementation via the Horizon deployment tooling (`packages/horizon`) or via orchestration tasks that depend on Horizon's Ignition modules. The key requirement is that RewardsManager exposes the issuance integration methods.

### **1.2 Execute RewardsManager Governance Upgrade**

Execute governance upgrade transaction via Safe multi-sig.

### **1.3 Verify RewardsManager Integration Points**

```bash
# Verify new interfaces are available
# - setIssuanceAllocator(address)
# - setRewardsEligibilityOracle(address)
# - issuanceAllocator() view function
# - rewardsEligibilityOracle() view function
```

TODO: Can this be done via checking interfaces are implemented? (Not indvidual calls, there are defined Interfaces and ERC165?)

**✅ Phase 1 Complete**: RewardsManager now supports issuance system integration

---

## 🏗️ **Phase 2: GraphProxyAdmin2 Deployment**

Deploy the shared proxy administration contract (GraphIssuanceProxyAdmin, implemented by the `GraphProxyAdmin2` contract) that will manage upgrades for all issuance system contracts.

### **2.1 Deploy GraphIssuanceProxyAdmin (GraphProxyAdmin2)**

Deploy the dedicated proxy admin for the issuance system using the standalone GraphIssuanceProxyAdmin Ignition module. RewardsEligibilityOracle and IssuanceAllocator deployment modules should depend on this shared module rather than deploying their own proxy admin instances.

### **2.2 Verify GraphIssuanceProxyAdmin Configuration**

Ensure the proxy admin is properly configured and owned by governance.

**Verification**:

- [ ] GraphIssuanceProxyAdmin (GraphProxyAdmin2) deployed successfully
- [ ] Owner is governance multi-sig address
- [ ] Contract is ready to manage proxy upgrades
- [ ] Address recorded in deployment artifacts

**✅ Phase 2 Complete**: GraphIssuanceProxyAdmin ready for issuance system contracts

---

## **Phase 3: RewardsEligibilityOracle Deployment**

Deploy and integrate the RewardsEligibilityOracle for indexer quality enforcement. This is a multi-stage process requiring careful configuration and validation.

### **Stage 3.1: Deploy RewardsEligibilityOracle**

Deploy the RewardsEligibilityOracle contract system using the existing GraphIssuanceProxyAdmin (GraphProxyAdmin2) via Hardhat Ignition.

**Verification**:

- [ ] RewardsEligibilityOracle proxy deployed
- [ ] RewardsEligibilityOracle implementation deployed
- [ ] Proxy managed by existing GraphIssuanceProxyAdmin (GraphProxyAdmin2)
- [ ] Contracts properly initialized

### **Stage 3.2: Define and Configure Roles**

Set up the role-based access control for the REO system based on GIP-0079 specifications.

**Required Governance Transactions**:

```solidity
// Set operator role (can manage oracles)
RewardsEligibilityOracle.grantRole(OPERATOR_ROLE, OPERATOR_ADDRESS)

// Set oracle roles (can mark indexers as eligible)
RewardsEligibilityOracle.grantRole(ORACLE_ROLE, ORACLE_1_ADDRESS)
RewardsEligibilityOracle.grantRole(ORACLE_ROLE, ORACLE_2_ADDRESS)
// ... additional oracles as needed
```

**Verification**:

- [ ] OPERATOR role assigned to operational team
- [ ] ORACLE roles assigned to authorized oracle operators
- [ ] Role hierarchy properly configured (operators can manage oracles)

### **Stage 3.3: Configure REO Parameters**

Set the operational parameters for quality assessment based on GIP-0079 specifications.

**Required Configuration**:

```solidity
// Configure the three main parameters from GIP-0079
RewardsEligibilityOracle.setAllowedPeriod(ALLOWED_PERIOD_SECONDS)        // How long eligibility lasts
RewardsEligibilityOracle.setOracleUpdateTimeout(TIMEOUT_SECONDS)         // Safety timeout for oracle updates
RewardsEligibilityOracle.setQualityChecking(true)                        // Enable quality checking
```

**Parameter Examples (from GIP-0079)**:

- **Allowed Period**: 14 days (1209600 seconds) - How long indexer eligibility lasts
- **Oracle Update Timeout**: 7 days (604800 seconds) - Safety mechanism if oracles stop updating
- **Quality Checking Active**: true - Enable the quality enforcement system

**Verification**:

- [ ] Allowed period set to 14 days (or governance-approved value)
- [ ] Oracle update timeout set to 7 days (or governance-approved value)
- [ ] Quality checking enabled
- [ ] Parameter values match GIP-0079 specifications

### **Stage 3.4: Prepare Oracle Operations**

Set up the oracle operators and their off-chain systems for quality assessment.

**Oracle Setup** (based on GIP-0079):

- Oracles have ORACLE_ROLE (granted in Stage 3.2)
- Oracles will call `allowIndexers(address[] indexers, bytes data)` function
- Quality assessment happens off-chain using service quality metrics
- Oracles should update eligibility regularly (less than 14-day allowed period)

**Off-chain Oracle Systems**:

- **Quality Metrics Collection**: Monitor indexer service quality, response times, availability
- **Assessment Framework**: Conservative quality metrics to identify underperforming indexers
- **Regular Updates**: Daily or regular cadence to mark eligible indexers
- **Transparency**: Provide methodology and results transparency

**Oracle Responsibilities** (from GIP-0079):

- Assess indexer service quality through off-chain mechanisms
- Mark eligible indexers by calling `allowIndexers()` function
- Provide transparency about assessment methodology
- Update eligibility regularly (recommended daily)

**Verification**:

- [ ] Oracle operators have off-chain monitoring systems ready
- [ ] Quality assessment methodology defined and documented
- [ ] Oracle update schedules established
- [ ] Transparency and reporting mechanisms in place

### **Stage 3.5: Testing and Validation Period**

Run the REO system in testing mode for a defined period to verify functionality.

**Testing Phase (Recommended: 2-4 weeks)**:

Testing can be done with quality checking disabled initially via `setQualityChecking(false)`, allowing all indexers to be eligible during testing. Monitor oracle submissions to ensure oracles are calling `allowIndexers()` and eligibility is being recorded correctly.

**Testing Activities**:

- [ ] Oracle operators call `allowIndexers()` with test indexer lists
- [ ] Verify `isAllowed()` function returns correct eligibility status
- [ ] Test eligibility expiration after allowed period (14 days)
- [ ] Test oracle update timeout safety mechanism (7 days)
- [ ] Monitor gas costs for oracle operations
- [ ] Test quality checking enable/disable functionality

**Validation Metrics**:

- **Assessment Coverage**: % of active indexers assessed
- **Oracle Participation**: % of oracles actively submitting
- **Score Accuracy**: Manual validation of quality scores
- **System Performance**: Gas costs, response times
- **Dispute Resolution**: Test dispute mechanisms

**Verification**:

- [ ] All oracle operators actively participating
- [ ] Quality assessments covering target indexer set
- [ ] Score calculations validated against manual review
- [ ] System performance within acceptable limits
- [ ] Emergency procedures tested and working

### **Stage 3.6: Governance Integration Preparation**

Prepare for integrating REO with the upgraded RewardsManager.

**Pre-Integration Checklist**:

- [ ] REO system fully tested and validated
- [ ] Oracle operators trained and operational
- [ ] Quality parameters finalized and approved
- [ ] Emergency procedures documented and tested
- [ ] Governance proposal prepared with REO contract address, integration timeline, rollback procedures, and success metrics

### **Stage 3.7: Execute Governance Integration**

Execute the governance transaction to connect REO to RewardsManager.

**Governance Execution**:

Execute governance transaction via Safe multi-sig to call `RewardsManager.setRewardsEligibilityOracle(REO_ADDRESS)`. This requires RewardsManager to be upgraded first (Phase 1).

**Post-Integration Verification**:

Verify RewardsManager integration:

1. Check REO address is set correctly in RewardsManager
2. RewardsManager calls isAllowed() when indexers claim rewards
3. Only eligible indexers receive rewards
4. Ineligible indexers are denied rewards

**Verification**:

- [ ] Governance transaction executed successfully
- [ ] RewardsManager correctly references REO address
- [ ] RewardsManager calls `isAllowed()` during reward claims
- [ ] Quality enforcement working: eligible indexers get rewards
- [ ] Quality enforcement working: ineligible indexers denied rewards

### **Stage 3.8: Monitoring and Adjustment Period**

Monitor the integrated system and make adjustments as needed.

**Monitoring Period (Recommended: 4-8 weeks)**:

- [ ] Daily monitoring of quality assessments
- [ ] Weekly review of indexer qualification changes
- [ ] Monthly parameter adjustment reviews
- [ ] Continuous oracle performance monitoring

**Key Metrics to Monitor**:

- **Indexer Qualification Rate**: % of indexers meeting quality standards
- **Oracle Participation**: Consistency of oracle submissions
- **Quality Score Distribution**: Range and distribution of scores
- **Dispute Rate**: Frequency of quality disputes
- **System Impact**: Effect on overall network rewards

**Adjustment Procedures**:

Parameter adjustments and oracle role administration can be performed via governance as needed, using `grantRole` and `revokeRole` functions on OPERATOR_ROLE and ORACLE_ROLE.

**✅ Phase 3 Complete**: RewardsEligibilityOracle fully operational and integrated with RewardsManager

---

## 💰 **Phase 4: IssuanceAllocator Deployment**

Deploy and migrate to the IssuanceAllocator system through careful, verifiable stages.

### **Stage 4.1: Contract Deployment and Configuration**

Deploy and configure the IssuanceAllocator to match existing configuration without impacting production.

#### **4.1.1 Deploy IssuanceAllocator**

Deploy IssuanceAllocator system using the existing GraphIssuanceProxyAdmin (GraphProxyAdmin2) from Phase 2 via Hardhat Ignition.

**Verification**:

- [ ] IssuanceAllocator proxy deployed
- [ ] IssuanceAllocator implementation deployed
- [ ] Proxy managed by existing GraphIssuanceProxyAdmin (GraphProxyAdmin2)
- [ ] Contracts properly initialized

#### **4.1.2 Configure Allocator to Match Existing Distribution**

Configure the Allocator to exactly replicate current RewardsManager behavior:

1. Set same issuance rate as current RewardsManager via `setIssuancePerBlock()`
2. Set 100% allocation to RewardsManager (self-minting target) via `setTargetAllocation(REWARDS_MANAGER_ADDRESS, 0, 1_000_000, true)`
3. Set 0% to other allocators (initially)

**Key Points**:

- **No Production Impact**: Allocator has no effect yet because RewardsManager doesn't use it
- **No Minting Authority**: Allocator cannot mint tokens yet
- **Exact Replication**: Same rate, same distribution (100% to RewardsManager)

**Verification**:

- [ ] Issuance rate matches current RewardsManager rate
- [ ] 100% allocation set to RewardsManager address
- [ ] RewardsManager configured as self-minting target
- [ ] Total allocations equal 100% (1,000,000 PPM)

#### **4.1.3 Validate Deployment, Configuration, and State**

Comprehensive validation of the deployed system: verify contract deployment, check issuance rate, allocation percentages, target addresses, and role assignments.

**Validation Checklist**:

- [ ] Contract bytecode matches expected implementation
- [ ] Configuration exactly replicates existing distribution
- [ ] Contract not paused
- [ ] Roles properly configured
- [ ] No unexpected state or configuration

**✅ Stage 4.1 Complete**: IssuanceAllocator deployed and configured, ready for governance validation

### **Stage 4.2: Migrate to Allocator Controlled Issuance**

Governance performs independent verification and makes the Allocator live in production.

#### **4.2.1 Complete Role Configuration and Transfer Governor**

Transfer governance control to the proper governance multi-sig via `grantRole` and `renounceRole` transactions.

**Verification**:

- [ ] Governor role transferred to governance multi-sig
- [ ] Deployer roles renounced
- [ ] Only governance can modify configuration

#### **4.2.2 Governance Independent Verification**

Governance performs comprehensive independent verification before going live.

**Governance Verification Checklist**:

- [ ] **Contract Verification**: Bytecode matches expected implementation
- [ ] **Configuration Verification**:
  - [ ] Issuance rate matches current RewardsManager
  - [ ] 100% allocation to RewardsManager address
  - [ ] RewardsManager set as self-minting target
- [ ] **State Verification**:
  - [ ] Contract not paused
  - [ ] Proper role assignments
  - [ ] No unexpected configuration
- [ ] **Security Review**: Independent audit of deployment and configuration

#### **4.2.3 Set RewardsManager to Use Allocator**

Execute critical governance transaction to make the Allocator live: `RewardsManager.setIssuanceAllocator(ISSUANCE_ALLOCATOR_ADDRESS)`

**Impact**:

- **Allocator Now Live**: RewardsManager now uses Allocator for issuance calculations
- **Same Distribution**: Still 100% to RewardsManager, no change in rewards
- **Self-Minting**: RewardsManager still mints its own tokens (backward compatibility)

**Post-Integration Verification**:

- [ ] RewardsManager correctly references Allocator address
- [ ] RewardsManager reads issuance via `issuanceAllocator.getTargetIssuancePerBlock(address(this)).selfIssuancePerBlock`
- [ ] Same reward amounts distributed to indexers
- [ ] No disruption to existing rewards distribution

#### **4.2.4 Grant Allocator Minting Authority**

Execute final governance transaction to grant minting authority: `GraphToken.addMinter(ISSUANCE_ALLOCATOR_ADDRESS)`

**Impact**:

- **Allocator Can Mint**: Now capable of allocator-controlled minting
- **Ready for New Targets**: Can mint tokens for DirectAllocation and other targets
- **Full Functionality**: Complete IssuanceAllocator system operational

**Verification**:

- [ ] Allocator has minting authority on GraphToken
- [ ] Can call `distributeIssuance()` successfully
- [ ] Ready to support non-self-minting allocation targets

**✅ Stage 4.2 Complete**: IssuanceAllocator live in production with existing distribution

### **Stage 4.3: Allocation Changes**

Governance-controlled allocation changes can now be made safely.

#### **4.3.1 Deploy Additional Allocation Targets**

Deploy DirectAllocation-based contracts for new allocation targets via Hardhat Ignition, including the optional PilotAllocation test/experimental target when appropriate.

#### **4.3.2 Gradual Allocation Adjustments**

Implement allocation changes gradually through governance using `setTargetAllocation()` to adjust percentages over time (e.g., Week 1: 95% RewardsManager / 5% new target, Week 4: 90% / 10%, etc.).

#### **4.3.3 Monitor and Verify Changes**

Continuously monitor system performance and verify allocation changes are working correctly: check distribution amounts, verify target contracts receive correct amounts, and monitor for any issues or unexpected behavior.

**Monitoring Checklist**:

- [ ] Allocation percentages applied correctly
- [ ] Token distribution amounts match expectations
- [ ] All targets receiving correct allocations
- [ ] No disruption to RewardsManager distribution
- [ ] System operating within expected parameters

**✅ Stage 4.3 Complete**: Full issuance system operational with new allocation model

---

## 🔧 **Operational Procedures**

### **Status Monitoring**

Check overall system status and verify component deployments using checkpoint modules and deployment status tasks.

### **Emergency Procedures**

In emergencies: pause IssuanceAllocator, pause RewardsEligibilityOracle, or revert to direct RewardsManager as needed via governance.

### **Upgrade Procedures**

For future upgrades: deploy new implementation, execute governance upgrade transaction, and verify upgrade success using checkpoint modules.

## 📊 **Success Criteria**

### **Phase 1 Success**

- [ ] RewardsManager upgraded successfully
- [ ] New interfaces available and functional
- [ ] No disruption to existing rewards distribution

### **Phase 2 Success**

- [ ] GraphIssuanceProxyAdmin (GraphProxyAdmin2) deployed successfully
- [ ] Owner set to governance multi-sig
- [ ] Ready to manage issuance system proxies

### **Phase 3 Success**

- [ ] RewardsEligibilityOracle deployed and operational
- [ ] Role-based access control configured
- [ ] Quality parameters set and validated
- [ ] Oracle operators registered and active
- [ ] Testing period completed successfully
- [ ] Governance integration executed
- [ ] Quality enforcement active in RewardsManager
- [ ] Monitoring period shows stable operation

### **Phase 4.1 Success (Contract Deployment and Configuration)**

- [ ] IssuanceAllocator deployed and operational
- [ ] Configuration exactly matches existing RewardsManager setup
- [ ] 100% allocation to RewardsManager (self-minting)
- [ ] No production impact (RewardsManager not using Allocator yet)
- [ ] Comprehensive validation completed

### **Phase 4.2 Success (Migrate to Allocator Controlled Issuance)**

- [ ] Governance roles properly transferred
- [ ] Independent governance verification completed
- [ ] RewardsManager successfully set to use Allocator
- [ ] Same reward distribution maintained (no disruption)
- [ ] Allocator granted minting authority
- [ ] System live in production with existing distribution

### **Phase 4.3 Success (Allocation Changes)**

- [ ] Additional allocation targets deployed
- [ ] Gradual allocation adjustments implemented
- [ ] New distribution model operational
- [ ] Continuous monitoring shows stable operation

## 🚨 **Risk Mitigation**

### **Deployment Safety Approach**

1. **No Production Impact During Deployment**: Allocator deployed and configured without affecting live rewards
2. **Independent Governance Verification**: Governance performs comprehensive verification before going live
3. **Exact Replication First**: 100% allocation to RewardsManager maintains existing distribution
4. **Gradual Migration**: Three distinct stages with verification at each step
5. **Self-Minting Compatibility**: RewardsManager continues self-minting during transition

### **Key Safety Mechanisms**

1. **Staged Deployment**: Each phase can be tested and verified independently
2. **Governance Control**: All critical transitions require governance approval
3. **Rollback Capability**: Clear rollback procedures at each stage
4. **Comprehensive Testing**: Full testing on testnets before mainnet
5. **Continuous Monitoring**: Real-time monitoring and verification at each step

### **Critical Verification Points**

1. **Contract Deployment**: Bytecode verification and configuration validation
2. **Governance Transfer**: Proper role assignments and access control
3. **Production Migration**: RewardsManager integration without disruption
4. **Minting Authority**: Safe granting of token minting permissions
5. **Allocation Changes**: Gradual adjustments with continuous monitoring

## 📋 **Network-Specific Considerations**

### **Mainnet**

- Requires governance approval for all upgrades
- Higher gas costs - optimize batch operations
- Maximum security and testing required

### **Arbitrum**

- Lower gas costs enable more frequent adjustments
- Bridge considerations for token transfers
- L1/L2 coordination for governance

### **Testnets (Sepolia/Arbitrum Sepolia)**

- Full testing of complete deployment flow
- Governance simulation
- Performance and gas optimization testing

## 🔧 **Parameter Configuration**

### **Required Parameters**

Each network requires these parameters in its JSON5 file:

```json5
{
  $global: {
    // Governance addresses
    owner: '0x...', // Governor/Council address

    // Protocol contracts
    graphToken: '0x...', // GraphToken contract address

    // Upgrade parameters (set after deployment)
    issuanceAllocatorProxyAddress: '0x...',
    proxyAdminAddress: '0x...',
    newImplementationAddress: '0x...',
  },

  IssuanceAllocator: {
    owner: '0x...', // Same as global owner
    graphToken: '0x...', // Same as global graphToken
  },
}
```

## 🧪 **Testing Strategy**

### **Pre-Deployment Testing**

- [ ] Unit tests for all contracts
- [ ] Integration tests for complete system
- [ ] Fork testing on mainnet state
- [ ] Gas optimization analysis

### **Deployment Testing**

- [ ] Testnet deployment and verification
- [ ] Governance workflow simulation
- [ ] Performance monitoring
- [ ] Security audit completion

## 📈 **Monitoring & Maintenance**

### **Post-Deployment Monitoring**

- [ ] Contract functionality verification
- [ ] Distribution accuracy monitoring
- [ ] Gas usage optimization
- [ ] Security incident response

### **Ongoing Maintenance**

- [ ] Regular system health checks
- [ ] Parameter adjustment procedures
- [ ] Upgrade preparation workflows
- [ ] Documentation updates

This comprehensive deployment ensures a safe, gradual rollout of the complete issuance system while maintaining existing functionality throughout the process.
