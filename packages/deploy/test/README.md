# Deploy Package Tests

Integration and fork-based tests for cross-package orchestration.

## Test Categories

### Integration Tests

Test orchestration logic without forking:

- TX batch generation
- Module coordination
- Parameter validation

### Fork-Based Tests

Test complete governance workflow on Arbitrum fork:

- Deploy components
- Generate governance TX
- Simulate governance execution
- Verify with checkpoint modules

## Available Tests

### ✅ Implemented

- `reo-governance-fork.test.ts` - REO deployment and governance integration workflow

### 📋 Planned

- `ia-governance-fork.test.ts` - IA deployment and integration (Phase 3)
- `tx-builder.test.ts` - Safe TX generation validation

## Running Tests

### Standard Tests

```bash
# All tests
pnpm test

# Specific test
pnpm test test/reo-governance-fork.test.ts

# Fork tests only
pnpm test:fork
```

### Fork-Based Tests (Requires RPC)

Fork tests require access to Arbitrum RPC endpoints.

#### Default: Arbitrum One (Mainnet)

Most realistic for governance testing - uses production contracts and state:

```bash
# Set RPC URL as Hardhat variable (one-time setup)
npx hardhat vars set ARBITRUM_ONE_RPC

# Or export as environment variable
export ARBITRUM_ONE_RPC="https://arb1.arbitrum.io/rpc"

# Run fork tests (defaults to Arbitrum One)
pnpm test:fork

# Run specific fork test
pnpm test test/reo-governance-fork.test.ts
```

#### Alternative: Arbitrum Sepolia (Testnet)

For testnet deployment validation:

```bash
# Set RPC URL
npx hardhat vars set ARBITRUM_SEPOLIA_RPC

# Or export as environment variable
export ARBITRUM_SEPOLIA_RPC="https://sepolia-rollup.arbitrum.io/rpc"

# Run fork tests with testnet
FORK_NETWORK=arbitrum-sepolia pnpm test:fork

# Run specific fork test with testnet
FORK_NETWORK=arbitrum-sepolia pnpm test test/reo-governance-fork.test.ts
```

**Note:** Fork tests will skip if RPC is not configured or network conditions prevent forking.
