# 🌅 Graph Horizon 🌅

Graph Horizon is the next evolution of the Graph Protocol.

## Deployment 

We use Hardhat Ignition to deploy the contracts. To build and deploy the contracts run the following commands:

```bash
yarn install
yarn build
npx hardhat ignition deploy ./ignition/modules/horizon.ts \
  --parameters ./ignition/configs/graph.hardhat.json \
  --network hardhat
```

You can use any network defined in `hardhat.config.ts` by replacing `hardhat` with the network name.