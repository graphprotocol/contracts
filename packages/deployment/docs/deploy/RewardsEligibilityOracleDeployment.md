# RewardsEligibilityOracle Deployment

Deployment guide for RewardsEligibilityOracle (REO).

**Related:**

- [Contract specification](../../../issuance/contracts/eligibility/RewardsEligibilityOracle.md) - architecture, operations, troubleshooting
- [GovernanceWorkflow.md](./GovernanceWorkflow.md) - Safe TX execution

## Prerequisites

- GraphToken deployed
- Controller deployed (provides governor, pause guardian addresses)
- `NetworkOperator` entry in issuance address book (for OPERATOR_ROLE)

## Deployment Scripts

All scripts are idempotent.

| Script                                                                                  | Tag                                       | Actor               | Purpose                                |
| --------------------------------------------------------------------------------------- | ----------------------------------------- | ------------------- | -------------------------------------- |
| [01_deploy.ts](../../deploy/rewards/eligibility/01_deploy.ts)                           | `rewards-eligibility-deploy`              | Deployer            | Deploy proxy + implementation          |
| [02_upgrade.ts](../../deploy/rewards/eligibility/02_upgrade.ts)                         | `rewards-eligibility-upgrade`             | Governance          | Upgrade implementation                 |
| [04_configure.ts](../../deploy/rewards/eligibility/04_configure.ts)                     | `rewards-eligibility-configure`           | Deployer/Governance | Set parameters                         |
| [05_transfer_governance.ts](../../deploy/rewards/eligibility/05_transfer_governance.ts) | `rewards-eligibility-transfer-governance` | Deployer            | Grant roles, transfer to governance    |
| [06_integrate.ts](../../deploy/rewards/eligibility/06_integrate.ts)                     | `rewards-eligibility-integrate`           | Governance          | Connect to RewardsManager              |
| [09_complete.ts](../../deploy/rewards/eligibility/09_complete.ts)                       | `rewards-eligibility`                     | -                   | Aggregate (deploy, upgrade, configure) |

### Quick Start

```bash
# Full deployment (new install)
pnpm hardhat deploy --tags rewards-eligibility --network <network>

# Individual steps
pnpm hardhat deploy --tags rewards-eligibility-deploy --network <network>
pnpm hardhat deploy --tags rewards-eligibility-configure --network <network>
pnpm hardhat deploy --tags rewards-eligibility-transfer-governance --network <network>
pnpm hardhat deploy --tags rewards-eligibility-integrate --network <network>
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

- [ ] `RewardsManager.getRewardsEligibilityOracle()` returns REO address

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
