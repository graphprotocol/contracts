# AddressBook Operations

## Overview

`AddressBookOps` wraps the base `AddressBook` class from toolshed, providing data-centric operations for managing contract addresses. Deployment code only sees `AddressBookOps` - the base class is internal.

**Layer 1 only**: Pure local storage operations with no on-chain interactions.

## Usage

```typescript
import { graph } from '../rocketh/deploy.js'

// Get AddressBookOps directly from factory functions
const addressBook = graph.getIssuanceAddressBook(chainId)

// Write operations
addressBook.setProxy('RewardsManager', proxyAddr, implAddr, adminAddr, 'transparent')
addressBook.setPendingImplementation('RewardsManager', newImplAddr, { txHash: '0x...' })

// Read operations
const entry = addressBook.getEntry('RewardsManager')
```

## API

### Write Operations

| Method                                            | Purpose                                  |
| ------------------------------------------------- | ---------------------------------------- |
| `setContract(name, address)`                      | Non-proxied contract                     |
| `setProxy(name, proxy, impl, admin, type)`        | All proxy fields                         |
| `setImplementation(name, impl)`                   | Active implementation                    |
| `setProxyAdmin(name, admin)`                      | Proxy admin                              |
| `setPendingImplementation(name, impl, metadata?)` | Pending implementation                   |
| `promotePendingImplementation(name)`              | Move pending → active                    |
| `clearPendingImplementation(name)`                | Clear pending                            |
| `setImplementationAndClearIfMatches(name, impl)`  | Set impl + auto-clear pending if matches |

### Read Operations

| Method                         | Purpose                              |
| ------------------------------ | ------------------------------------ |
| `getEntry(name)`               | Get address book entry               |
| `entryExists(name)`            | Check if entry exists                |
| `listPendingImplementations()` | List contracts with pending upgrades |
| `isContractName(name)`         | Type predicate for contract names    |

### Types

```typescript
// For union types where contract name would be inferred as `never`
type AnyAddressBookOps = AddressBookOps<string>
```

## Next Steps

See [LayerAnalysis.md](./LayerAnalysis.md) for potential Layer 2 (network-linked operations) design.
