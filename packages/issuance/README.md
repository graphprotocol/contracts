# The Graph Issuance Contracts

This package contains smart contracts for The Graph's issuance functionality.

## Overview

The issuance contracts handle token issuance mechanisms for The Graph protocol.

### Contracts

- **[IssuanceAllocator](contracts/allocate/IssuanceAllocator.md)** - Central distribution hub for token issuance, allocating tokens to different protocol components based on configured rates
- **[RewardsEligibilityOracle](contracts/eligibility/RewardsEligibilityOracle.md)** - Oracle-based eligibility system for indexer rewards with time-based expiration
- **DirectAllocation** - Simple target contract implementation for receiving and distributing allocated tokens (deployed as PilotAllocation and other instances)

## Development

### Setup

```bash
# Install dependencies
pnpm install

# Build
pnpm build

# Test
pnpm test
```

### Testing

To run the tests:

```bash
pnpm test
```

For coverage:

```bash
pnpm test:coverage
```

### Linting

To lint the contracts and tests:

```bash
pnpm lint
```

### Contract Size

To check contract sizes:

```bash
pnpm size
```

## License

GPL-2.0-or-later
