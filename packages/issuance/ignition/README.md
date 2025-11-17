# Issuance Ignition Deployments

This directory contains Hardhat Ignition deployment modules for The Graph Issuance contracts.

## Overview

The Ignition deployment system provides a declarative way to deploy and manage smart contracts with built-in support for:

- Transparent upgradeable proxies
- Multi-network deployments
- Configuration management
- Deployment verification
- Idempotent deployments (can be re-run safely)

## Contracts

The issuance package includes three main contracts:

1. **IssuanceAllocator** - Central distribution hub for token issuance
2. **DirectAllocation** - Simple target contract for receiving and distributing allocated tokens
3. **RewardsEligibilityOracle** - Oracle-based eligibility system for indexer rewards

All contracts are deployed using OpenZeppelin's TransparentUpgradeableProxy pattern.

## Directory Structure

```
ignition/
├── configs/           # Network-specific configuration files
│   ├── issuance.default.json5
│   ├── issuance.localNetwork.json5
│   ├── issuance.arbitrumSepolia.json5
│   └── issuance.arbitrumOne.json5
├── deployments/       # Deployment artifacts (generated)
└── modules/           # Deployment modules
    ├── proxy/         # Proxy deployment utilities
    ├── IssuanceAllocator.ts
    ├── DirectAllocation.ts
    ├── RewardsEligibilityOracle.ts
    ├── deploy.ts      # Main deployment module
    └── index.ts       # Module exports
```

## Usage

### Deploy All Contracts

Deploy all issuance contracts to a network:

```bash
# Deploy to local network
npx hardhat ignition deploy ignition/modules/deploy.ts --network localhost

# Deploy to Arbitrum Sepolia testnet
npx hardhat ignition deploy ignition/modules/deploy.ts --network arbitrumSepolia

# Deploy to Arbitrum One mainnet
npx hardhat ignition deploy ignition/modules/deploy.ts --network arbitrumOne
```

### Deploy Individual Contracts

Deploy a single contract:

```bash
# Deploy only IssuanceAllocator
npx hardhat ignition deploy ignition/modules/IssuanceAllocator.ts --network localhost

# Deploy only DirectAllocation
npx hardhat ignition deploy ignition/modules/DirectAllocation.ts --network localhost

# Deploy only RewardsEligibilityOracle
npx hardhat ignition deploy ignition/modules/RewardsEligibilityOracle.ts --network localhost
```

### Using Custom Configuration

You can override configuration parameters:

```bash
npx hardhat ignition deploy ignition/modules/deploy.ts \
  --network arbitrumSepolia \
  --parameters ignition/configs/issuance.arbitrumSepolia.json5
```

### Verify Contracts

After deployment, verify contracts on block explorers:

```bash
npx hardhat ignition verify <deployment-id>
```

## Configuration

Configuration files are in JSON5 format and support:

- Network-specific parameters
- Global parameters (prefixed with `$global`)
- BigInt values (using `n` suffix)

### Required Parameters

- `graphTokenAddress` - Address of the Graph Token contract

### Optional Parameters

- `issuancePerBlock` - Initial issuance rate (default: 0)
- `eligibilityPeriod` - Eligibility duration in seconds (default: 14 days)
- `oracleUpdateTimeout` - Oracle timeout in seconds (default: 7 days)
- `eligibilityValidationEnabled` - Enable/disable validation (default: false)

## Integration with Horizon

The issuance Ignition modules follow the same patterns as the Horizon deployment:

- Similar directory structure
- Compatible proxy deployment utilities
- Consistent configuration format
- Reusable deployment patterns

You can import and use issuance modules in other packages:

```typescript
import { IssuanceAllocatorModule } from '@graphprotocol/issuance/ignition'
```

## Deployment Artifacts

Deployment artifacts are stored in `ignition/deployments/<deployment-id>/`:

- `deployed_addresses.json` - Deployed contract addresses
- `journal.jsonl` - Deployment execution log
- `artifacts/` - Contract artifacts

## Migration Support

Each contract module includes a migration variant for connecting to existing deployments:

- `MigrateIssuanceAllocatorModule`
- `MigrateDirectAllocationModule`
- `MigrateRewardsEligibilityOracleModule`

Use these when you need to interact with already-deployed contracts.

## Best Practices

1. **Always test on local network first** before deploying to testnets or mainnet
2. **Review configuration files** to ensure correct parameters for each network
3. **Verify contracts** after deployment for transparency
4. **Keep deployment artifacts** in version control for production deployments
5. **Use migration modules** when integrating with existing deployments

## Troubleshooting

### Common Issues

**Issue**: "Cannot find module" errors
**Solution**: Run `pnpm build` to compile contracts and generate artifacts

**Issue**: Deployment fails with "insufficient funds"
**Solution**: Ensure deployer account has enough ETH for gas

**Issue**: "Contract already deployed" errors
**Solution**: Ignition deployments are idempotent; this usually means the deployment succeeded

## Further Reading

- [Hardhat Ignition Documentation](https://hardhat.org/ignition)
- [OpenZeppelin Upgradeable Contracts](https://docs.openzeppelin.com/contracts/5.x/upgradeable)
- [The Graph Protocol Documentation](https://thegraph.com/docs/)
