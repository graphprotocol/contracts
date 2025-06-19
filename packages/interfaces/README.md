# @graphprotocol/interfaces

Contract interfaces and types for The Graph protocol.

## Overview

This package contains contract interfaces and types used in dependent packages, which makes building systems that interact with The Graph contracts simpler, as the implementation information is not included.

## Installation

```bash
pnpm add @graphprotocol/interfaces
```

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

### TypeScript library

Additionally, the package exposes a few helper functions to facilitate the creation of fully typed ethers v6 contracts:

| Function Name        | Description                                                 |
| -------------------- | ----------------------------------------------------------- |
| `getInterface`       | Retrieves the contract interface for a given contract name. |
| `getMergedInterface` | Loads and merges interfaces from multiple contract names.   |
| `getAbi`             | Gets the ABI for a given contract name.                     |

```ts
import {
    getInterface,
    SubgraphService
} from '@graphprotocol/interfaces

const subgraphService = new ethers.Contract('0x12...90', getInterface('SubgraphService')) as SubgraphService
```
