# Multi-Package Deployment Architecture

This directory contains the orchestrator for deploying Graph Protocol contracts across multiple packages.

## 🏗️ Architecture

```
packages/
├── contracts/
│   ├── contracts/          # Contract sources (Solidity 0.7.6, OZ v3)
│   ├── artifacts/          # Compiled artifacts
│   └── deploy/            # Contracts deployment sub-project
├── issuance/
│   ├── contracts/          # Contract sources (Solidity 0.8.27, OZ v5)
│   ├── artifacts/          # Compiled artifacts
│   └── deploy/            # Issuance deployment sub-project
└── deploy/                # Main orchestrator (this directory)
```

## 🎯 Key Benefits

✅ **Clean Separation**: Each package has its own deployment project
✅ **No Version Conflicts**: OZ v3 and v5 stay in separate projects
✅ **Proper Path Resolution**: Each project resolves its own imports correctly
✅ **Independent Testing**: Each deployment can be tested separately
✅ **Orchestrated Deployment**: Coordinated multi-package deployments

## 🚀 Usage

### Deploy All Packages (Orchestrated)

```bash
# Deploy to local hardhat network
npm run deploy:local

# Deploy to sepolia testnet
npm run deploy:sepolia

# Deploy to mainnet
npm run deploy:mainnet
```

### Deploy Individual Packages

```bash
# Deploy only contracts package
npm run deploy:contracts

# Deploy only issuance package
npm run deploy:issuance
```

### Clean All Deployments

```bash
npm run clean
```

## 📋 Deployment Flow

1. **Contracts Package**: Deploys RewardsManager and related contracts
2. **Issuance Package**: Deploys IssuanceAllocator system with proxies
3. **Integration**: Configures cross-package interactions

## 🔧 Sub-Project Structure

Each sub-project (`contracts/deploy/` and `issuance/deploy/`) contains:

- `package.json` - Dependencies and scripts
- `hardhat.config.js` - Hardhat configuration
- `scripts/copyArtifacts.js` - Copy parent package artifacts
- `ignition/modules/` - Hardhat Ignition deployment modules
- `ignition/parameters/` - Network-specific parameters

## 🎯 Design Principles

- **Single Responsibility**: Each sub-project handles one package
- **Clean Dependencies**: No cross-package artifact conflicts
- **Orchestration**: Main deploy package coordinates everything
- **Maintainability**: Clear separation makes debugging easy
- **Scalability**: Easy to add more packages

## Issuance integration targets (Active)

- issuance/ServiceQualityOracleActive: asserts RewardsManager.serviceQualityOracle() matches the supplied SQO
- issuance/IssuanceAllocatorActive: asserts RewardsManager.issuanceAllocator() matches the supplied IA
- issuance/IssuanceAllocatorMinter: asserts GraphToken.isMinter(IA)

All targets are assertion-based and idempotent: they revert until governance calls have been executed.
