# REO Architecture & Deployment Diagrams

**Last Updated:** 2025-11-19

---

## Contract Architecture

### REO Component Relationships

```mermaid
graph TB
    GOV[Governance Multi-sig]
    RM[RewardsManager]
    REO_PROXY[REO Proxy]
    REO_IMPL[REO Implementation]
    PA[ProxyAdmin]
    OPERATOR[Operator]
    ORACLE[Oracle Off-chain]

    GOV -->|owns| PA
    GOV -->|owns| REO_PROXY
    GOV -->|grants roles| REO_PROXY
    PA -->|manages| REO_PROXY
    REO_PROXY -->|delegates to| REO_IMPL
    RM -->|queries eligibility| REO_PROXY
    OPERATOR -->|updates config| REO_PROXY
    ORACLE -->|submits data| REO_PROXY

    style GOV fill:#f9f,stroke:#333,stroke-width:2px
    style RM fill:#bbf,stroke:#333,stroke-width:2px
    style REO_PROXY fill:#bfb,stroke:#333,stroke-width:2px
    style ORACLE fill:#fbb,stroke:#333,stroke-width:2px
```

**Key Relationships:**
- **Governance** owns and controls REO proxy
- **ProxyAdmin** manages proxy upgrades (owned by governance)
- **RewardsManager** queries REO for indexer eligibility
- **Operator** updates configuration (role granted by governance)
- **Oracle** submits eligibility data (role granted by governance)

---

## Deployment Sequence

### Phase-by-Phase Deployment Flow

```mermaid
sequenceDiagram
    participant DEV as Developer
    participant RM as RewardsManager
    participant REO as REO
    participant GOV as Governance
    participant ORC as Oracle

    Note over DEV,ORC: Phase 1: RM Upgrade
    DEV->>RM: Deploy new implementation
    GOV->>RM: Upgrade proxy to V6
    Note over RM: Now has setRewardsEligibilityOracle()

    Note over DEV,ORC: Phase 2: REO Deployment
    DEV->>REO: Deploy implementation + proxy
    DEV->>REO: Initialize (rewardsManager, params)
    DEV->>REO: Transfer ownership to GOV
    Note over REO: Deployed but not integrated

    Note over DEV,ORC: Phase 3: Testing (2-4 weeks)
    DEV->>REO: Run tests
    ORC->>REO: Test oracle submissions
    Note over REO: Validated but still not integrated

    Note over DEV,ORC: Phase 4: Integration
    GOV->>RM: setRewardsEligibilityOracle(REO)
    GOV->>REO: Grant OPERATOR_ROLE
    GOV->>REO: Grant ORACLE_ROLE
    Note over RM,REO: Integrated (validation disabled)

    Note over DEV,ORC: Phase 5: Monitoring (4-8 weeks)
    ORC->>REO: Submit oracle data
    RM->>REO: Query eligibility
    Note over RM,REO: All indexers eligible (validation disabled)

    Note over DEV,ORC: Phase 6: Enable Validation
    GOV->>REO: setEligibilityValidationEnabled(true)
    RM->>REO: Query eligibility
    REO-->>RM: Return actual eligibility
    Note over RM,REO: Validation enforced
```

---

## Governance Workflow

### Three-Phase Governance Pattern

```mermaid
stateDiagram-v2
    [*] --> Prepare
    Prepare --> Execute : Governance Approves
    Execute --> Verify : Transaction Succeeds
    Verify --> [*] : Verification Passes
    Execute --> Prepare : Transaction Fails
    Verify --> Prepare : Verification Fails

    note right of Prepare
        Permissionless Phase
        • Deploy contracts
        • Generate TX data
        • Create checklist
        • Independent review
        • Zero production impact
    end note

    note right of Execute
        Governance Phase
        • Review proposal
        • Collect signatures
        • Execute Safe batch
        • State transitions
        • Production impact
    end note

    note right of Verify
        Automated Phase
        • Run verification
        • Update address book
        • Confirm state
        • Begin monitoring
    end note
```

---

## REO Lifecycle States

### State Transitions

