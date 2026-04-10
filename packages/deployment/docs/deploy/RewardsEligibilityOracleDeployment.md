# RewardsEligibilityOracle Deployment

Deployment guide for RewardsEligibilityOracle (REO).

**Related:**

- [Contract specification](../../../issuance/contracts/eligibility/RewardsEligibilityOracle.md) - architecture, operations, troubleshooting
- [GovernanceWorkflow.md](../GovernanceWorkflow.md) - Safe TX execution

## Prerequisites

- GraphToken deployed
- Controller deployed (provides governor, pause guardian addresses)
- `NetworkOperator` entry in issuance address book (for OPERATOR_ROLE)

## Deployment Scripts

All scripts are idempotent.

| Script                                                                                  | Tag                                       | Actor               | Purpose                                   |
| --------------------------------------------------------------------------------------- | ----------------------------------------- | ------------------- | ----------------------------------------- |
| [01_deploy.ts](../../deploy/rewards/eligibility/01_deploy.ts)                           | `RewardsEligibilityOracle{A,B}:deploy`    | Deployer            | Deploy proxy + implementation             |
| [02_upgrade.ts](../../deploy/rewards/eligibility/02_upgrade.ts)                         | `RewardsEligibilityOracle{A,B}:upgrade`   | Governance          | Upgrade implementation                    |
| [04_configure.ts](../../deploy/rewards/eligibility/04_configure.ts)                     | `RewardsEligibilityOracle{A,B}:configure` | Deployer/Governance | Set parameters                            |
| [05_transfer_governance.ts](../../deploy/rewards/eligibility/05_transfer_governance.ts) | `RewardsEligibilityOracle{A,B}:transfer`  | Deployer            | Revoke deployer role, transfer ProxyAdmin |
| [09_end.ts](../../deploy/rewards/eligibility/09_end.ts)                                 | `RewardsEligibilityOracle{A,B}`           | -                   | Aggregate (deploy, upgrade, configure)    |

Integration with `RewardsManager` is **not** a per-component lifecycle action. Only one of REO-A or REO-B is integrated at a time, which is a goal-level decision. Use the GIP-0088 activation tag instead:

```bash
pnpm hardhat deploy --tags GIP-0088:eligibility-integrate --network <network>
```

The testnet `MockRewardsEligibilityOracle` does have its own `06_integrate.ts` because it has no goal-tag equivalent.

### Quick Start

```bash
# Read-only status (no --tags = no mutations)
pnpm hardhat deploy --tags RewardsEligibilityOracleA --network <network>

# Individual steps
pnpm hardhat deploy --tags RewardsEligibilityOracleA,deploy --network <network>
pnpm hardhat deploy --tags RewardsEligibilityOracleA,configure --network <network>
pnpm hardhat deploy --tags RewardsEligibilityOracleA,transfer --network <network>

# Integrate (only one of A/B at a time — goal-level)
pnpm hardhat deploy --tags GIP-0088:eligibility-integrate --network <network>
```

## Verification Checklist

### Deployment

- [ ] Contract deployed via transparent proxy
- [ ] Implementation verified on block explorer

### Access Control

- [ ] Governor has GOVERNOR_ROLE
- [ ] Deployer does NOT have GOVERNOR_ROLE
- [ ] Pause guardian has PAUSE_ROLE
- [ ] Operator has OPERATOR_ROLE

### Configuration

- [ ] `eligibilityPeriod` = 14 days (1,209,600 seconds)
- [ ] `oracleUpdateTimeout` = 7 days (604,800 seconds)

### Integration

- [ ] `RewardsManager.getProviderEligibilityOracle()` returns REO address

## Configuration Parameters

| Parameter                      | Default | Purpose                                 |
| ------------------------------ | ------- | --------------------------------------- |
| `eligibilityPeriod`            | 14 days | How long indexer eligibility lasts      |
| `oracleUpdateTimeout`          | 7 days  | Failsafe timeout for oracle updates     |
| `eligibilityValidationEnabled` | false   | Global enable/disable (set by operator) |

## Roles

| Role          | Purpose                                   | Assigned To                |
| ------------- | ----------------------------------------- | -------------------------- |
| GOVERNOR_ROLE | Grant/revoke operator, governance actions | Protocol governance        |
| OPERATOR_ROLE | Configure parameters, manage oracle roles | Network operator           |
| ORACLE_ROLE   | Renew indexer eligibility                 | Oracle services (multiple) |
| PAUSE_ROLE    | Pause contract                            | Pause guardian             |

## Post-Deployment

After deployment completes, the **operator** must:

1. Grant ORACLE_ROLE to oracle services
2. Verify oracles are renewing eligibility
3. Enable eligibility validation when ready

See [Contract specification - Operations](../../../issuance/contracts/eligibility/RewardsEligibilityOracle.md#operations) for detailed operational guidance, monitoring, and troubleshooting.
