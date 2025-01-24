# 🌅 Graph Horizon 🌅

Graph Horizon is the next evolution of the Graph Protocol.

## Configuration

The following environment variables might be required:

- `ETHERSCAN_API_KEY`: Etherscan API key

You can set them using Hardhat:

```bash
npx hardhat vars set ETHERSCAN_API_KEY
```

## Build

```bash
yarn install
yarn build
```

## Deploy

### New deployment
To deploy Graph Horizon from scratch run the following command:

```bash
npx hardhat run scripts/deploy.ts --network hardhat
```

Note that this will deploy a standalone version of Graph Horizon contracts, meaning the Subgraph Service or any other data service will not be deployed. If you want to deploy the Subgraph Service please refer to the [Subgraph Service README](../subgraph-service/README.md) for deploy instructions.

### Upgrade deployment
To upgrade an existing deployment of the original Graph Protocol to Graph Horizon, run the following command:

```bash
npx hardhat run scripts/migrate.ts --network hardhat
```

Note that this will deploy a standalone version of Graph Horizon contracts, meaning the Subgraph Service or any other data service will not be deployed. If you want to deploy the Subgraph Service please refer to the [Subgraph Service README](../subgraph-service/README.md) for deploy instructions.