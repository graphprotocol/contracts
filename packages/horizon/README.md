# 🌅 Graph Horizon 🌅

Graph Horizon is the next evolution of the Graph Protocol.

## Configuration

The following environment variables might be required:

| Variable | Description |
|----------|-------------|
| `ARBISCAN_API_KEY` | Arbiscan API key - for contract verification|
| `ARBITRUM_ONE_RPC` | Arbitrum One RPC URL - defaults to `https://arb1.arbitrum.io/rpc` |
| `ARBITRUM_SEPOLIA_RPC` | Arbitrum Sepolia RPC URL - defaults to `https://sepolia-rollup.arbitrum.io/rpc` |
| `LOCALHOST_RPC` | Localhost RPC URL - defaults to `http://localhost:8545` |
| `LOCALHOST_CHAIN_ID` | Localhost chain ID - defaults to `31337` |
| `LOCALHOST_ACCOUNTS_MNEMONIC` | Localhost accounts mnemonic - no default value. Note that setting this will override any secure accounts configuration. |

You can set them using Hardhat:

```bash
npx hardhat vars set <variable>
```

## Build

```bash
yarn install
yarn build
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

- Unit tests can be run with `yarn test`
- Deployment tests can be run with `yarn test:deployment --network <network>`
   - By default, deployment tests assume a `migrate` deployment type. This can be overridden by setting the `IGNITION_DEPLOYMENT_TYPE` environment variable to `protocol`, however the tests only cover state transitions
   originated by a `migrate` deployment.

## Verification

To verify contracts on a network, run the following commands:

```bash
./scripts/pre-verify <ignition-deployment-id>
npx hardhat ignition verify --network <network> --include-unrelated-contracts <ignition-deployment-id>
```