```mermaid
stateDiagram-v2
    [*] --> Deployed
    Deployed --> Testing : Phase 2 Complete
    Testing --> Integrated : Phase 4 (Governance)
    Integrated --> Monitoring : Integration Verified
    Monitoring --> Active : Phase 6 (Governance)
    Active --> [*]

    note right of Deployed
        • Contracts deployed
        • Initialized
        • Owned by governance
        • Not integrated with RM
        • Zero production impact
    end note

    note right of Testing
        • Testing period (2-4 weeks)
        • Smart contract tests
        • Oracle operations tests
        • Security review
        • Ready for integration
    end note

    note right of Integrated
        • RM.setRewardsEligibilityOracle() executed
        • Roles granted
        • Validation DISABLED
        • All indexers eligible
        • Monitoring integration
    end note

    note right of Monitoring
        • Monitoring period (4-8 weeks)
        • Oracle operating
        • RM queries working
        • Data quality validated
        • Ready for validation
    end note

    note right of Active
        • Validation ENABLED
        • Eligibility enforced
        • Oracle data used for rewards
        • Full production operation
    end note
```

---

## Integration Flow

### RewardsManager + REO Integration

```mermaid
graph LR
    RM[RewardsManager] -->|1. Query| REO[REO Proxy]
    REO -->|2. Delegate| IMPL[REO Implementation]
    IMPL -->|3. Check validation| VAL{Validation Enabled?}
    VAL -->|No| ALL[Return: All Eligible]
    VAL -->|Yes| DATA{Has Oracle Data?}
    DATA -->|Yes| CHECK[Check Eligibility]
    DATA -->|No| TIMEOUT{Timeout Exceeded?}
    TIMEOUT -->|No| ALL2[Return: All Eligible]
    TIMEOUT -->|Yes| REVERT[Revert: Oracle Timeout]
    CHECK -->|Eligible| ELIG[Return: Eligible]
    CHECK -->|Not Eligible| INELIG[Return: Not Eligible]

    ALL -->|4. Response| RM
    ALL2 -->|4. Response| RM
    ELIG -->|4. Response| RM
    INELIG -->|4. Response| RM
    REVERT -->|4. Revert| RM

    style RM fill:#bbf,stroke:#333,stroke-width:2px
    style REO fill:#bfb,stroke:#333,stroke-width:2px
    style ALL fill:#bfb,stroke:#333,stroke-width:1px
    style ALL2 fill:#bfb,stroke:#333,stroke-width:1px
    style ELIG fill:#bfb,stroke:#333,stroke-width:1px
    style INELIG fill:#fbb,stroke:#333,stroke-width:1px
    style REVERT fill:#f99,stroke:#333,stroke-width:2px
```

**Flow Description:**
1. RewardsManager queries REO for indexer eligibility
2. REO proxy delegates to implementation
3. Implementation checks if validation enabled
4. If disabled: All indexers eligible (Phase 4-5)
5. If enabled: Check oracle data
6. If no data or within grace period: All eligible
7. If data exists: Return actual eligibility
8. If timeout exceeded: Revert (safety mechanism)

---

## Oracle Operations

### Oracle Data Submission Flow

```mermaid
sequenceDiagram
    participant IDX as Indexers
    participant ORC as Oracle Off-chain
    participant REO as REO Contract
    participant RM as RewardsManager

    Note over IDX,RM: Continuous Operation

    loop Every Period (e.g., daily)
        ORC->>IDX: Fetch indexer data
        ORC->>ORC: Assess quality
        ORC->>ORC: Determine eligibility
        ORC->>REO: updateOracleData(indexers[], eligible[], periodEnd)
        Note over REO: Store eligibility data
        REO-->>ORC: Success
    end

    loop On Reward Distribution
        RM->>REO: isIndexerEligible(indexer)
        REO->>REO: Check stored data
        REO->>REO: Check period validity
        REO-->>RM: eligible (true/false)
        alt Eligible
            RM->>IDX: Distribute rewards
        else Not Eligible
            RM->>RM: Skip rewards
        end
    end
```

---

## Proxy Administration

### REO Proxy Pattern

