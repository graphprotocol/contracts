# @graphprotocol/interfaces

Contract interfaces and types for The Graph protocol.

## Overview

This package contains contract interfaces and types used in dependent packages.

## Installation

```bash
pnpm add @graphprotocol/interfaces
```

## Compiler Version Strategy

Interface pragma statements use open-ended caret ranges (e.g., `^0.8.22`) rather than exact versions to maximize compatibility with future packages and compiler versions:

- **Dual-version interfaces** (`^0.7.6 || ^0.8.0` or `^0.7.3 || ^0.8.0`): Maintain compatibility with both Solidity 0.7.x and 0.8.x implementations
- **Modern interfaces** (`^0.8.22`): Allow the use of Solidity 0.8-specific features like custom errors, named mapping parameters, and file-level events

This approach allows consuming projects to use any compatible compiler version within the specified range.

## Usage

### Contract interfaces

Solidity contract interfaces can be imported from `@graphprotocol/interfaces/contracts/...`:

```solidity
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

contract GraphPayments is IGraphPayments {
    ...
}
```

Note that contracts in the `toolshed/` directory are not meant to be imported by Solidity code, they only exist to
generate complete TypeScript types.

### TypeScript types

This package provides types generated with [Typechain](https://github.com/dethcrypto/TypeChain) compatible with ethers v6. To use them import with:

```ts
import {
  GraphPayments,
  GraphTallyCollector,
  HorizonStaking,
  L2GraphToken,
  PaymentsEscrow,
  SubgraphService,
} from '@graphprotocol/interfaces'
```

#### Available Type Formats

This package generates TypeScript types in multiple formats to support different environments:

- **ethers v6** (default): `dist/types/` - Modern ethers.js types (imported from package root)
- **ethers v5**: `dist/types-v5/` - Legacy ethers.js support for projects still using ethers v5
- **Wagmi**: `dist/wagmi/` - React hooks for the wagmi library

Import the appropriate version based on your project's dependencies.

### TypeScript library

Additionally, the package exposes a few helper functions to facilitate the creation of fully typed ethers v6 contracts:

| Function Name        | Description                                                 |
| -------------------- | ----------------------------------------------------------- |
| `getInterface`       | Retrieves the contract interface for a given contract name. |
| `getMergedInterface` | Loads and merges interfaces from multiple contract names.   |
| `getAbi`             | Gets the ABI for a given contract name.                     |

```ts
import { getInterface, SubgraphService } from '@graphprotocol/interfaces'

const subgraphService = new ethers.Contract('0x12...90', getInterface('SubgraphService')) as SubgraphService
```
