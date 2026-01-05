# Issuance Deploy Scripts

This directory contains hardhat-deploy scripts for deploying and managing issuance contracts.

## Architecture

The deployment follows a structured hierarchy using hardhat-deploy conventions:

```
GraphIssuanceProxyAdmin (ProxyAdmin)
├── IssuanceAllocator (Implementation + TransparentUpgradeableProxy)
├── PilotAllocation (DirectAllocation Implementation + TransparentUpgradeableProxy)
└── RewardsEligibilityOracle (Implementation + TransparentUpgradeableProxy)
```

## Deployment Scripts

### Core Contracts

- **[00_proxy_admin.ts](./00_proxy_admin.ts)** - Deploy GraphIssuanceProxyAdmin
  - Tags: `proxy-admin`, `issuance-core`
  - Deploys OpenZeppelin ProxyAdmin owned by governor
  - Reuses existing deployment if already present

- **[01_issuance_allocator.ts](./01_issuance_allocator.ts)** - Deploy IssuanceAllocator
  - Tags: `issuance-allocator`, `issuance-core`, `issuance`
  - Dependencies: `proxy-admin`
  - Deploys implementation + transparent proxy with atomic initialization

- **[02_pilot_allocation.ts](./02_pilot_allocation.ts)** - Deploy PilotAllocation
  - Tags: `pilot-allocation`, `issuance-core`, `issuance`
  - Dependencies: `proxy-admin`
  - Uses DirectAllocation as implementation contract
  - Deploys implementation + transparent proxy with atomic initialization

- **[03_rewards_eligibility_oracle.ts](./03_rewards_eligibility_oracle.ts)** - Deploy RewardsEligibilityOracle
  - Tags: `rewards-eligibility`, `issuance-core`, `issuance`
  - Dependencies: `proxy-admin`
  - Deploys implementation + transparent proxy with atomic initialization

### Governance Operations

- **[04_accept_ownership.ts](./04_accept_ownership.ts)** - Accept ownership of all contracts
  - Tags: `accept-ownership`, `issuance-governance`, `issuance`
  - Dependencies: `issuance-core`
  - Idempotent ownership acceptance for all issuance contracts
  - Runs at the end of deployment sequence

### Legacy Contracts

- **[00_rewards_manager.ts](./00_rewards_manager.ts)** - Upgrade existing RewardsManager
  - Tags: `rewards-manager`
  - Manages upgrades to legacy GraphProxy-based RewardsManager
  - Uses GraphLegacyProxyAdmin

## Usage

### Full Deployment

Deploy all issuance contracts in sequence:

```bash
pnpm hardhat deploy --tags issuance --network arbitrumSepolia
```

This will:
1. Deploy GraphIssuanceProxyAdmin (if not exists)
2. Deploy IssuanceAllocator with proxy
3. Deploy PilotAllocation with proxy
4. Deploy RewardsEligibilityOracle with proxy
5. Accept ownership of all contracts as governor

### Partial Deployment

Deploy specific contracts:

```bash
# Deploy only ProxyAdmin
pnpm hardhat deploy --tags proxy-admin --network arbitrumSepolia

# Deploy only IssuanceAllocator
pnpm hardhat deploy --tags issuance-allocator --network arbitrumSepolia

# Run only governance operations
pnpm hardhat deploy --tags accept-ownership --network arbitrumSepolia
```

### Deploy Core Contracts Without Governance

Deploy contracts but skip ownership acceptance:

```bash
pnpm hardhat deploy --tags issuance-core --network arbitrumSepolia
```

## Requirements

### Named Accounts

Configure in [hardhat.config.ts](../hardhat.config.ts):

- `deployer` (account 0) - Deploys contracts and pays gas
- `governor` (account 1) - Owns ProxyAdmin and contracts after ownership acceptance

### Deployment Dependencies

Each network must have a `deployments/<network>/GraphToken.json` file:

```json
{
  "address": "0x...",
  "abi": [...]
}
```

You can create this manually or copy from an existing deployment:

```bash
# Create deployments directory for your network
mkdir -p deployments/arbitrumSepolia

# Create GraphToken deployment JSON
cat > deployments/arbitrumSepolia/GraphToken.json <<EOF
{
  "address": "0x...",
  "abi": []
}
EOF
```

## Deployment Artifacts

After deployment, hardhat-deploy creates:

```
deployments/<network>/
├── GraphIssuanceProxyAdmin.json           # ProxyAdmin deployment
├── IssuanceAllocator.json                 # Proxy deployment
├── IssuanceAllocator_Implementation.json  # Implementation deployment
├── IssuanceAllocator_Proxy.json          # Proxy artifact
├── PilotAllocation.json                   # Proxy deployment
├── PilotAllocation_Implementation.json    # Implementation deployment
├── PilotAllocation_Proxy.json            # Proxy artifact
├── RewardsEligibilityOracle.json         # Proxy deployment
├── RewardsEligibilityOracle_Implementation.json
└── RewardsEligibilityOracle_Proxy.json
```

Each JSON file contains:
- `address` - Deployed contract address
- `abi` - Contract ABI
- `implementation` - Implementation address (for proxies)
- `transactionHash` - Deployment transaction
- `receipt` - Transaction receipt
- Other deployment metadata

## Upgrade Workflow

Upgrades are handled via governance using the ProxyAdmin:

1. Deploy new implementation (hardhat-deploy detects code changes automatically)
2. Verify new implementation
3. Governance proposal to upgrade via ProxyAdmin.upgrade()
4. Execute upgrade transaction

See [tasks/upgrade-rewards-manager.ts](../tasks/upgrade-rewards-manager.ts) for upgrade task examples.

## Security Notes

### Atomic Initialization

All contracts use atomic initialization during proxy deployment:
- Initialization data encoded via `proxy.execute.init`
- Passed to TransparentUpgradeableProxy constructor
- Prevents front-running attacks
- No window for unauthorized initialization

### Two-Step Ownership

All contracts use OpenZeppelin's Ownable2Step:
1. Contract initialized with governor as pending owner
2. Governor must explicitly call `acceptOwnership()`
3. Ownership transfer completes only after acceptance
4. Prevents accidental ownership transfer to wrong address

### Proxy Pattern

Uses OpenZeppelin TransparentUpgradeableProxy:
- Admin (ProxyAdmin) can upgrade implementation
- Admin cannot call implementation functions
- Non-admin accounts can call implementation functions
- Complete separation of concerns

## Testing

Test deployment on local network:

```bash
# Start local node
pnpm hardhat node

# In another terminal, deploy
pnpm hardhat deploy --tags issuance --network localhost
```

## References

- [hardhat-deploy documentation](https://github.com/wighawag/hardhat-deploy)
- [OpenZeppelin Proxy patterns](https://docs.openzeppelin.com/contracts/5.x/api/proxy)
- [Design documentation](../docs/Design.md)
- [Hardhat-deploy vs Ignition comparison](../docs/hardhat-deploy-vs-ignition.md)
