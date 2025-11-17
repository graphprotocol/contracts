# Issuance Package Deployment Guide

This document provides a comprehensive guide for deploying the Graph Issuance contracts using Hardhat Ignition.

## Overview

The issuance package now includes a complete Hardhat Ignition deployment system that is:

- **Compatible with Horizon**: Uses the same patterns and utilities as the Horizon package
- **Modular**: Each contract has its own deployment module
- **Configurable**: Network-specific configuration files
- **Upgradeable**: All contracts use TransparentUpgradeableProxy pattern
- **Production-ready**: Includes verification, migration support, and deployment tracking

## What Was Created

### Directory Structure

```
packages/issuance/
├── ignition/
│   ├── modules/
│   │   ├── proxy/
│   │   │   ├── implementation.ts          # Implementation deployment utility
│   │   │   ├── TransparentUpgradeableProxy.ts  # Proxy deployment utilities
│   │   │   └── utils.ts                   # Helper functions
│   │   ├── IssuanceAllocator.ts           # IssuanceAllocator deployment
│   │   ├── DirectAllocation.ts            # DirectAllocation deployment
│   │   ├── RewardsEligibilityOracle.ts    # RewardsEligibilityOracle deployment
│   │   ├── deploy.ts                      # Main deployment module
│   │   └── index.ts                       # Module exports
│   ├── configs/
│   │   ├── issuance.default.json5         # Default configuration
│   │   ├── issuance.localNetwork.json5    # Local network config
│   │   ├── issuance.arbitrumSepolia.json5 # Testnet config
│   │   └── issuance.arbitrumOne.json5     # Mainnet config
│   ├── examples/
│   │   └── deploy-example.ts              # Example deployment script
│   ├── deployments/                       # Deployment artifacts (generated)
│   └── README.md                          # Detailed documentation
├── addresses.json                         # Deployed contract addresses
└── DEPLOYMENT.md                          # This file
```

### Key Features

1. **Proxy Pattern**: All contracts deployed with TransparentUpgradeableProxy
2. **Migration Support**: Each module includes a migration variant for existing deployments
3. **Configuration Management**: JSON5 config files with network-specific parameters
4. **Deployment Tracking**: Addresses stored in `addresses.json`
5. **Example Scripts**: Ready-to-use deployment examples

## Quick Start

### 1. Install Dependencies

```bash
cd packages/issuance
pnpm install
```

### 2. Compile Contracts

```bash
pnpm compile
```

### 3. Configure Deployment

Edit the appropriate config file in `ignition/configs/`:

```json5
{
  $global: {
    graphTokenAddress: '0x...', // Required: Graph Token address
  },
}
```

### 4. Deploy

```bash
# Deploy to local network
npx hardhat ignition deploy ignition/modules/deploy.ts --network localhost

# Deploy to testnet
npx hardhat ignition deploy ignition/modules/deploy.ts \
  --network arbitrumSepolia \
  --parameters ignition/configs/issuance.arbitrumSepolia.json5

# Deploy to mainnet
npx hardhat ignition deploy ignition/modules/deploy.ts \
  --network arbitrumOne \
  --parameters ignition/configs/issuance.arbitrumOne.json5
```

### 5. Verify Contracts

```bash
npx hardhat ignition verify <deployment-id>
```

## Deployment Modules

### IssuanceAllocator

Central distribution hub for token issuance.

**Module**: `ignition/modules/IssuanceAllocator.ts`

**Exports**:

- `IssuanceAllocator` - Proxy contract
- `IssuanceAllocatorImplementation` - Implementation contract
- `IssuanceAllocatorProxyAdmin` - ProxyAdmin contract

**Migration Module**: `MigrateIssuanceAllocatorModule`

### DirectAllocation

Simple target contract for receiving and distributing allocated tokens.

**Module**: `ignition/modules/DirectAllocation.ts`

**Exports**:

- `DirectAllocation` - Proxy contract
- `DirectAllocationImplementation` - Implementation contract
- `DirectAllocationProxyAdmin` - ProxyAdmin contract

**Migration Module**: `MigrateDirectAllocationModule`

### RewardsEligibilityOracle

Oracle-based eligibility system for indexer rewards.

**Module**: `ignition/modules/RewardsEligibilityOracle.ts`

**Exports**:

- `RewardsEligibilityOracle` - Proxy contract
- `RewardsEligibilityOracleImplementation` - Implementation contract
- `RewardsEligibilityOracleProxyAdmin` - ProxyAdmin contract

**Migration Module**: `MigrateRewardsEligibilityOracleModule`

## Configuration Parameters

### Global Parameters

- `graphTokenAddress` (required) - Address of the Graph Token contract

### IssuanceAllocator Parameters

- `issuancePerBlock` - Initial issuance rate (default: 0)

### RewardsEligibilityOracle Parameters

- `eligibilityPeriod` - Eligibility duration in seconds (default: 14 days)
- `oracleUpdateTimeout` - Oracle timeout in seconds (default: 7 days)
- `eligibilityValidationEnabled` - Enable/disable validation (default: false)

## Address Book and Toolshed Integration

### Address Book Format

Contract addresses are stored in `addresses.json` using chain IDs (matching Horizon's format):

```json
{
  "42161": {
    "IssuanceAllocator": {
      "address": "0x...",
      "proxy": "transparent",
      "proxyAdmin": "0x...",
      "implementation": "0x..."
    }
  }
}
```

### Syncing Deployment Addresses

After deploying with Ignition, sync addresses to the main address book:

```bash
npx ts-node scripts/sync-addresses.ts <deployment-id> <chain-id>

# Example:
npx ts-node scripts/sync-addresses.ts issuance-arbitrumSepolia 421614
```

### Using Deployed Contracts via Toolshed

The issuance package integrates with `@graphprotocol/toolshed` for easy contract loading:

```typescript
import { connectGraphIssuance } from '@graphprotocol/toolshed'
import { ethers } from 'ethers'

// Connect to deployed contracts
const provider = new ethers.JsonRpcProvider('https://...')
const contracts = connectGraphIssuance(42161, provider)

// Use contracts
const issuanceRate = await contracts.IssuanceAllocator.issuancePerBlock()
```

## Integration with Other Packages

The issuance package can be imported and used in other packages:

```typescript
// Import Ignition modules
import {
  GraphIssuanceModule,
  IssuanceAllocatorModule,
  DirectAllocationModule,
  RewardsEligibilityOracleModule,
} from '@graphprotocol/issuance/ignition'

// Import deployed contract instances via toolshed
import { connectGraphIssuance } from '@graphprotocol/toolshed'
```

## Next Steps

1. **Test Deployment**: Deploy to a local network first
2. **Configure Parameters**: Update config files for your network
3. **Deploy to Testnet**: Test on Arbitrum Sepolia
4. **Verify Contracts**: Ensure contracts are verified on block explorers
5. **Deploy to Mainnet**: Deploy to production when ready

## Additional Resources

- [Ignition README](ignition/README.md) - Detailed Ignition documentation
- [Example Script](ignition/examples/deploy-example.ts) - Programmatic deployment example
- [Hardhat Ignition Docs](https://hardhat.org/ignition) - Official documentation