```mermaid
graph TB
    GOV[Governance Multi-sig]
    PA[ProxyAdmin]
    PROXY[REO Proxy]
    IMPL_V1[REO Implementation V1]
    IMPL_V2[REO Implementation V2]
    USER[RewardsManager]

    GOV -->|owns| PA
    GOV -->|owns| PROXY
    PA -->|upgrade| PROXY
    PROXY -->|delegates to| IMPL_V1
    PROXY -.->|upgrade later| IMPL_V2
    USER -->|calls| PROXY

    style GOV fill:#f9f,stroke:#333,stroke-width:2px
    style PA fill:#ffa,stroke:#333,stroke-width:2px
    style PROXY fill:#bfb,stroke:#333,stroke-width:2px
    style IMPL_V1 fill:#aaf,stroke:#333,stroke-width:2px
    style IMPL_V2 fill:#aaf,stroke:#333,stroke-width:1px,stroke-dasharray: 5 5
    style USER fill:#bbf,stroke:#333,stroke-width:2px
```

**Upgrade Process:**
1. Deploy new implementation (IMPL_V2)
2. Governance calls `proxyAdmin.upgrade(proxy, impl_v2)`
3. Proxy now delegates to IMPL_V2
4. Storage preserved (proxy storage slot)
5. Users (RM) call same proxy address, get new logic

---

## Deployment Dependencies

### Dependency Graph

```mermaid
graph TD
    START[Start]
    RM_IMPL[Deploy RM V6 Implementation]
    RM_UPGRADE[Upgrade RM Proxy]
    REO_DEPLOY[Deploy REO Contracts]
    REO_TEST[Test REO]
    REO_INTEGRATE[Integrate REO with RM]
    REO_MONITOR[Monitor Integration]
    REO_ENABLE[Enable Validation]
    END[Fully Operational]

    START --> RM_IMPL
    RM_IMPL --> RM_UPGRADE
    RM_UPGRADE --> REO_DEPLOY
    REO_DEPLOY --> REO_TEST
    REO_TEST --> REO_INTEGRATE
    REO_INTEGRATE --> REO_MONITOR
    REO_MONITOR --> REO_ENABLE
    REO_ENABLE --> END

    style START fill:#fff,stroke:#333,stroke-width:2px
    style RM_UPGRADE fill:#ffa,stroke:#333,stroke-width:2px
    style REO_DEPLOY fill:#bfb,stroke:#333,stroke-width:2px
    style REO_INTEGRATE fill:#faa,stroke:#333,stroke-width:2px
    style REO_ENABLE fill:#faa,stroke:#333,stroke-width:2px
    style END fill:#aff,stroke:#333,stroke-width:2px

    class RM_UPGRADE,REO_INTEGRATE,REO_ENABLE governance
    classDef governance fill:#faa,stroke:#333,stroke-width:2px
```

**Critical Path:**
1. RM must be upgraded before REO deployment (provides integration method)
2. REO must be tested before integration
3. Integration requires governance approval
4. Monitoring period before enabling validation
5. Validation enablement requires governance approval

**Governance Gates** (red boxes): Points requiring governance multi-sig execution

---

## Rollback Procedures

### Rollback Flow

```mermaid
graph TD
    ISSUE[Issue Identified]
    ASSESS{Severity?}
    MINOR[Minor Issue]
    MAJOR[Major Issue]
    DISABLE[Disable Validation]
    DISCONNECT[Disconnect REO from RM]
    FIX[Fix Issue]
    TEST[Test Fix]
    REDEPLOY{Need Redeploy?}
    UPGRADE[Upgrade Implementation]
    RECONNECT[Reconnect REO]
    REENABLE[Re-enable Validation]
    MONITOR[Resume Monitoring]

    ISSUE --> ASSESS
    ASSESS -->|Minor| MINOR
    ASSESS -->|Major| MAJOR
    MINOR --> DISABLE
    MAJOR --> DISCONNECT
    DISABLE --> FIX
    DISCONNECT --> FIX
    FIX --> TEST
    TEST --> REDEPLOY
    REDEPLOY -->|Yes| UPGRADE
    REDEPLOY -->|No| REENABLE
    UPGRADE --> RECONNECT
    RECONNECT --> REENABLE
    REENABLE --> MONITOR

    style ISSUE fill:#f99,stroke:#333,stroke-width:2px
    style DISABLE fill:#ffa,stroke:#333,stroke-width:2px
    style DISCONNECT fill:#faa,stroke:#333,stroke-width:2px
    style MONITOR fill:#bfb,stroke:#333,stroke-width:2px
```

