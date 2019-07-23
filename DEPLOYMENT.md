## Deploying the Solidity Smart Contracts via Truffle

`/migrations/2_deploy_contracts.js` contains the parameters needed to deploy the contracts. Please edit these params as you see fit.
```
const initialSupply = 1000000, // total supply of Graph Tokens at time of deployment
  minimumCurationStakingAmount = 100, // minimum amount allowed to be staked by Market Curators
  defaultReserveRatio = 500000, // reserve ratio (percent as PPM)
  minimumIndexingStakingAmount = 100, // minimum amount allowed to be staked by Indexing Nodes
  maximumIndexers = 10, // maximum number of Indexing Nodes staked higher than stake to consider
  slashingPercent = 10, // percent of stake to slash in successful dispute
  thawingPeriod = 60 * 60 * 24 * 7, // amount of seconds to wait until indexer can finish stake logout
  multiSigRequiredVote = 0, // votes required (setting a required amount here will override a formula used later)
  multiSigOwners = [] // add addresses of the owners of the multisig contract here
```

The `MultiSigWallet` contract is deployed first in order to retain its address for use in deploying the remaining contracts. 

The `Staking` contract requires both the address of the `MultiSigWallet` and the `GraphToken`.

The order of deployment is as follows:

1. Deploy MultiSigWallet contract
2. Deploy GraphToken Contract
3. Deploy all remaining contracts with the address of the MultiSigWallet, and in the case of the `Staking` contract, use the `GraphToken` address retained previously.
