const BN = require('bn.js')

const TOKEN_UNIT = new BN('10').pow(new BN('18'))

module.exports = {
  curation: {
    // Reserve ratio to set bonding curve for curation (in PPM)
    reserveRatio: 500000,
    // Minimum amount required to be staked by Curators
    minimumCurationStake: new BN('100').mul(TOKEN_UNIT),
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
    maxSettlementEpochs: 5,
    thawingPeriod: 20, // in blocks
  },
  token: {
    initialSupply: new BN('10000000').mul(TOKEN_UNIT),
  },
}
