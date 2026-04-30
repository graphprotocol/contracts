# 🌅 Graph Horizon 🌅

Graph Horizon is the next evolution of the Graph Protocol.

## Configuration

The following environment variables might be required:

| Variable               | Description                                                                     |
| ---------------------- | ------------------------------------------------------------------------------- |
| `ARBISCAN_API_KEY`     | Arbiscan API key - for contract verification                                    |
| `ARBITRUM_ONE_RPC`     | Arbitrum One RPC URL - defaults to `https://arb1.arbitrum.io/rpc`               |
| `ARBITRUM_SEPOLIA_RPC` | Arbitrum Sepolia RPC URL - defaults to `https://sepolia-rollup.arbitrum.io/rpc` |
| `LOCALHOST_RPC`        | Localhost RPC URL - defaults to `http://localhost:8545`                         |

You can set them using Hardhat:

```bash
npx hardhat vars set <variable>
```

## Build

```bash
pnpm install
pnpm build
```

## Deployment

Note that this instructions will help you deploy Graph Horizon contracts, but no data service will be deployed. If you want to deploy the Subgraph Service please refer to the [Subgraph Service README](../subgraph-service/README.md) for deploy instructions.

### New deployment

To deploy Graph Horizon from scratch run the following command:

```bash
npx hardhat deploy:protocol --network hardhat
```

### Upgrade deployment

Usually you would run this against a network (or a fork) where the original Graph Protocol was previously deployed. To upgrade an existing deployment of the original Graph Protocol to Graph Horizon, run the following commands. Note that some steps might need to be run by different accounts (deployer vs governor):

```bash
npx hardhat deploy:migrate --network hardhat --step 1
npx hardhat deploy:migrate --network hardhat --step 2 # Run with governor. Optionally add --patch-config
npx hardhat deploy:migrate --network hardhat --step 3 # Optionally add --patch-config
npx hardhat deploy:migrate --network hardhat --step 4 # Run with governor. Optionally add --patch-config
```

Steps 2, 3 and 4 require patching the configuration file with addresses from previous steps. The files are located in the `ignition/configs` directory and need to be manually edited. You can also pass `--patch-config` flag to the deploy command to automatically patch the configuration reading values from the address book. Note that this will NOT update the configuration file.

## Testing

- **unit**: Unit tests can be run with `pnpm test`
- **integration**: Integration tests can be run with `pnpm test:integration` - Need to set `BLOCKCHAIN_RPC` for a chain where The Graph is already deployed - If no `BLOCKCHAIN_RPC` is detected it will try using `ARBITRUM_SEPOLIA_RPC`
- **deployment**: Deployment tests can be run with `pnpm test:deployment --network <network>`, the following environment variables allow customizing the test suite for different scenarios:
  - `TEST_DEPLOYMENT_STEP` (default: 1) - Specify the latest deployment step that has been executed. Tests for later steps will be skipped.
  - `TEST_DEPLOYMENT_TYPE` (default: migrate) - The deployment type `protocol/migrate` that is being tested. Test suite has been developed for `migrate` use case but can be run against a `protocol` deployment, likely with some failed tests.
  - `TEST_DEPLOYMENT_CONFIG` (default: `hre.network.name`) - The Ignition config file name to use for the test suite.

## Verification

To verify contracts on a network, run the following commands:

```bash
./scripts/pre-verify <ignition-deployment-id>
npx hardhat ignition verify --network <network> --include-unrelated-contracts <ignition-deployment-id>
./scripts/post-verify
```

## Operational Tasks

Operational tasks for post-migration maintenance and fund recovery are located in `tasks/ops/`.

### Configuration

Set the subgraph API key for querying The Graph Network:

```bash
npx hardhat vars set SUBGRAPH_API_KEY
```

### Legacy Allocations

Force close legacy allocations that haven't been migrated to Horizon.

#### Query Legacy Allocations

Query and report active legacy allocations from the Graph Network subgraph:

```bash
npx hardhat ops:allocations:query --network arbitrumOne
```

Options:
- `--subgraph-api-key`: API key for The Graph Network gateway
- `--excluded-indexers`: Comma-separated indexer addresses to exclude (default: upgrade indexer)
- `--output-dir`: Output directory for reports (default: `./ops-output`)

#### Close Legacy Allocations

Force close legacy allocations:

```bash
# Generate calldata for external execution (Fireblocks, Safe, etc.)
npx hardhat ops:allocations:close --network arbitrumOne --calldata-only

# Execute directly with secure accounts
npx hardhat ops:allocations:close --network arbitrumOne

# Dry run to simulate without executing
npx hardhat ops:allocations:close --network arbitrumOne --dry-run
```

Options:
- `--input-file`: JSON file from query task (if not provided, queries subgraph)
- `--account-index`: Derivation path index for the account (default: 0)
- `--calldata-only`: Generate calldata without executing
- `--dry-run`: Simulate without executing

### TAP Escrow Recovery

Recover GRT funds from the TAP v1 Escrow contract.

#### Query Escrow Accounts

Query and report TAP escrow accounts:

```bash
npx hardhat ops:escrow:query --network arbitrumOne
```

Options:
- `--subgraph-api-key`: API key for The Graph Network gateway
- `--sender-addresses`: Comma-separated sender addresses to query
- `--output-dir`: Output directory for reports (default: `./ops-output`)

#### Thaw Escrow Funds

Initiate the 30-day thawing period for escrow funds:

```bash
# Generate calldata for external execution
npx hardhat ops:escrow:thaw --network arbitrumOne --calldata-only

# Execute directly
npx hardhat ops:escrow:thaw --network arbitrumOne

# Dry run
npx hardhat ops:escrow:thaw --network arbitrumOne --dry-run
```

Options:
- `--input-file`: JSON file from query task
- `--account-index`: Derivation path index for the gateway account (default: 0)
- `--escrow-address`: TAP Escrow contract address
- `--calldata-only`: Generate calldata without executing
- `--dry-run`: Simulate without executing

#### Withdraw Escrow Funds

Withdraw thawed funds after the 30-day thawing period:

```bash
# Generate calldata for external execution
npx hardhat ops:escrow:withdraw --network arbitrumOne --calldata-only

# Execute directly
npx hardhat ops:escrow:withdraw --network arbitrumOne
```

Options:
- `--input-file`: JSON file from query task
- `--account-index`: Derivation path index for the gateway account (default: 0)
- `--escrow-address`: TAP Escrow contract address
- `--calldata-only`: Generate calldata without executing
- `--dry-run`: Simulate without executing

### Output Files

All operational task outputs are saved to `ops-output/` (configurable via `--output-dir`):

```
ops-output/
├── allocations-YYYY-MM-DD-HHMMSS.json     # Legacy allocation data
├── allocations-YYYY-MM-DD-HHMMSS.csv      # CSV for spreadsheet review
├── escrow-accounts-YYYY-MM-DD-HHMMSS.json # Escrow account data
├── escrow-accounts-YYYY-MM-DD-HHMMSS.csv  # CSV for spreadsheet review
├── close-allocations-results-*.json       # Allocation closing results
├── thaw-escrow-results-*.json             # Thaw transaction results
├── withdraw-escrow-results-*.json         # Withdraw transaction results
└── calldata/
    ├── close-allocations-*.json           # Calldata for allocation closing
    ├── thaw-escrow-*.json                 # Calldata for thawing
    └── withdraw-escrow-*.json             # Calldata for withdrawal
```
