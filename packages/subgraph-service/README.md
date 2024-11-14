# 🌅 Subgraph Service 🌅

The Subgraph Service is a data service designed to work with Graph Horizon that supports indexing subgraphs and serving queries to consumers.

## Deployment 

We use Hardhat Ignition to deploy the contracts. To build and deploy the Subgraph Service run the following commands:

```bash
yarn install
yarn build
npx hardhat run scripts/deploy.ts --network hardhat
```

You can use any network defined in `hardhat.config.ts` by replacing `hardhat` with the network name.

Note that this will deploy and configure Graph Horizon contracts as well as the Subgraph Service.