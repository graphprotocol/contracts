# Issuance Deployment

Component-only deployment for Graph Issuance contracts using hardhat-deploy.

## Contracts

This package deploys:

- **IssuanceAllocator** - Token allocation contract with role-based access control
- **PilotAllocation** - Direct token allocation (using DirectAllocation implementation)
- **RewardsEligibilityOracle** - Oracle for rewards eligibility validation
- **GraphIssuanceProxyAdmin** - Shared ProxyAdmin for all issuance proxies

All contracts use OpenZeppelin's TransparentUpgradeableProxy pattern.

## Quick Start

### Prerequisites

Create a GraphToken deployment artifact for your network:

```bash
mkdir -p deployments/<network>
echo '{"address":"0x...","abi":[]}' > deployments/<network>/GraphToken.json
```

### Deploy

```bash
# Deploy all issuance contracts
pnpm hardhat deploy --tags issuance --network <network>

# Deploy specific components
pnpm hardhat deploy --tags issuance-allocator --network <network>
pnpm hardhat deploy --tags pilot-allocation --network <network>
pnpm hardhat deploy --tags rewards-eligibility --network <network>
```

### Test

```bash
# Run deployment tests
pnpm test:self

# Run with coverage
pnpm test:coverage:self
```

## Deployment Scripts

Located in `deploy/`:

- `00_graph_token.ts` - Test fixture (local networks only)
- `00_proxy_admin.ts` - Deploy GraphIssuanceProxyAdmin
- `01_issuance_allocator.ts` - Deploy IssuanceAllocator with proxy
- `02_pilot_allocation.ts` - Deploy PilotAllocation with proxy
- `03_rewards_eligibility_oracle.ts` - Deploy RewardsEligibilityOracle with proxy
- `04_verify_governance.ts` - Verify governor role assignments

### Optional Script

- `00_rewards_manager.ts` - Legacy RewardsManager upgrades (separate from issuance)

## Tags

- `issuance` - Deploy all issuance contracts (GraphIssuanceProxyAdmin + all 3 contracts)
- `issuance-core` - Deploy the 3 main contracts (IA, Pilot, REO)
- `issuance-allocator` - Deploy IssuanceAllocator only
- `pilot-allocation` - Deploy PilotAllocation only
- `rewards-eligibility` - Deploy RewardsEligibilityOracle only
- `verify-governance` - Verify governor roles only
- `proxy-admin` - Deploy GraphIssuanceProxyAdmin only

## Architecture

### Access Control

These contracts use **role-based access control** (OpenZeppelin AccessControl), not ownership:

- `GOVERNOR_ROLE` - Full administrative access
- `PAUSE_ROLE` - Emergency pause capability
- `OPERATOR_ROLE` - Operational tasks

During deployment, the governor address (from `namedAccounts`) receives the `GOVERNOR_ROLE`.

### Proxy Pattern

All contracts use TransparentUpgradeableProxy:

- **Shared Admin**: All proxies use `GraphIssuanceProxyAdmin`
- **Atomic Initialization**: Contracts initialized during proxy deployment
- **Governance Upgrades**: Only ProxyAdmin owner (governor) can upgrade

### GraphToken Dependency

All contracts require GraphToken address via:

- Immutable constructor parameter on implementations
- Provided via `deployments/<network>/GraphToken.json`

## Deployment Flow

1. **Deploy ProxyAdmin** - Owned by governor
2. **Deploy Implementations** - With GraphToken constructor arg
3. **Deploy Proxies** - Using shared ProxyAdmin, atomic initialization
4. **Verify Governance** - Confirm governor has GOVERNOR_ROLE on all contracts

## Testing

The deployment test suite validates:

- ✅ Proxy deployment and initialization
- ✅ Governor role assignment
- ✅ Shared ProxyAdmin architecture
- ✅ Distinct implementation addresses
- ✅ Initialization protection (cannot re-initialize)

Run tests: `pnpm test:self`

## Network Configuration

Configure networks in `hardhat.config.ts` or use environment variables.

Named accounts (from toolshed base config):

- `deployer` - Account 0 (pays gas)
- `governor` - Account 1 (receives admin roles)

## Export Addresses

After deployment, export addresses:

```bash
pnpm hardhat run scripts/export-addresses.ts --network <network>
```

Creates `addresses.json` with all deployed contract addresses.

## Upgrades

Upgrades must be done via governance through the ProxyAdmin:

```bash
# Deploy new implementation
pnpm hardhat deploy --tags issuance-allocator --network <network>

# Upgrade via ProxyAdmin (governance only)
# Use governance tooling in packages/deploy/ for Safe transactions
```

## Documentation

- `test/deployment.test.ts` - Reference for deployment validation
- `docs/` - Extended deployment guides and architecture docs
- `deploy/*.ts` - Each script has inline documentation

## What This Package Does NOT Provide

This is component-only deployment. Cross-package orchestration belongs in `packages/deploy/`:

- ❌ Governance transaction generation
- ❌ Safe batch builders
- ❌ Integration with RewardsManager
- ❌ Checkpoint/verification modules
- ❌ Multi-package coordination

## Status

✅ Production-ready for component deployment
✅ All deployment tests passing (14/14)
✅ Role-based access control verified
✅ Shared ProxyAdmin architecture validated
