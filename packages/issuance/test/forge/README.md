# Foundry Fork Tests for Issuance Project

This directory contains Foundry-based fork tests for the issuance project. These tests are designed to test contract upgrades and interactions in a forked Arbitrum network environment.

## Overview

The fork tests are organized as follows:

- `utils/`: Base test contracts and utilities
  - `BaseTest.sol`: Base contract for all forge tests
  - `ForkTest.sol`: Base contract for fork tests
  - `ArbitrumForkTest.sol`: Base contract for Arbitrum fork tests

- `fork/`: Fork test implementations
  - `IssuanceSystemForkTest.sol`: Tests for the issuance system deployment and operation
  - `RewardsManagerUpgradeTest.sol`: Tests for upgrading from RewardsManager to IssuanceAllocator
  - `ExpiringServiceQualityOracleForkTest.sol`: Tests for the ExpiringServiceQualityOracle contract

## Setup

1. Create a `.env` file in the `packages/issuance` directory with the following variables:

   ```bash
   ARBITRUM_RPC_URL=https://rpc.ankr.com/arbitrum//your-api-key
   ```

2. Install Foundry if you haven't already:

   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

## Running the Tests

### Build the Contracts

```bash
yarn forge:build
```

### Run All Tests

```bash
yarn forge:test
```

### Run Fork Tests

```bash
# Run fork tests without forking (will fail for tests that require a fork)
yarn forge:test:fork

# Run fork tests with Arbitrum forking
yarn forge:test:fork:arbitrum
```

### Run Specific Tests

```bash
# Run a specific test file
forge test --match-path test/forge/fork/IssuanceSystemForkTest.sol --fork-url $ARBITRUM_RPC_URL -vvv

# Run a specific test function
forge test --match-path test/forge/fork/IssuanceSystemForkTest.sol --match-test testDistributeIssuance --fork-url $ARBITRUM_RPC_URL -vvv
```

## Test Coverage

```bash
yarn forge:coverage
```

## Notes

- These tests are designed to run against an Arbitrum fork, as the issuance project will be deployed on Arbitrum.
- The tests use the actual contract addresses from Arbitrum for interacting with existing contracts like GraphToken and RewardsManager.
- The fork tests complement the existing unit tests by testing upgrades and contract interactions in a more realistic environment.
