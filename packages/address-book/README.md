# @graphprotocol/address-book

Contract addresses for The Graph Protocol. This package provides JSON files containing contract addresses for different networks.

## Features

- Contract addresses for Horizon, Subgraph Service, Issuance, DataEdge and Legacy (the L1 deployment record)
- Network-specific deployment addresses
- Zero dependencies

## Installation

```bash
npm install @graphprotocol/address-book
# or
pnpm install @graphprotocol/address-book
```

## Usage

### Import addresses directly

```javascript
// CommonJS
const horizonAddresses = require('@graphprotocol/address-book/horizon/addresses.json')
const subgraphServiceAddresses = require('@graphprotocol/address-book/subgraph-service/addresses.json')
const issuanceAddresses = require('@graphprotocol/address-book/issuance/addresses.json')
const dataEdgeAddresses = require('@graphprotocol/address-book/data-edge/addresses.json')
const legacyAddresses = require('@graphprotocol/address-book/legacy/addresses.json')

// ES Modules
import horizonAddresses from '@graphprotocol/address-book/horizon/addresses.json'
import subgraphServiceAddresses from '@graphprotocol/address-book/subgraph-service/addresses.json'
import issuanceAddresses from '@graphprotocol/address-book/issuance/addresses.json'
import dataEdgeAddresses from '@graphprotocol/address-book/data-edge/addresses.json'
import legacyAddresses from '@graphprotocol/address-book/legacy/addresses.json'
```

### Address format

The addresses are organized by chain ID and contract name:

```json
{
  "1337": {
    "Controller": {
      "address": "0x...",
      "proxy": "transparent",
      "proxyAdmin": "0x...",
      "implementation": "0x..."
    }
  }
}
```

## Development

The files under `src/<name>/addresses.json` are tracked as regular copies of each package's `addresses.json`. Update the copy whenever its source changes.

## npm Publishing

This package uses a special workflow to ensure address files are included in the published package:

### How It Works

**Development**: `src/<name>/addresses.json` is a tracked regular file, a copy of the source address file:

- `src/horizon/addresses.json` ← `packages/horizon/addresses.json`
- `src/subgraph-service/addresses.json` ← `packages/subgraph-service/addresses.json`
- `src/issuance/addresses.json` ← `packages/issuance/addresses.json`
- `src/data-edge/addresses.json` ← `packages/data-edge/addresses.json`
- `src/legacy/addresses.json` ← `packages/legacy/addresses.json`

The list of exported packages lives in `scripts/sources.js`.

**Publishing**: `prepublishOnly` copies the source files over the tracked files. `postpublish` then turns the files into symlinks, so after a publish they are symlinks until you restore the regular files with `git checkout`:

```bash
npm publish
```

**Automatic execution**:

1. **`prepublishOnly`** - Copies the source files over `src/<name>/addresses.json`
2. **npm pack & publish** - Includes real address files in published package
3. **`postpublish`** - Runs `restore-symlinks`, which turns the files into symlinks

### Troubleshooting

If publishing fails, `postpublish` may not run. That leaves the copied files, which are the tracked state, so there is nothing to fix.

After a successful publish, `src/<name>/addresses.json` are symlinks and show as changes in git. To restore the tracked files, run this from `packages/address-book`:

```bash
git checkout -- src
```
