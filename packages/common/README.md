# @graphprotocol/common

Common utilities and configuration for Graph Protocol packages.

## Overview

This package provides shared utilities and configuration for all Graph Protocol packages. It centralizes network configurations, contract addresses, and environment variable handling to ensure consistency across packages.

## Installation

```bash
# From the root of the monorepo
yarn workspace @graphprotocol/common install
```

## Usage

TODO: This needs to be refactored with Ignition usage.

### Network Configuration

```javascript
import {
  getNetworkConfig,
  getNetworkConfigByChainId,
  isL2Network,
  isProductionNetwork,
  getAnvilForkConfig,
} from '@graphprotocol/common'

// Get network configuration by name
const arbitrumConfig = getNetworkConfig('arbitrumOne')
console.log(arbitrumConfig.displayName) // Arbitrum One
console.log(arbitrumConfig.sourceRpcUrl) // https://arb1.arbitrum.io/rpc
console.log(arbitrumConfig.localRpcUrl) // http://127.0.0.1:8545

// Get network configuration by chain ID
const ethereumConfig = getNetworkConfigByChainId(1)
console.log(ethereumConfig.name) // ethereumMainnet

// Check if a network is an L2
const isL2 = isL2Network('arbitrumOne') // true

// Check if a network is a production network
const isProd = isProductionNetwork('arbitrumOne') // true

// Configure an Anvil fork for a specific network
const forkConfig = getAnvilForkConfig('arbitrumOne')
console.log(forkConfig.displayName) // Anvil Fork of Arbitrum One
console.log(forkConfig.sourceRpcUrl) // https://arb1.arbitrum.io/rpc
console.log(forkConfig.localRpcUrl) // http://127.0.0.1:8545
```

Each network configuration includes:

- `name`: Internal name of the network
- `displayName`: Human-readable name of the network
- `chainId`: Chain ID of the network
- `sourceRpcUrl`: RPC URL of the actual network (used for forking)
- `localRpcUrl`: RPC URL for local development/testing (used for connecting)
- `blockExplorer`: URL of the block explorer
- `isL2`: Whether the network is an L2
- `isProduction`: Whether the network is a production network
- `paramsFile`: Path to the parameter file for deployments

### Contract Addresses

```javascript
import { getContractAddress, getAllContractAddresses } from '@graphprotocol/common'

// Get a specific contract address
const graphTokenAddress = getContractAddress(1, 'GraphToken')
console.log(graphTokenAddress) // 0x...

// Get all contract addresses for a chain ID
const addresses = getAllContractAddresses(1)
console.log(addresses.GraphToken) // 0x...
```

Note: For Arbitrum networks, the GraphToken contract address is stored as L2GraphToken in the addresses.json file, but you can still use 'GraphToken' as the contract name in your code.

### Environment Variables

```javascript
import { loadEnv, getEnv, getBoolEnv, getNumericEnv } from '@graphprotocol/common'

// Load environment variables from a file
loadEnv('.env.arbitrum-one')

// Get environment variables with fallbacks
const rpcUrl = getEnv('RPC_URL', 'http://localhost:8545')
const isProduction = getBoolEnv('PRODUCTION', false)
const chainId = getNumericEnv('CHAIN_ID', 1)
```

## Command-line Usage

The addresses.js module can be used directly from the command line:

```bash
# Get a specific contract address
node src/config/addresses.js 1 GraphToken

# Get all contract addresses for a chain ID
node src/config/addresses.js 1
```

## Directory Structure

```text
src/
  config/           # Shared configuration
    networks.js     # Network configurations
    addresses.js    # Contract addresses utility
    ignition/       # Ignition-specific configuration
      parameters/   # Shared parameter templates
  utils/            # Shared utilities
    env.js          # Environment variable handling
  index.js          # Main entry point
```

## Contributing

To add a new network configuration, update the `NETWORKS` object in `src/config/networks.js`.

To add new utilities, create a new file in the appropriate directory and export it from `src/index.js`.