**Rollback Options:**

**Option 1: Disable Validation** (Minor issues, oracle problems)
- Governance: `reo.setEligibilityValidationEnabled(false)`
- Impact: All indexers treated as eligible, rewards continue
- Recovery: Fix oracle, re-enable when ready

**Option 2: Disconnect REO** (Major issues, contract problems)
- Governance: `rm.setRewardsEligibilityOracle(address(0))`
- Impact: RM reverts to previous behavior, no validation
- Recovery: Fix/upgrade REO, reconnect when safe

---

## Monitoring Architecture

### Monitoring Flow

```mermaid
graph LR
    REO[REO Contract]
    EVENTS[Event Logs]
    ORACLE[Oracle Off-chain]
    METRICS[Metrics Collection]
    DASH[Dashboard]
    ALERTS[Alerting System]
    OPS[Operations Team]

    REO -->|emits| EVENTS
    ORACLE -->|reports| METRICS
    EVENTS -->|feeds| METRICS
    METRICS -->|displays| DASH
    METRICS -->|triggers| ALERTS
    ALERTS -->|notifies| OPS
    DASH -->|viewed by| OPS

    style REO fill:#bfb,stroke:#333,stroke-width:2px
    style DASH fill:#bbf,stroke:#333,stroke-width:2px
    style ALERTS fill:#faa,stroke:#333,stroke-width:2px
    style OPS fill:#f9f,stroke:#333,stroke-width:2px
```

**Key Metrics:**
- Oracle update frequency
- Indexer coverage (% assessed)
- Eligibility percentages
- Query counts and response times
- Error rates
- Gas costs

---

## Access Control

### Role-Based Access Control

```mermaid
graph TB
    GOV[Governance Multi-sig]
    ADMIN[DEFAULT_ADMIN_ROLE]
    OPERATOR[OPERATOR_ROLE]
    ORACLE[ORACLE_ROLE]
    PUBLIC[Public Users]

    REO[REO Contract]

    GOV -->|is| ADMIN
    ADMIN -->|grants| OPERATOR
    ADMIN -->|grants| ORACLE
    ADMIN -->|can call| ADMIN_FUNCS[Admin Functions]
    OPERATOR -->|can call| OP_FUNCS[Operator Functions]
    ORACLE -->|can call| ORC_FUNCS[Oracle Functions]
    PUBLIC -->|can call| PUB_FUNCS[View Functions]

    ADMIN_FUNCS -->|on| REO
    OP_FUNCS -->|on| REO
    ORC_FUNCS -->|on| REO
    PUB_FUNCS -->|on| REO

    style GOV fill:#f9f,stroke:#333,stroke-width:2px
    style ADMIN fill:#faa,stroke:#333,stroke-width:2px
    style OPERATOR fill:#ffa,stroke:#333,stroke-width:2px
    style ORACLE fill:#aff,stroke:#333,stroke-width:2px
    style PUBLIC fill:#ddd,stroke:#333,stroke-width:1px
```

**Role Permissions:**

**DEFAULT_ADMIN_ROLE** (Governance):
- Grant/revoke all roles
- Upgrade implementation
- Transfer ownership
- Pause/unpause (if pausable)

**OPERATOR_ROLE:**
- `setEligibilityPeriod()`
- `setOracleUpdateTimeout()`
- `setEligibilityValidationEnabled()`
- Configuration updates

**ORACLE_ROLE:**
- `updateOracleData()`
- Submit eligibility assessments

**Public:**
- All view functions
- `isIndexerEligible()` (called by RM)

---

## Network Topology

### Multi-Network Deployment

