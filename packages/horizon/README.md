# 🌅 Graph Horizon 🌅

Graph Horizon is the next evolution of the Graph Protocol.

## Configuration

The following environment variables might be required:

- `ETHERSCAN_API_KEY`: Etherscan API key

You can set them using Hardhat:

```bash
npx hardhat vars set ETHERSCAN_API_KEY
```

## Deployment 

We use Hardhat Ignition to deploy the contracts. To build and deploy Graph Horizon run the following commands:

```bash
yarn install
yarn build
npx hardhat ignition deploy ./ignition/modules/horizon.ts \
  --parameters ./ignition/configs/horizon.hardhat.json5 \
  --network hardhat
```

You can use any network defined in `hardhat.config.ts` by replacing `hardhat` with the network name.

Note that this will deploy a standalone version of Graph Horizon contracts, meaning the Subgraph Service or any other data service will not be deployed. If you want to deploy the Subgraph Service please refer to the [Subgraph Service README](../subgraph-service/README.md) for deploy instructions.
