## Deploying the Solidity Smart Contracts via Truffle

### Running

A script in `/migrations/2_deploy_contracts.js` deploys the contracts to the specified network.

The script can be run with `npm run deploy`.

### Networks

By default, `npm run deploy` will deploy the contracts to the development network. To deploy to a different network run `npm run deploy -- --network {networkName}`, for example `npm run deploy -- --network ropsten`.

- `{networkName}` must exist as valid network in the `truffle.js` config file.

### Configuration

A configuration file in the `/migrations/deploy.config.js` contains the parameters needed to deploy the contracts. Please edit these params as you see fit.

```
const TOKEN_UNIT = new BN('10').pow(new BN('18'))

{
  curation: {
    reserveRatio: 500000,
    minimumCurationStake: new BN('100').mul(TOKEN_UNIT),
    withdrawalFeePercentage: 50000,
  },
  dispute: {
    minimumDeposit: new BN('100').mul(TOKEN_UNIT),
    fishermanRewardPercentage: 1000, // in basis points
    slashingPercentage: 1000, // in basis points
  },
  epochs: {
    lengthInBlocks: (24 * 60 * 60) / 15, // One day in blocks
  },
  staking: {
    channelDisputeEpochs: 1,
    maxAllocationEpochs: 5,
    thawingPeriod: 20, // in blocks
  },
  token: {
    initialSupply: new BN('10000000').mul(TOKEN_UNIT),
  },
}
```

### Order of deployment

Due to some of the contracts require the address of other contracts, they are deployed in the following order:

1. GraphToken
2. EpochManager
3. Curation
4. Staking
5. RewardsManager
6. DisputeManager
7. ServiceRegistry
8. GNS