```mermaid
graph TB
    subgraph "Arbitrum One (Mainnet)"
        RM1[RewardsManager]
        REO1[REO]
        GOV1[Governance Multi-sig]
    end

    subgraph "Arbitrum Sepolia (Testnet)"
        RM2[RewardsManager]
        REO2[REO]
        GOV2[Governance Multi-sig]
    end

    subgraph "Off-chain Infrastructure"
        ORACLE[Oracle System]
        MONITOR[Monitoring]
    end

    GOV1 -->|controls| REO1
    GOV2 -->|controls| REO2
    RM1 -->|queries| REO1
    RM2 -->|queries| REO2
    ORACLE -->|submits to| REO1
    ORACLE -->|submits to| REO2
    MONITOR -->|observes| REO1
    MONITOR -->|observes| REO2

    style RM1 fill:#bbf,stroke:#333,stroke-width:2px
    style REO1 fill:#bfb,stroke:#333,stroke-width:2px
    style RM2 fill:#bbf,stroke:#333,stroke-width:1px,stroke-dasharray: 5 5
    style REO2 fill:#bfb,stroke:#333,stroke-width:1px,stroke-dasharray: 5 5
    style ORACLE fill:#fbb,stroke:#333,stroke-width:2px
```

**Deployment Strategy:**
1. Deploy and validate on Arbitrum Sepolia first
2. Complete full lifecycle on testnet
3. Validate procedures and governance workflow
4. Deploy to Arbitrum One with proven process

---

## Future: IssuanceAllocator Integration

### Complete Issuance System

```mermaid
graph TB
    GT[GraphToken]
    IA[IssuanceAllocator]
    RM[RewardsManager]
    REO[RewardsEligibilityOracle]
    DA[DirectAllocation]
    GOV[Governance]

    GT -->|minted by| IA
    IA -->|distributes to| RM
    IA -->|distributes to| DA
    RM -->|checks eligibility| REO
    GOV -->|controls| IA
    GOV -->|controls| REO
    GOV -->|controls| RM

    style GT fill:#ffa,stroke:#333,stroke-width:2px
    style IA fill:#aff,stroke:#333,stroke-width:2px
    style RM fill:#bbf,stroke:#333,stroke-width:2px
    style REO fill:#bfb,stroke:#333,stroke-width:2px
    style DA fill:#fbb,stroke:#333,stroke-width:1px
    style GOV fill:#f9f,stroke:#333,stroke-width:2px
```

**Future State:**
- IssuanceAllocator mints tokens from GraphToken
- Distributes tokens to multiple targets (RM, DirectAllocation, etc.)
- RewardsManager uses REO for eligibility
- Governance controls all components

**Current State:**
- IA not deployed yet
- RM self-mints (traditional flow)
- REO ready to integrate when IA deploys

---

## Legend

### Diagram Symbols

```mermaid
graph LR
    DEPLOYED[Deployed/Active]
    PLANNED[Planned/Future]
    GOVERNANCE[Governance Action Required]
    CRITICAL[Critical/Alert]

    style DEPLOYED fill:#bfb,stroke:#333,stroke-width:2px
    style PLANNED fill:#ddd,stroke:#333,stroke-width:1px,stroke-dasharray: 5 5
    style GOVERNANCE fill:#faa,stroke:#333,stroke-width:2px
    style CRITICAL fill:#f99,stroke:#333,stroke-width:2px
```

**Colors:**
- 🟢 **Green:** Deployed, active, success
- 🔵 **Blue:** Protocol contracts (RM, GT)
- 🟡 **Yellow:** Administrative (ProxyAdmin, config)
- 🔴 **Red:** Governance actions, critical, alerts
- 🟣 **Purple:** Governance multi-sig
- ⚪ **Gray/Dashed:** Planned, future, not yet deployed

---

## Usage Notes

These diagrams can be:
- Embedded in documentation (GitHub renders Mermaid)
- Exported to images for presentations
- Updated as architecture evolves
- Used for governance proposals
- Included in audit reports

To render locally:
- Use Mermaid Live Editor: https://mermaid.live/
- Use VS Code with Mermaid extension
- Use GitHub/GitLab (renders automatically)

---

## References

- Mermaid Documentation: https://mermaid.js.org/
- Deployment Sequence: `REODeploymentSequence.md`
- Governance Workflow: `GovernanceWorkflow.md`
- Verification Checklists: `VerificationChecklists.md`
