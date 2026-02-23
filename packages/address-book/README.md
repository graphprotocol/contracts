# @graphprotocol/address-book

Contract addresses for The Graph Protocol. This package provides JSON files containing contract addresses for different networks.

## Features

- Contract addresses for Horizon and Subgraph Service
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

// ES Modules
import horizonAddresses from '@graphprotocol/address-book/horizon/addresses.json'
import subgraphServiceAddresses from '@graphprotocol/address-book/subgraph-service/addresses.json'
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

This package uses symlinks to stay in sync with the source address files. On first install, symlinks are automatically created.

## npm Publishing

This package uses a special workflow to ensure address files are included in the published package:

### How It Works

**Development**: The package uses symlinks to stay in sync with source address files:

- `src/horizon/addresses.json` → symlink to `../../../horizon/addresses.json`
- `src/subgraph-service/addresses.json` → symlink to `../../../subgraph-service/addresses.json`

**Publishing**: npm doesn't include symlinks in packages, so we automatically handle this:

```bash
npm publish
```

**Automatic execution**:

1. **`prepublishOnly`** - Copies actual files to replace symlinks
2. **npm pack & publish** - Includes real address files in published package
3. **`postpublish`** - Restores symlinks for development

### Troubleshooting

If publishing fails, the `postpublish` script may not run, leaving copied files instead of symlinks. To restore symlinks manually:

```bash
pnpm restore-symlinks
```

All symlink management is handled automatically during successful publishes.
