# @graphprotocol/toolshed

A collection of tools and utilities for The Graph Protocol's TypeScript components. This package provides essential functionality for working with The Graph Protocol's smart contracts, deployments, and development tools.

## Features

- **Core**: Essential tools and functions for working with The Graph Protocol
- **Deployment Tools**: Utilities for interacting with protocol deployments
- **Hardhat Integration**: Tools and plugins for Hardhat development
- **Utility Functions**: Helper functions for common operations

## Installation

```bash
pnpm add @graphprotocol/toolshed
```

## Usage

The package is organized into several modules that can be imported separately:

```typescript
// Import core functionality
import { encodeAllocationProof } from '@graphprotocol/toolshed';

// Import deployment
import { loadGraphHorizon } from '@graphprotocol/toolshed/deployments/horizon';

// Import Hardhat utilities
import { hardhatBaseConfig } from '@graphprotocol/toolshed/hardhat';

// Import utility functions
import { printBanner } from '@graphprotocol/toolshed/utils';
```