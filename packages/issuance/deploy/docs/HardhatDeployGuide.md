# Hardhat-Deploy Deployment Guide

## Overview

This package uses [hardhat-deploy](https://github.com/wighawag/hardhat-deploy) for deploying issuance contracts. The deployment is split into numbered scripts that execute in sequence with clear dependencies.

## Quick Start

### Prerequisites

1. **Install dependencies**

   ```bash
   pnpm install
   ```

2. **Create GraphToken deployment artifact** for your network

   ```bash
   mkdir -p deployments/<network-name>
   cat > deployments/<network-name>/GraphToken.json <<EOF
   {
     "address": "0x...",
     "abi": []
   }
   EOF
   ```

### Deploy All Contracts

```bash
# Deploy everything
pnpm hardhat deploy --tags issuance --network <network-name>

# Export to address book
pnpm hardhat run scripts/export-addresses.ts --network <network-name>
```

## Deployment Scripts

### Execution Order

1. **00_proxy_admin.ts** - Deploy GraphIssuanceProxyAdmin (OpenZeppelin ProxyAdmin)
2. **01_issuance_allocator.ts** - Deploy IssuanceAllocator with TransparentUpgradeableProxy
3. **02_pilot_allocation.ts** - Deploy PilotAllocation with TransparentUpgradeableProxy
4. **03_rewards_eligibility_oracle.ts** - Deploy RewardsEligibilityOracle with TransparentUpgradeableProxy
5. **04_verify_governance.ts** - Verify GOVERNOR_ROLE is assigned to all contracts

### Tags

Use tags for selective deployment:

```bash
# Deploy only ProxyAdmin
pnpm hardhat deploy --tags proxy-admin --network <network>

# Deploy core contracts (without ownership acceptance)
pnpm hardhat deploy --tags issuance-core --network <network>

# Deploy specific contract
pnpm hardhat deploy --tags issuance-allocator --network <network>

# Run only governance operations
pnpm hardhat deploy --tags accept-ownership --network <network>
```

Available tags:

- `proxy-admin` - GraphIssuanceProxyAdmin only
- `issuance-allocator` - IssuanceAllocator deployment
- `pilot-allocation` - PilotAllocation deployment
- `rewards-eligibility` - RewardsEligibilityOracle deployment
- `issuance-core` - All core contracts (excludes governance ops)
- `accept-ownership` - Governance ownership acceptance
- `issuance` - Full deployment including governance

## Network Configuration

### Named Accounts

Configure in [hardhat.config.ts](../hardhat.config.ts):

```typescript
namedAccounts: {
  deployer: {
    default: 0,  // Account that deploys and pays gas
  },
  governor: {
    default: 1,  // Account that owns contracts after acceptance
  },
}
```

### Network-Specific Accounts

Override per network:

```typescript
namedAccounts: {
  deployer: {
    default: 0,
    arbitrumSepolia: '0x...',  // Specific deployer for testnet
  },
  governor: {
    default: 1,
    arbitrumOne: '0x...',       // Governance multisig for mainnet
  },
}
```

## Deployment Artifacts

After deployment, artifacts are stored in `deployments/<network>/`:

```
deployments/arbitrumSepolia/
├── GraphIssuanceProxyAdmin.json
├── IssuanceAllocator.json
├── IssuanceAllocator_Implementation.json
├── IssuanceAllocator_Proxy.json
├── PilotAllocation.json
├── PilotAllocation_Implementation.json
├── PilotAllocation_Proxy.json
├── RewardsEligibilityOracle.json
├── RewardsEligibilityOracle_Implementation.json
└── RewardsEligibilityOracle_Proxy.json
```

Each JSON contains:

- `address` - Deployed contract address
- `abi` - Contract ABI
- `implementation` - Implementation address (for proxies)
- `transactionHash` - Deployment transaction
- Full deployment metadata

## Address Book Integration

Export deployments to address book format:

```bash
pnpm hardhat run scripts/export-addresses.ts --network <network>
```

This creates `addresses.json`:

```json
{
  "42161": {
    "GraphIssuanceProxyAdmin": {
      "address": "0x..."
    },
    "IssuanceAllocator": {
      "address": "0x...",
      "implementation": "0x...",
      "proxyAdmin": "0x...",
      "proxy": "transparent"
    },
    "PilotAllocation": { ... },
    "RewardsEligibilityOracle": { ... }
  }
}
```

## Testing Deployments

### Local Hardhat Network

```bash
# Terminal 1: Start local node
pnpm hardhat node

# Terminal 2: Deploy
pnpm hardhat deploy --tags issuance --network localhost

# Verify deployment
pnpm hardhat test --network localhost
```

### Testnet Fork

```bash
# Fork arbitrum-sepolia
pnpm hardhat deploy --tags issuance --network arbitrumSepolia --fork

# Or use environment variable
FORK=true pnpm hardhat deploy --tags issuance --network arbitrumSepolia
```

## Upgrading Contracts

### Process

1. **Deploy new implementation** (hardhat-deploy detects changes automatically)

   ```bash
   pnpm hardhat deploy --tags issuance-allocator --network <network>
   ```

2. **Verify new implementation**

   ```bash
   pnpm hardhat verify --network <network> <implementation-address>
   ```

3. **Prepare governance proposal**

   ```bash
   # Use ProxyAdmin to upgrade
   # GraphIssuanceProxyAdmin.upgrade(proxy, newImplementation)
   ```

4. **Execute via governance**

### Upgrade Detection

Hardhat-deploy automatically:

- Detects bytecode changes
- Deploys new implementation
- Keeps existing proxy
- Does NOT automatically upgrade proxy (requires governance)

## Common Operations

### Check Deployment Status

```bash
# List all deployments for network
pnpm hardhat deployments --network <network>

# Get specific deployment info
pnpm hardhat deployments get IssuanceAllocator --network <network>
```

### Verify Contracts

```bash
# Verify all deployments
pnpm hardhat etherscan-verify --network <network>

# Verify specific contract
pnpm hardhat verify --network <network> <address>
```

### Reset Deployments

```bash
# Clear deployment cache for network
rm -rf deployments/<network>

# Clear all local deployments
rm -rf deployments/localhost
```

## Troubleshooting

### "Cannot find artifact" errors

Ensure contracts are compiled:

```bash
cd ../  # Go to parent issuance package
pnpm build
cd deploy
```

### GraphToken.json not found

Create the deployment artifact:

```bash
mkdir -p deployments/<network>
echo '{"address":"0x...","abi":[]}' > deployments/<network>/GraphToken.json
```

### Ownership acceptance fails

Ensure governor account has enough ETH:

```bash
# Check balance
pnpm hardhat run --network <network> -e "
  console.log(await ethers.provider.getBalance((await getNamedAccounts()).governor))
"
```

## Advanced Usage

### Custom Deployment Script

```typescript
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre
  const { deploy, execute } = deployments
  const { deployer, governor } = await getNamedAccounts()

  await deploy('MyContract', {
    from: deployer,
    args: [param1, param2],
    log: true,
  })
}

func.tags = ['my-contract']
func.dependencies = ['proxy-admin']

export default func
```

### Using Fixtures in Tests

```typescript
import { deployments } from 'hardhat'

describe('My Test', () => {
  beforeEach(async () => {
    // Deploy all issuance contracts
    await deployments.fixture(['issuance'])

    // Get deployed contracts
    const issuanceAllocator = await deployments.get('IssuanceAllocator')
  })
})
```

## References

- [hardhat-deploy documentation](https://github.com/wighawag/hardhat-deploy)
- [Deployment scripts](../deploy/)
- [Test suite](../test/deployment.test.ts)
- [Address export script](../scripts/export-addresses.ts)
