# 🌅 Graph Horizon 🌅

Graph Horizon is the next evolution of the Graph Protocol.

## Configuration

The following environment variables might be required:

| Variable | Description |
|----------|-------------|
| `ARBISCAN_API_KEY` | Arbiscan API key |
| `DEPLOYER_PRIVATE_KEY` | Deployer private key - for testnet deployments |
| `GOVERNOR_PRIVATE_KEY` | Governor private key - for testnet deployments |
| `ARBITRUM_SEPOLIA_RPC` | Arbitrum Sepolia RPC URL |
| `VIRTUAL_ARBITRUM_SEPOLIA_RPC` | Virtual Arbitrum Sepolia RPC URL |

You can set them using Hardhat:

```bash
npx hardhat vars set <variable>
```

## Build

```bash
yarn install
yarn build
```

## Deploy

Note that this instructions will help you deploy Graph Horizon contracts, but no data service will be deployed. If you want to deploy the Subgraph Service please refer to the [Subgraph Service README](../subgraph-service/README.md) for deploy instructions.

### New deployment
To deploy Graph Horizon from scratch run the following command:

```bash
npx hardhat run scripts/deploy.ts --network hardhat
```

### Upgrade deployment
To upgrade an existing deployment of the original Graph Protocol to Graph Horizon, run the following command:

```bash
npx hardhat run scripts/migrate.ts --network localhost
```

Usually you would run this against a network (or a fork) where the original Graph Protocol was previously deployed.