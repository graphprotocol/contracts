# Issuance Package Integration with Horizon Patterns

This document explains how the issuance package aligns with Horizon's deployment and contract interaction patterns.

## Overview

The issuance package now follows the same patterns as Horizon for:

1. **Address Book Format** - Using chain IDs and structured metadata
2. **Toolshed Integration** - Providing easy contract loading utilities
3. **Ignition Deployments** - Using Hardhat Ignition for deployments
4. **Deployment Syncing** - Scripts to sync Ignition artifacts to address book

## Address Book Alignment

### Horizon Format

```json
{
  "42161": {
    "GraphPayments": {
      "address": "0x7Aae8ae011927BC36Cb4d0d3e81f2E6E30daE06D",
      "proxy": "transparent",
      "proxyAdmin": "0x0D065CE83938Ea226c145e9c4a8C95b31aDA3613",
      "implementation": "0x6BC86e5D64C6c4882670804ca7eE4919cCCca86a"
    }
  }
}
```

### Issuance Format (Now Aligned)

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

**Key Points:**

- ✅ Uses chain IDs as keys (42161, 421614, 31337)
- ✅ Stores proxy metadata inline with contract entry
- ✅ Includes `proxy`, `proxyAdmin`, and `implementation` fields
- ✅ Compatible with toolshed's `AddressBook` class

## Toolshed Integration

### Horizon Pattern

```typescript
import { connectGraphHorizon } from '@graphprotocol/toolshed'

const contracts = connectGraphHorizon(42161, provider)
await contracts.GraphPayments.collect(...)
```

### Issuance Pattern (Now Aligned)

```typescript
import { connectGraphIssuance } from '@graphprotocol/toolshed'

const contracts = connectGraphIssuance(42161, provider)
await contracts.IssuanceAllocator.setIssuancePerBlock(...)
```

**Implementation:**

- ✅ `GraphIssuanceAddressBook` extends `AddressBook` base class
- ✅ `GraphIssuanceContracts` type defines contract interfaces
- ✅ `connectGraphIssuance()` helper for external usage
- ✅ `loadGraphIssuance()` helper for Hardhat tasks
- ✅ Exported from `@graphprotocol/toolshed`

## Ignition Deployment Workflow

### 1. Deploy with Ignition

```bash
npx hardhat ignition deploy ignition/modules/deploy.ts \
  --network arbitrumSepolia \
  --parameters ignition/configs/issuance.arbitrumSepolia.json5
```

This creates: `ignition/deployments/<deployment-id>/deployed_addresses.json`

### 2. Sync to Address Book

```bash
npx ts-node scripts/sync-addresses.ts issuance-arbitrumSepolia 421614
```

This updates: `addresses.json` with the deployed contract addresses

### 3. Use via Toolshed

```typescript
import { connectGraphIssuance } from '@graphprotocol/toolshed'

const contracts = connectGraphIssuance(421614, provider)
// Contracts are now loaded from addresses.json
```

## File Structure Comparison

### Horizon

```
packages/horizon/
├── addresses.json                    # Chain ID based
├── ignition/
│   ├── modules/                      # Deployment modules
│   ├── configs/                      # Network configs
│   └── deployments/                  # Ignition artifacts
└── toolshed integration via:
    packages/toolshed/src/deployments/horizon/
    ├── address-book.ts
    ├── contracts.ts
    └── index.ts
```

### Issuance (Now Aligned)

```
packages/issuance/
├── addresses.json                    # Chain ID based ✅
├── ignition/
│   ├── modules/                      # Deployment modules ✅
│   ├── configs/                      # Network configs ✅
│   └── deployments/                  # Ignition artifacts ✅
├── scripts/
│   └── sync-addresses.ts             # Sync script ✅
└── toolshed integration via:
    packages/toolshed/src/deployments/issuance/
    ├── address-book.ts               # ✅
    ├── contracts.ts                  # ✅
    └── index.ts                      # ✅
```

