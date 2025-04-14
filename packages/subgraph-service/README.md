# 🌅 Subgraph Service 🌅

The Subgraph Service is a data service designed to work with Graph Horizon that supports indexing subgraphs and serving queries to consumers.

## Configuration

The following environment variables might be required:

| Variable | Description |
|----------|-------------|
| `ARBISCAN_API_KEY` | Arbiscan API key - for contract verification|
| `ARBITRUM_ONE_RPC` | Arbitrum One RPC URL - defaults to `https://arb1.arbitrum.io/rpc` |
| `ARBITRUM_SEPOLIA_RPC` | Arbitrum Sepolia RPC URL - defaults to `https://sepolia-rollup.arbitrum.io/rpc` |
| `LOCALHOST_RPC` | Localhost RPC URL - defaults to `http://localhost:8545` |

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

Note that this instructions will help you deploy Graph Horizon contracts alongside the Subgraph Service. If you want to deploy just the core Horizon contracts please refer to the [Horizon README](../horizon/README.md) for deploy instructions.

### New deployment
To deploy Graph Horizon from scratch including the Subgraph Service run the following command:

```bash
npx hardhat deploy:protocol --network hardhat
```

### Upgrade deployment
Usually you would run this against a network (or a fork) where the original Graph Protocol was previously deployed. To upgrade an existing deployment of the original Graph Protocol to Graph Horizon including the Subgraph Service, run the following commands. Note that some steps might need to be run by different accounts (deployer vs governor):

```bash
cd ../
cd horizon && npx hardhat deploy:migrate --network hardhat --step 1 && cd ..
cd subgraph-service && npx hardhat deploy:migrate --network hardhat --step 1 && cd ..
cd horizon && npx hardhat deploy:migrate --network hardhat --step 2 && cd .. # Run with governor. Optionally add --patch-config
cd horizon && npx hardhat deploy:migrate --network hardhat --step 3 && cd .. # Optionally add --patch-config
cd subgraph-service && npx hardhat deploy:migrate --network hardhat --step 2 && cd .. # Optionally add --patch-config
cd horizon && npx hardhat deploy:migrate --network hardhat --step 4 && cd .. # Run with governor. Optionally add --patch-config
```

Horizon Steps 2, 3 and 4, and Subgraph Service Step 2 require patching the configuration file with addresses from previous steps. The files are located in the `ignition/configs` directory and need to be manually edited. You can also pass `--patch-config` flag to the deploy command to automatically patch the configuration reading values from the address book. Note that this will NOT update the configuration file.

## Testing

- Unit tests can be run with `pnpm test`
- Deployment tests can be run with `pnpm test:deployment --network <network>`
   - By default, deployment tests assume a `migrate` deployment type. This can be overridden by setting the `IGNITION_DEPLOYMENT_TYPE` environment variable to `protocol`, however the tests only cover state transitions
   originated by a `migrate` deployment.

## Verification

To verify contracts on a network, run the following commands:

```bash
./scripts/pre-verify <ignition-deployment-id>
npx hardhat ignition verify --network <network> --include-unrelated-contracts <ignition-deployment-id>
```