## Key Differences from Horizon

While aligned in pattern, issuance is simpler and cleaner:

1. **No Actions Module** - Horizon has `actions.ts` with helper functions; issuance doesn't need this yet
2. **Fewer Contracts** - Only 3 contracts vs Horizon's 12+
3. **No Legacy Aliases** - Horizon creates legacy contract aliases; issuance doesn't need this
4. **Simpler Configs** - Fewer configuration parameters
5. **No Toolshed Wrapper Interfaces** - Issuance contracts implement complete interfaces directly, unlike legacy contracts that needed toolshed wrappers to add missing functions or work around TypeScript generation issues

### Why Horizon Needs Toolshed Interfaces (But Issuance Doesn't)

Horizon's toolshed interfaces (`IHorizonStakingToolshed`, `IL2GNSToolshed`, etc.) exist to work around issues with legacy contracts:

**Problems they solve:**

1. **Incomplete interfaces** - Legacy contracts split functionality across multiple files, toolshed combines them
2. **Missing functions** - Some storage getters or utility functions weren't in the original interfaces
3. **TypeScript generation issues** - ethers v6 has problems with certain Solidity patterns (e.g., dynamic return types)
4. **Adding Multicall** - Many contracts needed `IMulticall` added for batch operations

**Example from Horizon:**

```solidity
// IL2GNSToolshed adds missing functions
interface IL2GNSToolshed is IGNS, IL2GNS, IMulticall {
    function nextAccountSeqID(address account) external view returns (uint256);
    function subgraphNFT() external view returns (address);
}
```

**Issuance doesn't need this because:**

- ✅ Contracts implement complete interfaces from the start
- ✅ All functions are properly exposed in interfaces
- ✅ No legacy compatibility issues
- ✅ Modern Solidity patterns that work well with TypeScript generation

The issuance package uses **composite TypeScript types** instead:

```typescript
// In @graphprotocol/interfaces
export type IssuanceAllocator = IIssuanceAllocationAdministration &
  IIssuanceAllocationData &
  IIssuanceAllocationDistribution &
  IIssuanceAllocationStatus
```

This provides the same developer experience without needing extra Solidity wrapper interfaces.

## Benefits of Alignment

1. **Consistent Developer Experience** - Same patterns across packages
2. **Toolshed Reuse** - Leverage existing `AddressBook` infrastructure
3. **Easy Integration** - Can compose issuance with Horizon deployments
4. **Type Safety** - Full TypeScript support via interfaces package
5. **Maintainability** - Familiar patterns for team members

## Usage Examples

### Standalone Usage

```typescript
import { connectGraphIssuance } from '@graphprotocol/toolshed'

const contracts = connectGraphIssuance(42161, provider)
await contracts.IssuanceAllocator.setIssuancePerBlock(newRate)
```

### Combined with Horizon

```typescript
import { connectGraphHorizon, connectGraphIssuance } from '@graphprotocol/toolshed'

const horizonContracts = connectGraphHorizon(42161, provider)
const issuanceContracts = connectGraphIssuance(42161, provider)

// Use both together
await issuanceContracts.IssuanceAllocator.setTarget(
  horizonContracts.HorizonStaking.target
)
```

### In Hardhat Tasks

```typescript
import { loadGraphIssuance } from '@graphprotocol/toolshed'

task('set-issuance', 'Set issuance rate')
  .addParam('rate', 'New issuance rate')
  .setAction(async ({ rate }, hre) => {
    const { contracts } = loadGraphIssuance(
      'addresses.json',
      hre.network.config.chainId!,
      hre.ethers.provider
    )
    
    await contracts.IssuanceAllocator.setIssuancePerBlock(rate)
  })
```

## Migration Notes

If you have existing code using the old format:

**Old (network names):**

```json
{
  "arbitrumOne": { "IssuanceAllocator": "0x..." }
}
```

**New (chain IDs):**

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

The sync script handles this conversion automatically when syncing from Ignition deployments.
